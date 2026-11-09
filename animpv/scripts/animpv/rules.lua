-- AniMPV's media rules. No filesystem or mpv state in this module.
local M = {}
local extensions = {
    video = ' mkv mp4 webm avi mov m4v mpg mpeg ts m2ts ogm ',
    audio = ' mka flac aac ac3 eac3 dts wav mp3 ogg opus m4a ',
    sub = ' ass ssa srt vtt sub idx sup ',
}

function M.basename(path) return (path or ''):gsub('\\', '/'):match('([^/]*)$') end
function M.stem(path) return M.basename(path):gsub('%.[^.]+$', '') end
function M.lower(value)
    local text = (value or ''):lower()
    -- Lua's bytewise lower() does not case-fold Russian release names.
    return (text:gsub('[\208\209][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        if a == 208 and b >= 144 and b <= 159 then return string.char(208, b + 32) end
        if a == 208 and b >= 160 and b <= 175 then return string.char(209, b - 32) end
        if a == 208 and b == 129 then return '\209\145' end
        return pair
    end))
end
function M.kind(path)
    local ext = M.lower(path):match('%.([^.]+)$')
    if ext then
        for kind, list in pairs(extensions) do
            if list:find(' ' .. ext .. ' ', 1, true) then return kind end
        end
    end
end
local function clean(text)
    text = text:gsub('%b[]', ' '):gsub('%b()', ' ')
    return (text:gsub('[%s%p_]+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end
function M.episode(path)
    local text = M.lower(M.stem(path))
    for _, special in ipairs({'op', 'ed', 'ncop', 'nced', 'pv', 'trailer'}) do
        if text:find('%f[%a]' .. special .. '%f[%A]') then return nil end
    end
    local first, last, season, number = text:find('s(%d%d?)e(%d%d?%d?)')
    if not first then first, last, season, number = text:find('%f[%d](%d%d?)x(%d%d?%d?)%f[%D]') end
    if not first then
        first, last, number = text:find('%[%s*(%d%d?%d?)%s*%]')
        if not first then first, last, number = text:find('%-%s*(%d%d?%d?)%f[%D]') end
        if not first then
            local stripped = text:gsub('%b[]', ''):gsub('%b()', '')
                :gsub('[._]([%a]+)$', ''):gsub('%s+$', '')
            first, last, number = stripped:find('(%d+)%s*$')
            text = stripped
        end
        season = '1'
    end
    number, season = tonumber(number), tonumber(season)
    if not first or not number or number < 1 or number > 999 or not season then return nil end
    -- A partial match must not turn 1080 or 2024 into episode 108/202.
    if text:sub(last + 1, last + 1):match('%d') then return nil end
    return {season = season, number = number, series = clean(text:sub(1, first - 1))}
end
function M.natural_less(a, b)
    local x, y = M.lower(a), M.lower(b)
    local ix, iy = 1, 1
    while ix <= #x and iy <= #y do
        local nx, ny = x:sub(ix):match('^%d+'), y:sub(iy):match('^%d+')
        if nx and ny then
            local ax, ay = nx:gsub('^0+', ''), ny:gsub('^0+', '')
            if #ax ~= #ay then return #ax < #ay end
            if ax ~= ay then return ax < ay end
            ix, iy = ix + #nx, iy + #ny
        else
            local cx, cy = x:sub(ix, ix), y:sub(iy, iy)
            if cx ~= cy then return cx < cy end
            ix, iy = ix + 1, iy + 1
        end
    end
    if #x - ix ~= #y - iy then return #x - ix < #y - iy end
    return a < b
end
function M.match(video, candidate)
    local v, c = M.lower(M.stem(video)), M.lower(M.stem(candidate))
    if v == c then return 100 end
    if c:sub(1, #v + 1) == v .. '.' then return 95 end
    local ve, ce = M.episode(video), M.episode(candidate)
    if not ve or not ce or ve.season ~= ce.season or ve.number ~= ce.number then return nil end
    if ve.series ~= '' and ce.series ~= '' and ve.series ~= ce.series then return nil end
    return ve.series == ce.series and 80 or 60
end
function M.videos(files, current)
    local candidates, groups, ambiguous, result = {}, {}, {}, {}
    local now = M.episode(current)
    for _, file in ipairs(files) do
        if M.kind(file) == 'video' then
            local e = M.episode(file)
            if not now or (e and e.series == now.series and e.season == now.season) then
                candidates[#candidates + 1] = file
                if now then
                    local key = tostring(e.number)
                    groups[key] = groups[key] or {}; table.insert(groups[key], file)
                end
            end
        end
    end
    if now then
        for _, group in pairs(groups) do
            table.sort(group, M.natural_less)
            if #group == 1 then result[#result + 1] = group[1]
            else
                ambiguous[#ambiguous + 1] = group
                for _, file in ipairs(group) do
                    if file == current then result[#result + 1] = file end
                end
            end
        end
    else result = candidates end
    table.sort(result, function(a,b)
        if now then
            local ae,be=M.episode(a),M.episode(b)
            if ae.number ~= be.number then return ae.number < be.number end
        end
        return M.natural_less(a,b)
    end)
    table.sort(ambiguous, function(a,b) return M.natural_less(a[1],b[1]) end)
    return result, ambiguous, now ~= nil
end
function M.track_key(track)
    return table.concat({track.type or '', M.lower(track.lang), M.lower(track.title)}, '|')
end
function M.escape(text)
    return tostring(text or ''):gsub('[%z\1-\31\127]', ' ')
        :gsub('\\', '＼'):gsub('{', '｛'):gsub('}', '｝')
end
function M.time(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds >= 3600 then
        return string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format('%02d:%02d', math.floor(seconds / 60), seconds % 60)
end
return M
