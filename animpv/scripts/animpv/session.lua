local mp = require 'mp'
local utils = require 'mp.utils'
local rules = require 'rules'
local M = {}
function M.main_items(candidates,resume_position)
    local list={}
    for _,item in ipairs({{'Аудиодорожки','audio'},{'Субтитры','sub'},{'Серии / плейлист','playlist'},
        {'Главы','chapters'},{'История','history'}}) do
        list[#list+1]={label=item[1],action='menu',args={item[2]}}
    end
    if #candidates>0 then list[#list+1]={label='Варианты файлов',action='menu',args={'found'}} end
    list[#list+1]={label='Продолжить с '..rules.time(resume_position),action='resume'}
    list[#list+1]={label='Клавиши',action='menu',args={'help'}}
    return list
end
local function absolute(path)
    if not path or path == '' then return nil end
    if path:match('^%a[%w+.-]*://') then return path end
    return utils.join_path(mp.get_property('working-directory', ''), path):gsub('\\', '/')
end
local function directory(path) return (path or ''):match('^(.*)/[^/]*$') or '' end
local function is_local(path) return path and not path:match('^%a[%w+.-]*://') end
function M.new(library, history, options)
    local self = {model={ready=true, path='', title='AniMPV', position=0, duration=0,
        pause=true, volume=100, tracks={}, playlist={}, chapters={}, menu='', scan_pending=false,
        status='', resume_position=0, candidates={}}, generation=0, preferences={}, owned_tracks={}, last_save=-math.huge}
    local m = self.model
    local function publish()
        mp.set_property_native('user-data/animpv', {ready=true, path=m.path, menu=m.menu,
            scan_pending=m.scan_pending, resume_position=m.resume_position, status=m.status,
            tracks=#m.tracks, ambiguous=m.ambiguous or 0, index_seconds=m.index_seconds or 0,
            index_reads=library.reads, ui=m.ui})
    end
    self.publish=publish
    function self:changed(major)
        if major then publish() end
        if self.ui then self.ui:invalidate() end
    end
    function self:set_status(text)
        m.status = text; self:changed(true)
    end
    function self:sync_tracks()
        local result = {}
        for _, t in ipairs(mp.get_property_native('track-list', {})) do
            local copy = {}
            for k,v in pairs(t) do copy[k] = v end
            local title = t.title
            local external = t['external-filename']
            local group = external and rules.basename(directory(absolute(external))) or ''
            if not title or title == '' or (external and rules.stem(title) == rules.stem(external)) then
                title = t.lang or t.codec or ('Дорожка ' .. t.id)
            end
            copy.display = (group ~= '' and group .. ' / ' or '') .. title
            copy.key = table.concat({t.type, group, rules.track_key({type=t.type, lang=t.lang, title=title})}, '|')
            result[#result+1] = copy
        end
        m.tracks = result
        self:changed(true)
    end
    function self:save(preference_changed)
        if m.path == '' or m.duration <= 0 then return end
        local old = history:get(m.path)
        -- Merely opening a file at the beginning must not erase a saved resume point.
        local position = m.position >= 5 and m.position or old and old.position or preference_changed and 0
        if not position then return end
        local preference = self.preferences[directory(m.path)] or {}
        local ok = history:save(m.path, {position=position, duration=m.duration,
            audio=preference.audio, sub=preference.sub})
        self.last_save = mp.get_time()
        if not ok then self:set_status('История недоступна: ' .. tostring(history.error or 'ошибка записи')) end
    end
    function self:apply_preferences()
        local preference = self.preferences[directory(m.path)] or {}
        for _, kind in ipairs({'audio', 'sub'}) do
            local key = preference[kind]
            if key == 'off' then mp.set_property(kind == 'audio' and 'aid' or 'sid', 'no')
            elseif key then
                for _, t in ipairs(m.tracks) do
                    if t.type == kind and t.key == key then
                        mp.set_property_number(kind == 'audio' and 'aid' or 'sid', t.id); break
                    end
                end
            end
        end
    end
    local function auto_playlist(result, expected)
        if mp.get_property_number('playlist-count', 0) ~= 1 then return end
        local names, by_name = {}, {}
        for _, path in ipairs(result.videos) do
            local name = rules.basename(path); names[#names+1] = name; by_name[name] = path
        end
        local ordered, duplicates, numbered = rules.videos(names, rules.basename(expected))
        m.ambiguous = #duplicates
        for _, group in ipairs(duplicates) do
            for _, name in ipairs(group) do
                m.candidates[#m.candidates+1] = {label='Версия серии: ' .. name, path=by_name[name], kind='video'}
            end
        end
        local current_index
        for i, name in ipairs(ordered) do
            if by_name[name] == expected then current_index = i - 1
            else mp.commandv('loadfile', by_name[name], 'append') end
        end
        if current_index and current_index > 0 then mp.commandv('playlist-move', 0, current_index+1) end
        if not numbered then m.status = 'Нумерация не определена: обычный список видео' end
    end
    local function track_candidates(result, expected)
        local groups = {}
        for _, field in ipairs({'audio', 'subtitles'}) do
            for _, path in ipairs(result[field]) do
                local score = rules.match(expected, path)
                if score then
                    local key = field .. '|' .. directory(path)
                    local group = groups[key]
                    if not group or score > group.score then groups[key] = {score=score, files={path}, field=field}
                    elseif score == group.score then group.files[#group.files+1] = path end
                end
            end
        end
        local attach = {}
        for _, group in pairs(groups) do
            for _, path in ipairs(group.files) do
                local kind = group.field == 'audio' and 'audio' or 'sub'
                if #group.files == 1 then attach[#attach+1] = {path=path, kind=kind}
                else m.candidates[#m.candidates+1] = {label='Выбрать: ' .. path, path=path, kind=kind} end
            end
        end
        table.sort(attach, function(a,b) return a.path < b.path end)
        return attach
    end
    function self:discover(refresh)
        local expected, generation = m.path, self.generation
        if not is_local(expected) or expected == '' then m.scan_pending=false; self:changed(true); return end
        if refresh then library:refresh() end
        m.scan_pending, m.candidates, m.status = true, {}, 'Поиск дорожек…'
        local started = mp.get_time()
        self:changed(true)
        library:scan(directory(expected), function(result)
            if generation ~= self.generation or absolute(mp.get_property('path')) ~= expected then return end
            auto_playlist(result, expected)
            local attach = track_candidates(result, expected)
            local allowed={}
            for _,field in ipairs({'audio','subtitles'}) do
                for _,path in ipairs(result[field]) do
                    if rules.match(expected,path) then allowed[path]=true end
                end
            end
            local function next_track(index)
                if generation ~= self.generation or absolute(mp.get_property('path')) ~= expected then return end
                local item = attach[index]
                if item then
                    local found = false
                    for _, t in ipairs(mp.get_property_native('track-list', {})) do
                        if absolute(t['external-filename']) == item.path then found = true; break end
                    end
                    if not found then
                        self.owned_tracks[item.path]=true
                        local ok, err = pcall(mp.commandv, item.kind .. '-add', item.path, 'auto')
                        if not ok then m.status = 'Ошибка дорожки: ' .. tostring(err) end
                    end
                    mp.add_timeout(0, function() next_track(index+1) end)
                else
                    -- A core file replacement can race a synchronous *-add already sent.
                    -- Reconcile only AniMPV-owned tracks after the latest discovery finishes.
                    local retained={}
                    for _,track in ipairs(mp.get_property_native('track-list',{})) do
                        local path=absolute(track['external-filename'])
                        if path and self.owned_tracks[path] then
                            if not allowed[path] and (track.type=='audio' or track.type=='sub') then
                                mp.commandv(track.type..'-remove',track.id)
                            else retained[path]=true end
                        end
                    end
                    self.owned_tracks=retained
                    self:sync_tracks(); self:apply_preferences()
                    m.scan_pending = false; m.index_seconds = mp.get_time()-started
                    if result.incomplete then m.status = result.reason .. ' · F5: повторить'
                    elseif #m.candidates > 0 then m.status = 'Есть неоднозначные совпадения · меню «Варианты файлов»'
                    elseif m.status == 'Поиск дорожек…' then m.status = '' end
                    self:changed(true)
                end
            end
            next_track(1)
        end)
    end
    function self:start_file()
        self.generation = self.generation + 1; library:cancel()
        m.path = absolute(mp.get_property('path')) or ''
        m.title = rules.basename(m.path); m.position=0; m.duration=0; m.tracks={}
        m.chapters={}
        m.scan_pending=true; m.resume_position=0; m.status=''; m.candidates={}; m.ambiguous=0
        if self.ui then self.ui:close() end
        self:changed(true)
    end
    function self:file_loaded()
        m.path = absolute(mp.get_property('path')) or ''
        m.title = mp.get_property('media-title', rules.basename(m.path))
        m.duration = mp.get_property_number('duration', 0)
        m.chapters = mp.get_property_native('chapter-list', {})
        local old = history:get(m.path)
        m.resume_position = old and old.position or 0
        local dir = directory(m.path)
        if not self.preferences[dir] then
            local preferred = old
            if not preferred then
                for _, r in ipairs(history:list()) do if directory(r.path) == dir then preferred=r; break end end
            end
            self.preferences[dir] = {audio=preferred and preferred.audio, sub=preferred and preferred.sub}
        end
        self:sync_tracks(); self:discover()
    end
    function self:items(kind)
        local list = {}
        if kind == 'audio' or kind == 'sub' then
            list[1] = {label='Выключено', action='select-track', args={kind, 'no'},
                selected=mp.get_property(kind == 'audio' and 'aid' or 'sid') == 'no'}
            for _, t in ipairs(m.tracks) do
                if t.type == kind then
                    list[#list+1] = {label=t.display .. (t.lang and ' · ' .. t.lang or ''), selected=t.selected,
                        action='select-track', args={kind, t.id}}
                end
            end
        elseif kind == 'playlist' then
            for i, item in ipairs(m.playlist) do
                list[#list+1] = {label=rules.playlist_label(item.filename,item.title), selected=item.current,
                    action='playlist-at', args={i-1}}
            end
        elseif kind == 'chapters' then
            for i, item in ipairs(m.chapters) do
                list[#list+1] = {label=rules.time(item.time) .. '  ' .. rules.chapter_title(item,i),
                    action='seek-time', args={item.time}}
            end
        elseif kind == 'history' then
            for _, item in ipairs(history:list()) do
                list[#list+1] = {label=rules.basename(item.path) .. ' · ' .. rules.time(item.position),
                    action='open', args={item.path}}
            end
        elseif kind == 'found' then
            for _, item in ipairs(m.candidates) do
                list[#list+1] = {label=item.label, action='attach', args={item.kind,item.path}}
            end
        elseif kind == 'help' then
            for _, text in ipairs(options.help or {}) do list[#list+1] = {label=text} end
        else
            return M.main_items(m.candidates,m.resume_position)
        end
        return list
    end
    function self:dispatch(action, a, b)
        if action == 'pause' then mp.commandv('cycle', 'pause')
        elseif action == 'fullscreen' then mp.commandv('cycle', 'fullscreen')
        elseif action == 'mute' then mp.commandv('cycle', 'mute')
        elseif action == 'sub-visible' then mp.commandv('cycle', 'sub-visibility')
        elseif action == 'volume' then mp.commandv('add', 'volume', tonumber(a) or 0)
        elseif action == 'seek' then
            local fraction = tonumber(a)
            if fraction and fraction == fraction and m.duration > 0 then
                mp.commandv('seek', math.max(0, math.min(1, fraction))*m.duration, 'absolute+exact')
            end
        elseif action == 'seek-time' then
            local t = tonumber(a); if t and t == t and t >= 0 then mp.commandv('seek', t, 'absolute+exact') end
        elseif action == 'seek-relative' then mp.commandv('seek', tonumber(a) or 0, 'relative+exact')
        elseif action == 'resume' then
            if m.resume_position > 0 then mp.commandv('seek', m.resume_position, 'absolute+exact')
            else mp.osd_message('Сохранённой позиции нет') end
        elseif action == 'prev' or action == 'next' then mp.commandv('playlist-' .. action, 'weak')
        elseif action == 'playlist-at' then
            local n = tonumber(a); if n and n >= 0 and n < #m.playlist then mp.set_property_number('playlist-pos', n) end
        elseif action == 'select-track' and (a == 'audio' or a == 'sub') then
            local key
            if b == 'no' then key = 'off'
            else for _, t in ipairs(m.tracks) do if t.type == a and t.id == tonumber(b) then key=t.key; break end end end
            if key then
                mp.set_property(a == 'audio' and 'aid' or 'sid', b)
                self.preferences[directory(m.path)] = self.preferences[directory(m.path)] or {}
                self.preferences[directory(m.path)][a] = key
                self:save(true)
            end
        elseif action == 'attach' and b then
            if a == 'video' then mp.commandv('loadfile', b, 'replace')
            elseif a == 'audio' or a == 'sub' then mp.commandv(a .. '-add', b, 'cached') end
        elseif action == 'open' and a then mp.commandv('loadfile', a, 'replace')
        elseif action == 'refresh' then self:discover(true)
        elseif action == 'menu' then if self.ui then self.ui:open(a or 'main') end
        elseif action == 'menu-close' then if self.ui then self.ui:close() end
        elseif action == 'show-ui' then if self.ui then self.ui:reveal() end
        end
        self:changed(true)
    end
    mp.register_script_message('action', function(...) self:dispatch(...) end)
    mp.register_event('start-file', function() self:start_file() end)
    mp.register_event('file-loaded', function() self:file_loaded() end)
    mp.register_event('end-file', function() self:save(); library:cancel() end)
    mp.register_event('shutdown', function() self:save(); library:cancel(); if self.ui then self.ui:shutdown() end end)
    mp.observe_property('time-pos', 'number', function(_, value)
        if value then m.position=value end
        if value and value >= 5 and mp.get_time()-self.last_save > options.save_interval then self:save() end
        self:changed(false)
    end)
    for property, field in pairs({pause='pause', volume='volume', mute='mute', duration='duration',
        playlist='playlist', ['chapter-list']='chapters', ['track-list']='tracks',
        ['demuxer-cache-state']='cache_state'}) do
        mp.observe_property(property, 'native', function(_, value)
            if property == 'track-list' then self:sync_tracks()
            else if value ~= nil then m[field]=value end; self:changed(property ~= 'volume') end
        end)
    end
    publish()
    return self
end
return M
