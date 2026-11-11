-- Original compact AniMPV panel: shared geometry, vector icons and on-demand frames.
local mp=require 'mp'
local rules=require 'rules'
local previews=require 'preview'
local drawing=require 'drawing'
local M={}
function M.layout(w,h,scale)
    local margin=math.min(12,w/20)
    local width=math.min(w-margin*2,760*(scale or 1))
    local left,bottom=(w-width)/2,h-margin
    local g={left=left,right=left+width,top=math.max(margin,bottom-56),bottom=bottom,
        seek_left=left+12,seek_right=left+width-12,seek_y=bottom-46,controls_y=bottom-22,controls={}}
    local function control(name,x,tip,action,arg)
        g.controls[#g.controls+1]={name=name,x1=x-15,x2=x+15,y1=bottom-38,y2=bottom-6,
            cx=x,cy=g.controls_y,tip=tip,action=action,arg=arg}
        if name=='play' then g.play_x=x end
        if name=='menu' then g.menu_x=x end
    end
    local spacing=width<480 and 32 or 34
    local x=left+20
    local left_controls={{'menu','Меню','menu','main'},
        {'prev','Предыдущая серия · PgUp','prev'},{'play','Пауза · Пробел','pause'},
        {'next','Следующая серия · PgDn','next'}}
    for _,entry in ipairs(left_controls) do
        if width>=280 or (entry[1]~='prev' and entry[1]~='next') then
            control(entry[1],x,entry[2],entry[3],entry[4]); x=x+spacing
        end
    end
    g.time_x=x+6; g.time_above=width<400; g.time_compact=width<580
    local right={}
    if width>=760 then right[#right+1]={'mute','Звук · M','mute'} end
    if width>=350 then right[#right+1]={'audio','Аудиодорожки · A','menu','audio'} end
    if width>=160 then right[#right+1]={'sub','Субтитры · J','menu','sub'} end
    if width>=580 then
        right[#right+1]={'playlist','Серии · P','menu','playlist'}
        right[#right+1]={'history','История · H','menu','history'}
    end
    if width>=124 then right[#right+1]={'fullscreen','Полный экран · F','fullscreen'} end
    for i,item in ipairs(right) do control(item[1],g.right-20-(#right-i)*spacing,item[2],item[3],item[4]) end
    return g
end
function M.seek_fraction(g,x) return math.max(0,math.min(1,(x-g.seek_left)/(g.seek_right-g.seek_left))) end
local utf8_char='[%z\1-\127\194-\244][\128-\191]*'
local function shorten(text,count)
    local chars={}
    for c in tostring(text or ''):gmatch(utf8_char) do
        chars[#chars+1]=c; if #chars>count then chars[#chars]='…'; break end
    end
    return table.concat(chars)
end
local function character_count(text)
    local _,count=text:gsub('[^\128-\191]','')
    return count
end
local function title_units(text)
    local width=0
    for char in text:gmatch(utf8_char) do
        -- Estimate advances in ems; reserve a full em for wide glyphs such as CJK.
        local wide=#char>=3 or char:match('[MW@]') or char=='Ж' or char=='Ш' or char=='Щ'
        width=width+(char==' ' and 0.4 or wide and 1 or 0.75)
    end
    return width
end
local function wrap_title(title,limit)
    local lines,parts,length={},{},0
    local function flush()
        lines[#lines+1]=table.concat(parts)
        parts,length={},0
    end
    for word in title:gmatch('%S+') do
        local width=title_units(word)
        if length>0 and length+width+0.4>limit then flush() end
        if length>0 then parts[#parts+1]=' '; length=length+0.4 end
        parts[#parts+1]=word; length=length+width
    end
    if length>0 then flush() end
    return lines
end
function M.chapter_hint(title,stamp,max_width,max_height)
    local width_limit=math.min(max_width,680)
    local width=math.min(width_limit,math.max(96,character_count(title)*10+16))
    local font,pad=13,4
    while true do
        local lines=wrap_title(title,math.max(1,(width-16)/font))
        local row_height=font+2
        local stamp_font=math.min(12,font)
        local last_width=math.min(width-16,title_units(lines[#lines] or '')*font)
        local stamp_row=#lines+(last_width+#stamp*stamp_font+8>width-16 and 1 or 0)
        local height=2*pad+row_height*stamp_row
        if height<=max_height or font<=4 then
            return {width=width,height=height,lines=lines,font=font,row_height=row_height,
                stamp_row=stamp_row,stamp_font=stamp_font,pad=pad}
        end
        if width<width_limit then width=width_limit else font=font-1 end
    end
end
local function chapter_at(chapters,seconds)
    for i=#chapters,1,-1 do
        local chapter=chapters[i]
        if chapter.time<=seconds then return rules.chapter_title(chapter,i),chapter.time end
    end
end
local titles={main='Меню',audio='Аудиодорожки',sub='Субтитры',playlist='Серии и плейлист',
    chapters='Главы',history='История просмотра',found='Варианты файлов',help='Клавиши AniMPV'}
function M.new(session,options)
    local self={regions={},index=1,shown_until=0,enabled=options.ui,renders=0,
        captured=false,menu_keys={},closed=false,dragging=false,hover=nil,pointer_inside=false,
        last_ui_click=-math.huge}
    local model=session.model
    local overlay=mp.create_osd_overlay('ass-events'); overlay.z=1000
    local preview=previews.new(options,function() self:invalidate() end)
    local cursor_restore
    if self.enabled then
        cursor_restore={hide=mp.get_property_native('cursor-autohide'),
            fs_only=mp.get_property_native('cursor-autohide-fs-only')}
        mp.set_property_native('cursor-autohide-fs-only',false)
    end
    local function sync_cursor(visible)
        if not self.enabled or self.cursor_visible==visible then return end
        self.cursor_visible=visible
        mp.set_property_native('cursor-autohide',visible and 'no' or 'always')
    end
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
    local function publish(w,h,scale,visible,g,chapter)
        local geometry
        if g then
            geometry={}
            for _,key in ipairs({'left','right','top','bottom','seek_left','seek_right','seek_y','play_x','menu_x','controls_y'}) do
                geometry[key]=g[key]*scale
            end
        end
        model.ui={width=w,height=h,physical_width=w*scale,physical_height=h*scale,scale=scale,
            visible=visible,renders=self.renders,regions=#self.regions,geometry=geometry,
            dragging=self.dragging,hover=self.hover,chapter=chapter,preview=preview:stats()}
        session.publish()
    end
    local function unbind_menu()
        for _,name in ipairs(self.menu_keys) do mp.remove_key_binding(name) end
        self.menu_keys={}
    end
    local function seek_at(x)
        local w,h=size(); session:dispatch('seek',M.seek_fraction(M.layout(w,h,1),x))
    end
    local function click_interval()
        return mp.get_property_number('input-doubleclick-time',300)/1000
    end
    local function cancel_video_click()
        self.video_down=false
        if self.video_click_timer then self.video_click_timer:kill(); self.video_click_timer=nil end
    end
    local function consume_ui_click()
        self.last_ui_click=mp.get_time()
        cancel_video_click()
        self:reveal()
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
                    if r or model.menu~='' then consume_ui_click() end
                    if r and r.seek and model.duration>0 then
                        self.dragging=event.event=='down'; seek_at(x); preview:hide(); self:invalidate()
                    elseif r and r.fn then r.fn()
                    elseif model.menu~='' then self:close() end
                end
            end,{complex=true})
            for _,pair in ipairs({{'WHEEL_UP',-1},{'WHEEL_DOWN',1}}) do
                mp.add_forced_key_binding(pair[1],'animpv-'..pair[1],function()
                    self:reveal()
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
        return model.menu~='' or model.path=='' or self.dragging or mp.get_time()<self.shown_until
    end
    local function on_video()
        if self.closed or model.path=='' or model.menu~='' or self.dragging then return false end
        if self.enabled and self:visible() then
            local w,h=size(); local g=M.layout(w,h,1); local x,y=mouse()
            if x>=g.left and x<=g.right and y>=g.top and y<=g.bottom then return false end
        end
        return true
    end
    local function after_ui_click()
        -- The first click may already have closed the menu before the second arrives.
        return mp.get_time()-self.last_ui_click<=click_interval()
    end
    local function queue_pause()
        if self.video_click_timer then
            -- Another completed click without a double-click event is a separate single click.
            self.video_click_timer:kill()
            session:dispatch('pause')
        end
        self.video_click_timer=mp.add_timeout(click_interval(),function()
            self.video_click_timer=nil
            session:dispatch('pause')
        end)
    end
    mp.add_key_binding(nil,'video-click',function(event)
        if event.canceled then self.video_down=false; return end
        if event.event=='down' or event.event=='press' then
            if not on_video() then consume_ui_click(); return end
            if after_ui_click() then return end
            self:reveal()
            if event.event=='down' then self.video_down=true else queue_pause() end
        elseif event.event=='up' then
            local down=self.video_down
            self.video_down=false
            if down and on_video() then queue_pause() end
        end
    end,{complex=true})
    mp.register_script_message('video-double-click',function()
        cancel_video_click()
        if on_video() and not after_ui_click() then self:reveal(); session:dispatch('fullscreen') end
    end)
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
        cancel_video_click()
        self.dragging=false; self.regions={}; preview:hide(); model.menu=kind; self.index=1; unbind_menu()
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
        cancel_video_click()
        model.menu=''; self.regions={}; unbind_menu(); self.dragging=false; capture(false); preview:hide()
        self:reveal(); session:changed(true)
    end
    function self:reveal(paused)
        if not self.enabled or self.closed then return end
        if paused==nil then paused=model.pause end
        local delay=paused and 2 or 1
        self.shown_until=mp.get_time()+delay
        if self.hide_timer then self.hide_timer:kill() end
        self.hide_timer=mp.add_timeout(delay,function()
            self.hide_timer=nil
            self:invalidate()
        end)
        self:invalidate()
    end
    local function draw_menu(d,w,h,region)
        local items=session:items(model.menu)
        self.index=math.max(1,math.min(#items,self.index))
        local row,header,pad=26,36,6
        local mw=math.min(w-20,model.menu=='main' and 288 or 380)
        local rows=math.max(1,math.floor((h-20-header-pad)/row))
        local footer=#items>rows and 18 or 0
        rows=math.max(1,math.min(math.max(1,#items),math.floor((h-20-header-pad-footer)/row)))
        local mh=header+rows*row+pad+footer
        local x1,y1=(w-mw)/2,(h-mh)/2
        local x2=x1+mw
        local first=math.max(1,math.min(self.index-math.floor(rows/2),#items-rows+1))
        d:rect(0,0,w,h,'100D0B','A8')
        d:rect(x1,y1,x2,y1+mh,'201915','00',9)
        d:text(x1+14,y1+18,titles[model.menu] or 'AniMPV',17,'ECF0F3',4)
        local close=region(x2-34,y1+4,x2-6,y1+32,function() self:close() end)
        close.menu_close=true
        if #items==0 then d:text(x1+14,y1+header+row/2,'Пока нет элементов',14,'A4ADAF',4) end
        for i=first,math.min(#items,first+rows-1) do
            local top=y1+header+(i-first)*row
            local index=i
            local r=region(x1+5,top,x2-5,top+row,function() self:activate(index) end)
            if items[i].action then r.menu_index=i end
        end
        local hovered=hit()
        local close_hovered=hovered==close
        if close_hovered then
            d:rect(close.x1,close.y1,close.x2,close.y2,'493B30','00',5)
            self.hover={kind='menu-close'}
        end
        d:icon('close',x2-20,y1+18,13,close_hovered and 'ECF0F3' or 'A4ADAF')
        local hovered_index=hovered and hovered.menu_index
        for i=first,math.min(#items,first+rows-1) do
            local item,top=items[i],y1+header+(i-first)*row
            if i==hovered_index then
                d:rect(x1+5,top,x2-5,top+row,'493B30','00',5)
                self.hover={kind='menu-item',index=i}
            elseif i==self.index and not hovered_index then
                d:rect(x1+5,top,x2-5,top+row,'342A23','00',5)
            end
            if i==self.index then d:rect(x1+5,top+6,x1+7,top+row-6,'C9DC7A','00',1) end
            if item.selected then d:rect(x1+13,top+row/2-2,x1+17,top+row/2+2,'C9DC7A','00',2) end
            d:text(x1+23,top+row/2,shorten(item.label,math.max(6,math.floor((mw-32)/8))),15,
                item.selected and 'C9DC7A' or 'ECF0F3',4)
        end
        if footer>0 then d:text(x2-12,y1+mh-5,self.index..' / '..#items,11,'A4ADAF',3) end
    end
    function self:draw()
        self.timer=nil
        if self.closed or not self.enabled then return end
        local w,h,scale,pw,ph=size()
        self.regions={}; self.hover=nil
        if w<=0 or h<=0 or not self:visible() then
            overlay:remove(); sync_cursor(false); preview:hide(); capture(false); publish(w,h,scale,false); return
        end
        local d=drawing.new()
        local function region(x1,y1,x2,y2,fn,seek,tip)
            local r={x1=x1,y1=y1,x2=x2,y2=y2,fn=fn,seek=seek,tip=tip}
            self.regions[#self.regions+1]=r
            return r
        end
        local function finish(g,chapter)
            overlay.res_x,overlay.res_y=w,h; overlay.data=d:result(); overlay:update()
            sync_cursor(true)
            self.renders=self.renders+1; capture(model.menu~='' or hit()~=nil)
            publish(w,h,scale,true,g,chapter)
        end
        if model.menu~='' then
            draw_menu(d,w,h,region)
            finish()
            return
        end
        local params=mp.get_property_native('video-params') or {}
        preview:set_media(model.path,model.duration,params.dw or params.w or 0,
            params.dh or params.h or 0,mp.get_property('vid','1'),params.rotate or 0)
        local g=M.layout(w,h,1)
        local mx,my=mouse()
        local seeking=self.pointer_inside and mx>=g.seek_left and mx<=g.seek_right and math.abs(my-g.seek_y)<=8
        if model.path=='' then
            d:text(w/2,h*0.33,'AniMPV',32,'C9DC7A',5)
            d:text(w/2,h*0.33+34,'Перетащите видео в окно',15,'A4ADAF',5)
        end
        d:rect(g.left,g.top,g.right,g.bottom,'201915','10',9)
        local y=g.seek_y
        local expanded=seeking or self.dragging
        local current_chapter,chapter_start=chapter_at(model.chapters,model.position)
        local padding,footer,chapter_band=4,22,26
        local show_chapter=current_chapter and (not expanded or (g.top-chapter_band-padding-footer)*scale>=28)
        local half=expanded and 2.5 or 1.5
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
                d:rect(x-1,y-half-1,x+1,y+half+1,chapter.time==chapter_start and 'E9F4C1' or '201915')
            end
        end
        if expanded then d:rect(head-4,y-4,head+4,y+4,'E9F4C1','00',4) end
        region(g.seek_left,y-8,g.seek_right,y+8,nil,true)
        for _,c in ipairs(g.controls) do
            local hovered=self.pointer_inside and mx>=c.x1 and mx<=c.x2 and my>=c.y1 and my<=c.y2
            if hovered then d:rect(c.x1,c.cy-14,c.x2,c.cy+14,'493B30','00',6) end
            local name=c.name
            if name=='play' then name=model.pause and 'play' or 'pause' end
            if name=='mute' then name=model.mute and 'mute' or 'volume' end
            d:icon(name,c.cx,c.cy,c.name=='play' and 21 or 17,hovered and 'C9DC7A' or 'ECF0F3')
            region(c.x1,c.y1,c.x2,c.y2,function() session:dispatch(c.action,c.arg) end,false,c.tip)
        end
        if not g.time_above then
            d:text(g.time_x,g.controls_y,g.time_compact and rules.time(model.position) or
                rules.time(model.position)..' / '..rules.time(model.duration),12,'BAC3C9',4)
        end
        local r=hit()
        if expanded and model.duration>0 then
            local seconds=M.seek_fraction(g,mx)*model.duration
            local chapter,segment_start=chapter_at(model.chapters,seconds)
            self.hover={kind='seek',time=seconds,chapter=chapter}
            local anchor=g.top-(show_chapter and chapter_band or 4)
            if not self.dragging then
                preview:request(seconds,math.min(240*scale,pw-16-2*padding*scale),
                    math.min(136*scale,math.max(20,(anchor-padding-footer)*scale-8)),segment_start)
            end
            local f=not self.dragging and preview.frame or nil
            local stamp=rules.time(seconds)
            local stamp_width=#stamp*7+16
            local max_width=w-16/scale
            local hint=chapter and not f and M.chapter_hint(chapter,stamp,max_width,g.seek_y-5-8/scale)
            if hint and hint.height>anchor-8/scale then
                show_chapter=nil; anchor=g.seek_y-5
            end
            local label_width=chapter and math.min(250,stamp_width+character_count(chapter)*8+8) or stamp_width
            local width=hint and hint.width or math.min(max_width,math.max(label_width,f and f.width/scale+2*padding or 0))
            local height=hint and hint.height or (f and f.height/scale+padding or 0)+footer
            local box=previews.placement(mx*scale,anchor*scale,width*scale,height*scale,pw,ph)
            local bx,by,bw,bh=box.x/scale,box.y/scale,box.w/scale,box.h/scale
            d:rect(bx,by,bx+bw,by+bh,'201915','00',6)
            if f then preview:show(box.x+(box.w-f.width)/2,box.y+padding*scale) end
            local ty=by+bh-footer/2
            if hint then
                for i,line in ipairs(hint.lines) do
                    -- An oversized word stays on a single line and is fitted to the card.
                    local scale_x=math.min(100,100*math.max(1,bw-16)/(title_units(line)*hint.font))
                    d:text(bx+8,by+hint.pad+(i-0.5)*hint.row_height,line,hint.font,'ECF0F3',4,scale_x)
                end
                d:text(bx+bw-8,by+hint.pad+(hint.stamp_row-0.5)*hint.row_height,stamp,hint.stamp_font,'BAC3C9',6)
            elseif chapter and bw>stamp_width+24 then
                d:text(bx+8,ty,shorten(chapter,math.floor((bw-stamp_width-8)/8)),13,'ECF0F3',4)
                d:text(bx+bw-8,ty,stamp,13,'BAC3C9',6)
            else
                d:text(bx+bw/2,ty,stamp,12,'ECF0F3',5)
            end
        else
            if preview.wanted or preview.visible then preview:hide() end
            if r and r.tip then
                self.hover={kind='control',text=r.tip}
                local tw=math.min(w-20,character_count(r.tip)*7+18)
                local tx=math.max(tw/2+8,math.min(w-tw/2-8,(r.x1+r.x2)/2))
                if g.top<49 then show_chapter=nil end
                local ty=math.max(16,g.top-(show_chapter and 38 or 18))
                d:rect(tx-tw/2,ty-11,tx+tw/2,ty+11,'201915','00',5)
                d:text(tx,ty,shorten(r.tip,math.floor((tw-18)/7)),12,'ECF0F3',5)
            end
        end
        if show_chapter then
            local available=g.right-g.left-(g.time_above and 116 or 4)
            local label=shorten(current_chapter,math.min(36,math.floor((available-16)/8)))
            local width=math.min(available,character_count(label)*8+16)
            d:rect(g.left,g.top-24,g.left+width,g.top-4,'201915','10',5)
            d:text(g.left+8,g.top-14,label,14,'ECF0F3',4)
        end
        if not self.hover then
            if g.time_above then
                d:text(g.right-4,g.top-14,rules.time(model.position)..' / '..rules.time(model.duration),12,'B7C1C7',6)
            end
            if model.status~='' then
                local available=g.right-g.left-(g.time_above and not show_chapter and 116 or 8)
                local ty=g.top-(show_chapter and 36 or 14)
                if ty>=7 then d:text(g.left+4,ty,shorten(model.status,math.floor(available/7)),12,'A4ADAF',4) end
            end
        end
        finish(g,current_chapter)
    end
    function self:invalidate()
        if not self.enabled or self.closed or self.timer then return end
        if not self:visible() then
            self.regions={}; self.hover=nil
            if overlay.data~='' then overlay:remove(); overlay.data=''; preview:hide() end
            sync_cursor(false)
            capture(false)
            local w,h,scale=size(); publish(w,h,scale,false)
            return
        end
        self.timer=mp.add_timeout(self.dragging and 0.02 or 0.04,function() self:draw() end)
    end
    function self:shutdown()
        cancel_video_click()
        self.closed=true; unbind_menu(); self.dragging=false; capture(false)
        if self.timer then self.timer:kill() end
        if self.hide_timer then self.hide_timer:kill() end
        preview:shutdown(); overlay:remove()
        if cursor_restore then
            mp.set_property_native('cursor-autohide',cursor_restore.hide)
            mp.set_property_native('cursor-autohide-fs-only',cursor_restore.fs_only)
        end
    end
    mp.observe_property('mouse-pos','native',function(_,value)
        if not self.enabled then return end
        local x,y=value and value.x,value and value.y
        local moved=type(x)=='number' and type(y)=='number'
            and (x~=self.last_mouse_x or y~=self.last_mouse_y)
        if type(x)=='number' and type(y)=='number' then self.last_mouse_x,self.last_mouse_y=x,y end
        self.pointer_inside=value and value.hover==true or false
        if value and value.hover==false and not self.dragging then
            preview:hide(); self.hover=nil
            self:invalidate()
            return
        end
        if self.dragging then
            local x=mouse()
            if not self.last_seek or mp.get_time()-self.last_seek>=0.04 then seek_at(x); self.last_seek=mp.get_time() end
        end
        if moved and self.pointer_inside then self:reveal() else self:invalidate() end
        capture(model.menu~='' or (self:visible() and hit()~=nil))
    end)
    mp.observe_property('osd-dimensions','native',function() preview:hide(); self:invalidate() end)
    mp.observe_property('video-params','native',function() self:invalidate() end)
    mp.observe_property('pause','bool',function(_,paused)
        if type(paused)=='boolean' then self:reveal(paused) end
    end)
    self:reveal()
    return self
end
return M
