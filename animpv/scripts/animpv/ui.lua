-- Original compact AniMPV panel: shared geometry, vector icons and on-demand frames.
local mp=require 'mp'
local rules=require 'rules'
local previews=require 'preview'
local drawing=require 'drawing'
local M={}
function M.layout(w,h,scale)
    local margin=math.min(16,w/20)
    local width=math.min(w-margin*2,920*(scale or 1))
    local left,bottom=(w-width)/2,h-margin
    local g={left=left,right=left+width,top=math.max(margin,bottom-76),bottom=bottom,
        seek_left=left+18,seek_right=left+width-18,seek_y=bottom-60,compact=width<620,controls={}}
    local function control(name,x,tip,action,arg)
        g.controls[#g.controls+1]={name=name,x1=x-16,x2=x+16,y1=bottom-47,y2=bottom-11,
            cx=x,cy=bottom-29,tip=tip,action=action,arg=arg}
    end
    local spacing=width<480 and 36 or 40
    local x=left+24
    local left_controls={{'menu','Меню · правый клик','menu','main'},
        {'prev','Предыдущая серия · PgUp','prev'},{'play','Пауза · Пробел','pause'},
        {'next','Следующая серия · PgDn','next'}}
    for _,entry in ipairs(left_controls) do
        if width>=280 or (entry[1]~='prev' and entry[1]~='next') then
            control(entry[1],x,entry[2],entry[3],entry[4]); x=x+spacing
        end
    end
    g.time_x=x+12; g.time_above=width<420; g.time_compact=width<620
    local right={}
    if width>=760 then right[#right+1]={'mute','Звук · M','mute'} end
    if width>=350 then right[#right+1]={'audio','Аудиодорожки · A','menu','audio'} end
    if width>=160 then right[#right+1]={'sub','Субтитры · J','menu','sub'} end
    if width>=620 then
        right[#right+1]={'playlist','Серии · P','menu','playlist'}
        right[#right+1]={'history','История · H','menu','history'}
    end
    if width>=124 then right[#right+1]={'fullscreen','Полный экран · F','fullscreen'} end
    for i,item in ipairs(right) do control(item[1],g.right-24-(#right-i)*spacing,item[2],item[3],item[4]) end
    return g
end
function M.seek_fraction(g,x) return math.max(0,math.min(1,(x-g.seek_left)/(g.seek_right-g.seek_left))) end
local function shorten(text,count)
    local chars={}
    for c in tostring(text or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        chars[#chars+1]=c; if #chars>count then chars[#chars]='…'; break end
    end
    return table.concat(chars)
end
local titles={main='Управление',audio='Аудиодорожки',sub='Субтитры',playlist='Серии и плейлист',
    chapters='Главы',history='История просмотра',found='Найденные варианты',help='Клавиши AniMPV'}
function M.new(session,options)
    local self={regions={},index=1,shown_until=mp.get_time()+3,enabled=options.ui,renders=0,
        captured=false,menu_keys={},closed=false,dragging=false,hover=nil,pointer_inside=false,hovering_panel=false}
    local model=session.model
    local overlay=mp.create_osd_overlay('ass-events'); overlay.z=1000
    local preview=previews.new(options,function() self:invalidate() end)
    local function size()
        local w,h=mp.get_osd_size()
        local scale=options.ui_scale*math.max(0.8,math.min(2,h/720))
        return w/scale,h/scale,scale,w,h
    end
    local function mouse()
        local x,y=mp.get_mouse_pos(); local _,_,scale=size()
        return x/scale,y/scale
    end
    local function hit()
        local x,y=mouse()
        if not self.pointer_inside and not self.dragging then return nil,x,y end
        for i=#self.regions,1,-1 do
            local r=self.regions[i]
            if x>=r.x1 and x<=r.x2 and y>=r.y1 and y<=r.y2 then return r,x,y end
        end
        return nil,x,y
    end
    local function publish(w,h,scale,visible,g)
        local geometry
        if g then
            geometry={}
            for _,key in ipairs({'left','right','top','bottom','seek_left','seek_right','seek_y'}) do geometry[key]=g[key]*scale end
        end
        model.ui={width=w,height=h,physical_width=w*scale,physical_height=h*scale,scale=scale,
            visible=visible,renders=self.renders,regions=#self.regions,geometry=geometry,
            dragging=self.dragging,hover=self.hover,preview=preview:stats()}
        session.publish()
    end
    local function unbind_menu()
        for _,name in ipairs(self.menu_keys) do mp.remove_key_binding(name) end
        self.menu_keys={}
    end
    local function seek_at(x)
        local w,h=size(); session:dispatch('seek',M.seek_fraction(M.layout(w,h,1),x))
    end
    local function capture(value)
        value=value or self.dragging
        if value==self.captured then return end
        self.captured=value
        if value then
            self.drag_restore={}
            for _,name in ipairs({'input-builtin-dragging','window-dragging'}) do
                local old=mp.get_property_native(name)
                if type(old)=='boolean' then
                    self.drag_restore[name]=old; mp.set_property_native(name,false)
                end
            end
            mp.add_forced_key_binding('MBTN_LEFT','animpv-pointer',function(event)
                if event.canceled then self.dragging=false; self:invalidate(); return end
                local r,x=hit()
                if event.event=='up' then
                    if self.dragging then seek_at(x); self.dragging=false; self:reveal() end
                elseif event.event=='down' or event.event=='press' then
                    if r and r.seek and model.duration>0 then
                        self.dragging=event.event=='down'; seek_at(x); preview:hide(); self:invalidate()
                    elseif r and r.fn then r.fn()
                    elseif model.menu~='' then self:close() end
                end
            end,{complex=true})
            for _,pair in ipairs({{'WHEEL_UP',-1},{'WHEEL_DOWN',1}}) do
                mp.add_forced_key_binding(pair[1],'animpv-'..pair[1],function()
                    if model.menu~='' then self:move(pair[2])
                    else local r=hit(); session:dispatch(r and r.seek and 'seek-relative' or 'volume',-pair[2]*5) end
                end)
            end
        else
            for name,old in pairs(self.drag_restore or {}) do mp.set_property_native(name,old) end
            self.drag_restore=nil
            for _,name in ipairs({'animpv-pointer','animpv-WHEEL_UP','animpv-WHEEL_DOWN'}) do mp.remove_key_binding(name) end
        end
    end
    function self:visible()
        return model.menu~='' or model.path=='' or model.pause or self.dragging or self.hovering_panel or mp.get_time()<self.shown_until
    end
    function self:move(delta)
        local items=session:items(model.menu)
        self.index=math.max(1,math.min(#items,self.index+delta)); self:invalidate()
    end
    function self:activate(index)
        local item=session:items(model.menu)[index or self.index]
        if not item or not item.action then return end
        self:close(); session:dispatch(item.action,unpack(item.args or {}))
    end
    function self:open(kind)
        self.dragging=false; preview:hide(); model.menu=kind; self.index=1; unbind_menu()
        for _,entry in ipairs({{'UP',function() self:move(-1) end},{'DOWN',function() self:move(1) end},
            {'PGUP',function() self:move(-8) end},{'PGDWN',function() self:move(8) end},
            {'ENTER',function() self:activate() end},{'ESC',function() self:close() end},{'LEFT',function() self:close() end}}) do
            local name='animpv-menu-'..entry[1]; self.menu_keys[#self.menu_keys+1]=name
            mp.add_forced_key_binding(entry[1],name,entry[2],{repeatable=true})
        end
        if self.enabled then capture(true) end
        session:changed(true)
    end
    function self:close()
        model.menu=''; unbind_menu(); self.dragging=false; capture(false); preview:hide()
        self.shown_until=mp.get_time()+2; session:changed(true)
    end
    function self:reveal()
        self.shown_until=mp.get_time()+2.5
        if self.hide_timer then self.hide_timer:kill() end
        self.hide_timer=mp.add_timeout(2.6,function() self:invalidate() end)
        self:invalidate()
    end
    function self:draw()
        self.timer=nil
        if self.closed or not self.enabled then return end
        local w,h,scale,pw,ph=size()
        self.regions={}; self.hover=nil
        if w<=0 or h<=0 or not self:visible() then
            overlay:remove(); preview:hide(); capture(false); publish(w,h,scale,false); return
        end
        local params=mp.get_property_native('video-params') or {}
        preview:set_media(model.path,model.duration,params.dw or params.w or 0,
            params.dh or params.h or 0,mp.get_property('vid','1'),params.rotate or 0)
        local d=drawing.new()
        local function region(x1,y1,x2,y2,fn,seek,tip)
            self.regions[#self.regions+1]={x1=x1,y1=y1,x2=x2,y2=y2,fn=fn,seek=seek,tip=tip}
        end
        local g=M.layout(w,h,1)
        local mx,my=mouse()
        local seeking=self.pointer_inside and mx>=g.seek_left and mx<=g.seek_right and math.abs(my-g.seek_y)<=12 and model.menu==''
        if model.path=='' then
            d:text(w/2,h*0.33,'AniMPV',42,'C9DC7A',5)
            d:text(w/2,h*0.33+52,'Перетащите видео в окно',20,'A4ADAF',5)
            d:text(w/2,h*0.33+84,'Правый клик — меню  ·  F1 — клавиши',14,'849093',5)
        end
        d:rect(g.left,g.top,g.right,g.bottom,'201915','08',12)
        if g.right-g.left>=280 then
            d:text(g.left+8,g.top-23,shorten(model.title,math.max(12,math.floor((g.right-g.left-150)/8))),13,'D7DDE1')
        end
        if g.time_above then d:text(g.right-8,g.top-23,rules.time(model.position)..' / '..rules.time(model.duration),12,'B7C1C7',9) end
        local y=g.seek_y
        local half=(seeking or self.dragging) and 3 or 2
        d:rect(g.seek_left,y-half,g.seek_right,y+half,'54463C','00',half)
        for _,r in ipairs(model.cache_state and model.cache_state['seekable-ranges'] or {}) do
            if model.duration>0 and r.start and r['end'] then
                local a=math.max(0,math.min(1,r.start/model.duration))
                local b=math.max(0,math.min(1,r['end']/model.duration))
                d:rect(g.seek_left+(g.seek_right-g.seek_left)*a,y-half,g.seek_left+(g.seek_right-g.seek_left)*b,y+half,'887463','00',half)
            end
        end
        local ratio=model.duration>0 and math.max(0,math.min(1,model.position/model.duration)) or 0
        local head=g.seek_left+(g.seek_right-g.seek_left)*ratio
        d:rect(g.seek_left,y-half,head,y+half,'C9DC7A','00',half)
        for _,chapter in ipairs(model.chapters) do
            if model.duration>0 and chapter.time>0 and chapter.time<model.duration then
                local x=g.seek_left+(g.seek_right-g.seek_left)*chapter.time/model.duration
                d:rect(x-1,y-half-1,x+1,y+half+1,'201915')
            end
        end
        if half==3 then d:rect(head-5,y-5,head+5,y+5,'E9F4C1','00',5) end
        region(g.seek_left,y-12,g.seek_right,y+12,nil,true)
        for _,c in ipairs(g.controls) do
            local hovered=self.pointer_inside and model.menu=='' and mx>=c.x1 and mx<=c.x2 and my>=c.y1 and my<=c.y2
            if hovered then d:rect(c.x1,c.cy-16,c.x2,c.cy+16,'493B30','00',8) end
            local name=c.name
            if name=='play' then name=model.pause and 'play' or 'pause' end
            if name=='mute' then name=model.mute and 'mute' or 'volume' end
            d:icon(name,c.cx,c.cy,c.name=='play' and 23 or 19,hovered and 'C9DC7A' or 'ECF0F3')
            region(c.x1,c.y1,c.x2,c.y2,function() session:dispatch(c.action,c.arg) end,false,c.tip)
        end
        if not g.time_above then
            d:text(g.time_x,g.bottom-29,g.time_compact and rules.time(model.position) or
                rules.time(model.position)..'  /  '..rules.time(model.duration),g.compact and 12 or 13,'BAC3C9',4)
        end
        if model.status~='' then d:text(g.left+8,g.top-43,shorten(model.status,math.floor((g.right-g.left)/7)),12,'A4ADAF') end
        if model.menu~='' then
            preview:hide(); self.regions={}
            d:rect(0,0,w,h,'100D0B','60')
            local mw,mh=math.min(w-24,650),math.min(h-24,500)
            local x1,y1=(w-mw)/2,(h-mh)/2
            d:rect(x1,y1,x1+mw,y1+mh,'292019','00',14)
            d:text(x1+20,y1+16,titles[model.menu] or 'AniMPV',21,'C9DC7A')
            d:icon('close',x1+mw-26,y1+29,15,'A4ADAF')
            region(x1+mw-46,y1+9,x1+mw-8,y1+48,function() self:close() end)
            local items=session:items(model.menu)
            self.index=math.max(1,math.min(#items,self.index))
            local rows=math.max(1,math.floor((mh-96)/32))
            local first=math.max(1,math.min(self.index-math.floor(rows/2),#items-rows+1))
            if #items==0 then d:text(x1+20,y1+65,'Пока нет элементов',16,'A4ADAF') end
            for i=first,math.min(#items,first+rows-1) do
                local item,top=items[i],y1+57+(i-first)*32
                if i==self.index then d:rect(x1+9,top-1,x1+mw-9,top+29,'493B30','00',6) end
                d:text(x1+18,top+4,shorten((item.selected and '●  ' or '    ')..item.label,math.max(8,math.floor((mw-36)/8))),16,item.selected and 'C9DC7A' or 'ECF0F3')
                local index=i; region(x1+9,top-1,x1+mw-9,top+29,function() self:activate(index) end)
            end
            d:text(x1+20,y1+mh-26,'↑ ↓  выбор   Enter  открыть   Esc  закрыть',12,'A4ADAF')
            d:text(x1+mw-20,y1+mh-26,tostring(#items),12,'A4ADAF',9)
        else
            local r=hit()
            if (seeking or self.dragging) and model.duration>0 then
                local seconds=M.seek_fraction(g,mx)*model.duration
                self.hover={kind='seek',time=seconds}
                if not self.dragging then
                    preview:request(seconds,math.min(240*scale,pw-24),math.min(136*scale,math.max(20,g.top*scale-48)))
                end
                local f=preview.frame
                if f and not self.dragging then
                    local box=previews.placement(mx*scale,g.top*scale,f.width,f.height,pw,ph)
                    preview:show(box.x,box.y)
                    d:rect(box.x/scale-5,box.y/scale-5,(box.x+f.width)/scale+5,(box.y+f.height)/scale+28,'201915','00',8)
                    d:text((box.x+f.width/2)/scale,(box.y+f.height)/scale+15,rules.time(seconds),13,'ECF0F3',5)
                else
                    local tx=math.max(g.left+36,math.min(g.right-36,mx))
                    local ty=math.max(22,g.top-23)
                    d:rect(tx-34,ty-14,tx+34,ty+14,'201915','00',7)
                    d:text(tx,ty,rules.time(seconds),13,'ECF0F3',5)
                end
            else
                if preview.wanted or preview.visible then preview:hide() end
                if r and r.tip then
                    self.hover={kind='control',text=r.tip}
                    local tw=math.min(w-24,#r.tip*4+24)
                    local tx=math.max(tw/2+8,math.min(w-tw/2-8,(r.x1+r.x2)/2))
                    d:rect(tx-tw/2,g.top-36,tx+tw/2,g.top-8,'201915','00',7)
                    d:text(tx,g.top-22,r.tip,13,'ECF0F3',5)
                end
            end
        end
        overlay.res_x,overlay.res_y=w,h; overlay.data=d:result(); overlay:update()
        self.renders=self.renders+1; capture(model.menu~='' or hit()~=nil)
        publish(w,h,scale,true,g)
    end
    function self:invalidate()
        if not self.enabled or self.closed or self.timer then return end
        if not self:visible() then
            if overlay.data~='' then overlay:remove(); overlay.data=''; preview:hide() end
            capture(false)
            local w,h,scale=size(); publish(w,h,scale,false)
            return
        end
        self.timer=mp.add_timeout(self.dragging and 0.02 or 0.04,function() self:draw() end)
    end
    function self:shutdown()
        self.closed=true; unbind_menu(); self.dragging=false; capture(false)
        if self.timer then self.timer:kill() end
        if self.hide_timer then self.hide_timer:kill() end
        preview:shutdown(); overlay:remove()
    end
    mp.observe_property('mouse-pos','native',function(_,value)
        if not self.enabled then return end
        self.pointer_inside=value and value.hover==true or false
        local w,h=size(); local g=M.layout(w,h,1); local mx,my=mouse()
        self.hovering_panel=self.pointer_inside and mx>=g.left and mx<=g.right and my>=g.top and my<=g.bottom
        if value and value.hover==false and not self.dragging then
            preview:hide(); self.hover=nil; self:invalidate(); return
        end
        if self.dragging then
            local x=mouse()
            if not self.last_seek or mp.get_time()-self.last_seek>=0.04 then seek_at(x); self.last_seek=mp.get_time() end
        end
        self:reveal(); capture(model.menu~='' or hit()~=nil)
    end)
    mp.observe_property('osd-dimensions','native',function() preview:hide(); self:invalidate() end)
    mp.observe_property('video-params','native',function() self:invalidate() end)
    self:invalidate()
    return self
end
return M
