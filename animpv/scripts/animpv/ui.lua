-- Original AniMPV interface, drawn as an ASS overlay using mpv's Lua API.
local mp = require 'mp'
local rules = require 'rules'
local M = {}
function M.layout(w, h, scale)
    local margin = math.min(16, w/20)
    local width = math.min(w-margin*2, 1120*(scale or 1))
    local left, bottom = (w-width)/2, h-margin
    return {left=left, right=left+width, top=math.max(margin,bottom-126), bottom=bottom,
        seek_left=left+18, seek_right=left+width-18, seek_y=math.max(margin,bottom-126)+42,
        compact=width<620}
end
local function shorten(text, count)
    local chars = {}
    for c in tostring(text or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        chars[#chars+1] = c
        if #chars > count then chars[#chars]='…'; break end
    end
    return table.concat(chars)
end
local titles = {main='Управление', audio='Аудиодорожки', sub='Субтитры', playlist='Серии и плейлист',
    chapters='Главы', history='История просмотра', found='Найденные варианты', help='Клавиши AniMPV'}
function M.new(session, options)
    local self = {regions={}, index=1, shown_until=mp.get_time()+3, enabled=options.ui,
        renders=0, captured=false, menu_keys={}, closed=false}
    local model = session.model
    local overlay = mp.create_osd_overlay('ass-events')
    overlay.z = 1000
    local function size()
        local w,h = mp.get_osd_size()
        local scale = options.ui_scale * math.max(0.8, math.min(2, h/720))
        return w/scale, h/scale, scale
    end
    local function mouse()
        local x,y = mp.get_mouse_pos()
        local _,_,scale = size()
        return x/scale,y/scale
    end
    local function inside(r,x,y) return x>=r.x1 and x<=r.x2 and y>=r.y1 and y<=r.y2 end
    local function hit()
        local x,y = mouse()
        for i=#self.regions,1,-1 do if inside(self.regions[i],x,y) then return self.regions[i],x,y end end
    end
    local function unbind_menu()
        for _, name in ipairs(self.menu_keys) do mp.remove_key_binding(name) end
        self.menu_keys = {}
    end
    local function capture(value)
        if value == self.captured then return end
        self.captured=value
        if value then
            mp.add_forced_key_binding('MBTN_LEFT', 'animpv-pointer', function()
                local r,x = hit()
                if r and r.seek then session:dispatch('seek', (x-r.x1)/(r.x2-r.x1))
                elseif r and r.fn then r.fn()
                elseif model.menu ~= '' then self:close() end
            end)
            for _, pair in ipairs({{'WHEEL_UP',-1},{'WHEEL_DOWN',1}}) do
                mp.add_forced_key_binding(pair[1], 'animpv-' .. pair[1], function()
                    if model.menu ~= '' then self:move(pair[2])
                    else
                        local r = hit()
                        session:dispatch(r and r.seek and 'seek-relative' or 'volume', -pair[2]*5)
                    end
                end)
            end
        else
            mp.remove_key_binding('animpv-pointer')
            mp.remove_key_binding('animpv-WHEEL_UP'); mp.remove_key_binding('animpv-WHEEL_DOWN')
        end
    end
    function self:visible()
        return model.menu ~= '' or model.path == '' or model.pause or mp.get_time() < self.shown_until
    end
    function self:move(delta)
        local items = session:items(model.menu)
        self.index=math.max(1,math.min(#items,self.index+delta)); self:invalidate()
    end
    function self:activate(index)
        local item = session:items(model.menu)[index or self.index]
        if not item or not item.action then return end
        self:close()
        session:dispatch(item.action, unpack(item.args or {}))
    end
    function self:open(kind)
        model.menu, self.index = kind, 1
        unbind_menu()
        for _, entry in ipairs({{'UP',function() self:move(-1) end}, {'DOWN',function() self:move(1) end},
            {'PGUP',function() self:move(-8) end}, {'PGDWN',function() self:move(8) end},
            {'ENTER',function() self:activate() end}, {'ESC',function() self:close() end},
            {'LEFT',function() self:close() end}}) do
            local name = 'animpv-menu-' .. entry[1]
            self.menu_keys[#self.menu_keys+1] = name
            mp.add_forced_key_binding(entry[1], name, entry[2], {repeatable=true})
        end
        if self.enabled then capture(true) end
        session:changed(true)
    end
    function self:close()
        model.menu = ''; unbind_menu(); capture(false)
        self.shown_until = mp.get_time()+2
        session:changed(true)
    end
    function self:reveal()
        self.shown_until = mp.get_time()+2.5
        if self.hide_timer then self.hide_timer:kill() end
        self.hide_timer=mp.add_timeout(2.6,function() self:invalidate() end)
        self:invalidate()
    end
    function self:draw()
        self.timer=nil
        if self.closed or not self.enabled then return end
        local w,h = size()
        self.regions={}
        if w<=0 or h<=0 then overlay:remove(); capture(false); return end
        if not self:visible() then overlay:remove(); capture(false); return end
        local parts = {}
        local function rect(x1,y1,x2,y2,color,alpha)
            parts[#parts+1]=string.format('{\\an7\\pos(0,0)\\bord0\\shad0\\c&H%s&\\alpha&H%s&\\p1}m %.1f %.1f l %.1f %.1f %.1f %.1f %.1f %.1f{\\p0}',
                color,alpha or '00',x1,y1,x2,y1,x2,y2,x1,y2)
        end
        local function text(x,y,value,font,color,align)
            parts[#parts+1]=string.format('{\\an%d\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\bord0\\shad0\\alpha&H00&\\c&H%s&}%s',
                align or 7,x,y,font or 17,color or 'E8EDEF',rules.escape(value))
        end
        local function region(x1,y1,x2,y2,fn,seek)
            self.regions[#self.regions+1]={x1=x1,y1=y1,x2=x2,y2=y2,fn=fn,seek=seek}
        end
        local g = M.layout(w,h,1)
        if model.path == '' then
            text(w/2,h*0.32,'AniMPV',44,'C9DC7A',5)
            text(w/2,h*0.32+52,'Перетащите видео в окно',21,'A4ADAF',5)
            text(w/2,h*0.32+85,'Правый клик — меню  ·  F1 — клавиши',15,'849093',5)
        end
        rect(g.left,g.top,g.right,g.bottom,'241D18','08')
        rect(g.left,g.top,g.left+3,g.bottom,'C9DC7A')
        text(g.left+18,g.top+9,shorten(model.path == '' and 'Готов к просмотру' or model.title,
            math.max(12,math.floor((g.right-g.left-160)/9))),17)
        text(g.right-18,g.top+10,rules.time(model.position) .. ' / ' .. rules.time(model.duration),15,'A9B2B5',9)
        local y=g.seek_y
        rect(g.seek_left,y-2,g.seek_right,y+2,'55483F')
        local ratio=model.duration>0 and math.max(0,math.min(1,model.position/model.duration)) or 0
        rect(g.seek_left,y-2,g.seek_left+(g.seek_right-g.seek_left)*ratio,y+2,'C9DC7A')
        region(g.seek_left,y-12,g.seek_right,y+12,nil,true)
        local buttons = g.compact and {
            {'☰','menu','main'},{'‹','prev'},{model.pause and '▶' or 'Ⅱ','pause'}, {'›','next'},
            {'A','menu','audio'},{'CC','menu','sub'},{'⛶','fullscreen'},
        } or {
            {'Меню','menu','main'},{'‹','prev'},{model.pause and '▶' or 'Ⅱ','pause'}, {'›','next'},
            {'Аудио','menu','audio'},{'Субтитры','menu','sub'},{'Серии','menu','playlist'},
            {'История','menu','history'},{'⛶','fullscreen'},
        }
        local bx,by = g.left+12,g.top+62
        local button_w=(g.right-g.left-24)/#buttons
        local mx,my=mouse()
        for _, button in ipairs(buttons) do
            local x=bx
            if mx>=x and mx<x+button_w-4 and my>=by and my<=by+29 then rect(x,by,x+button_w-4,by+29,'4A3C31') end
            text(x+button_w/2-2,by+14,button[1],g.compact and 16 or 17,'E8EDEF',5)
            region(x,by,x+button_w-4,by+29,function() session:dispatch(button[2],button[3]) end)
            bx=bx+button_w
        end
        local hint = model.status
        if hint == '' then
            hint = (model.mute and 'Звук выключен' or 'Громкость ' .. math.floor(model.volume) .. '%')
            if model.resume_position > 0 then hint=hint .. '  ·  Ctrl+R: ' .. rules.time(model.resume_position) end
        end
        text(g.left+18,g.top+101,shorten(hint,math.max(16,math.floor((g.right-g.left-30)/7))),13,'A4ADAF')
        if model.menu ~= '' then
            -- The modal owns hit testing; covered playback controls cannot receive clicks.
            self.regions={}
            rect(0,0,w,h,'100D0B','60')
            local mw,mh=math.min(w-24,720),math.min(h-24,540)
            local x1,y1=(w-mw)/2,(h-mh)/2
            rect(x1,y1,x1+mw,y1+mh,'292019')
            text(x1+22,y1+18,titles[model.menu] or 'AniMPV',23,'C9DC7A')
            text(x1+mw-22,y1+22,'Закрыть ×',14,'A4ADAF',9)
            region(x1+mw-125,y1+12,x1+mw-10,y1+48,function() self:close() end)
            local items=session:items(model.menu)
            self.index=math.max(1,math.min(#items,self.index))
            local rows=math.max(1,math.floor((mh-100)/34))
            local first=math.max(1,math.min(self.index-math.floor(rows/2),#items-rows+1))
            if #items == 0 then text(x1+22,y1+70,'Пока нет элементов',17,'A4ADAF') end
            for i=first,math.min(#items,first+rows-1) do
                local item,row=items[i],i-first
                local top=y1+60+row*34
                if i == self.index then rect(x1+10,top-1,x1+mw-10,top+31,'493B30') end
                local label=(item.selected and '●  ' or '    ') .. item.label
                text(x1+20,top+4,shorten(label,math.max(8,math.floor((mw-40)/8.5))),17,
                    item.selected and 'C9DC7A' or 'E8EDEF')
                local index=i
                region(x1+10,top-1,x1+mw-10,top+31,function() self:activate(index) end)
            end
            text(x1+22,y1+mh-28,'↑ ↓  выбор   Enter  открыть   Esc  закрыть',13,'A4ADAF')
            text(x1+mw-22,y1+mh-28,tostring(#items) .. ' элементов',13,'A4ADAF',9)
        end
        overlay.res_x,overlay.res_y=w,h
        overlay.data=table.concat(parts,'\n'); overlay:update()
        self.renders=self.renders+1
        model.ui={width=w,height=h,visible=true,renders=self.renders,regions=#self.regions}
        capture(model.menu~='' or hit()~=nil)
    end
    function self:invalidate()
        if not self.enabled or self.closed or self.timer then return end
        -- Hidden playback produces no periodic draw loop; reveal/resize schedules one.
        if not self:visible() then
            if overlay.data ~= '' then overlay:remove(); overlay.data='' end
            capture(false); return
        end
        self.timer=mp.add_timeout(0.08,function() self:draw() end)
    end
    function self:shutdown()
        self.closed=true; unbind_menu(); capture(false)
        if self.timer then self.timer:kill() end
        if self.hide_timer then self.hide_timer:kill() end
        overlay:remove()
    end
    mp.observe_property('mouse-pos','native',function()
        if not self.enabled then return end
        self:reveal()
        capture(model.menu~='' or hit()~=nil)
    end)
    mp.observe_property('osd-dimensions','native',function() self:invalidate() end)
    self:invalidate()
    return self
end
return M
