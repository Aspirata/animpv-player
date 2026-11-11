-- On-demand preview frames decoded by an isolated instance of mpv itself.
local mp=require 'mp'
local utils=require 'mp.utils'
local M={}
function M.display_dimensions(params)
    local w,h=params.dw or params.w or 0,params.dh or params.h or 0
    local angle=math.rad(params.rotate or 0)
    return math.floor(w*math.abs(math.cos(angle))+h*math.abs(math.sin(angle))+0.5),
        math.floor(h*math.abs(math.cos(angle))+w*math.abs(math.sin(angle))+0.5)
end
function M.dimensions(w,h,max_w,max_h)
    if not w or not h or w<=0 or h<=0 then return nil end
    local scale=math.min(1,max_w/w,max_h/h)
    return math.max(1,math.floor(w*scale)),math.max(1,math.floor(h*scale))
end
function M.placement(x,anchor_y,w,h,window_w,window_h)
    local fit=math.min(1,math.max(1,window_w-16)/w,math.max(1,window_h-16)/h)
    w,h=math.floor(w*fit),math.floor(h*fit)
    return {x=math.max(8,math.min(window_w-w-8,math.floor(x-w/2))),
        y=math.max(8,math.min(window_h-h-8,math.floor(anchor_y-h))),w=w,h=h}
end
function M.eligible(path,duration,w,h)
    return type(path)=='string' and path~='' and not path:match('^%a[%w+.-]*://')
        and type(duration)=='number' and duration>0 and duration<1e10
        and type(w)=='number' and w>0 and type(h)=='number' and h>0
end
function M.new(options,changed)
    local self={cache={},order={},files={},generation=0,serial=0,decoded=0,cache_hits=0,busy=false,
        frame=nil,wanted=nil,media=nil,error=nil,visible=false}
    local prefix=utils.join_path(options.state_dir,'preview-'..utils.getpid()..'-'..tostring(math.floor(mp.get_time()*1000))..'-')
    local engine=options.preview_mpv
    if not engine or engine=='' then
        engine=require('filesystem').executable()
    end
    local function notify() if changed then changed() end end
    local function remove(path)
        if self.files[path] then os.remove(path); self.files[path]=nil end
    end
    local function clear_cache()
        for path in pairs(self.files) do remove(path) end
        self.cache={}; self.order={}
    end
    function self:hide()
        self.generation=self.generation+1
        if self.delay then self.delay:kill(); self.delay=nil end
        if self.timeout then self.timeout:kill(); self.timeout=nil end
        if self.worker then mp.abort_async_command(self.worker); self.worker=nil end
        self.busy=false; self.wanted=nil; self.frame=nil; self.visible=false
        mp.commandv('overlay-remove',42)
        if self.expiry then self.expiry:kill() end
        self.expiry=mp.add_timeout(20,clear_cache)
    end
    function self:set_media(path,duration,w,h,vid,rotation)
        local identity=table.concat({path or '',tostring(w),tostring(h),tostring(vid),tostring(rotation)},'|')
        if identity~=self.identity then
            self:hide(); clear_cache(); self.identity=identity; self.error=nil
        end
        self.media,self.duration,self.source_w,self.source_h,self.vid=path,duration,w,h,vid
        self.rotation=rotation or 0
    end
    local start
    start=function()
        self.delay=nil
        local wanted=self.wanted
        if not wanted or self.busy or self.error then return end
        local cached=self.cache[wanted.key]
        if cached then self.frame=cached; self.cache_hits=self.cache_hits+1; notify(); return end
        if not engine or engine=='' then self.error='Движок превью не найден'; notify(); return end
        self.serial=self.serial+1
        local output=prefix..self.serial..'.bgra'
        self.files[output]=true
        local generation=self.generation
        local rotation=self.rotation%360
        local filters={}
        if rotation~=0 then
            -- Normalize anamorphic pixels at thumbnail size before rotating.
            local rw,rh=M.display_dimensions({dw=self.source_w,dh=self.source_h,rotate=rotation})
            local factor=math.min(wanted.w/rw,wanted.h/rh)
            filters[#filters+1]='scale='..math.max(1,math.floor(self.source_w*factor))..':'..math.max(1,math.floor(self.source_h*factor))
            filters[#filters+1]='setsar=1'
            if rotation==90 then filters[#filters+1]='transpose=clock'
            elseif rotation==270 then filters[#filters+1]='transpose=cclock'
            elseif rotation==180 then filters[#filters+1]='hflip'; filters[#filters+1]='vflip'
            else
                local angle=string.format('%.8f',math.rad(rotation))
                filters[#filters+1]='rotate='..angle..':ow=rotw('..angle..'):oh=roth('..angle..')'
            end
        end
        filters[#filters+1]='scale='..wanted.w..':'..wanted.h
        filters[#filters+1]='setsar=1'; filters[#filters+1]='format=bgra'
        local args={engine,'--no-config','--load-scripts=no','--osc=no','--terminal=no',
            '--no-audio','--no-sub','--no-resume-playback','--no-save-position-on-quit',
            '--no-input-default-bindings','--no-input-terminal','--hwdec=no','--vd-lavc-threads=1',
            '--ovc=rawvideo','--of=rawvideo','--ovcopts=threads=1','--frames=1','--hr-seek=yes',
            '--start='..string.format('%.3f',wanted.time),'--video-rotate=no',
            '--vf=lavfi=['..table.concat(filters,',')..']',
            '--o='..output,'--vid='..tostring(self.vid or 1),'--',self.media}
        self.busy=true
        self.worker=mp.command_native_async({name='subprocess',args=args,playback_only=false,
            capture_stdout=true,capture_stderr=true,capture_size=8192},function(ok,result)
            if generation~=self.generation then remove(output); return end
            self.worker=nil; self.busy=false
            if self.timeout then self.timeout:kill(); self.timeout=nil end
            local info=utils.file_info(output)
            if not ok or not result or result.status~=0 or not info or info.size~=wanted.w*wanted.h*4 then
                remove(output); self.error='Превью недоступно для этого файла'; self.frame=nil
                notify(); return
            end
            local frame={file=output,width=wanted.w,height=wanted.h,time=wanted.time,media=self.media,key=wanted.key}
            self.decoded=self.decoded+1; self.cache[wanted.key]=frame
            self.order[#self.order+1]=wanted.key
            while #self.order>(options.preview_cache or 16) do
                local key=table.remove(self.order,1)
                if self.cache[key] then remove(self.cache[key].file); self.cache[key]=nil end
            end
            if self.wanted and self.wanted.key==wanted.key then self.frame=frame end
            notify()
            if self.wanted and self.wanted.key~=wanted.key and not self.delay then start() end
        end)
        self.timeout=mp.add_timeout(5,function()
            if generation~=self.generation then return end
            self:hide(); self.error='Превью: превышено время ожидания'; notify()
        end)
        notify()
    end
    function self:request(seconds,max_w,max_h,chapter_start)
        if not options.previews or not M.eligible(self.media,self.duration,self.source_w,self.source_h) then return end
        local dw,dh=M.display_dimensions({dw=self.source_w,dh=self.source_h,rotate=self.rotation})
        local w,h=M.dimensions(dw,dh,max_w,max_h)
        local bucket=math.floor(seconds/2)*2
        local time=math.max(0,math.min(self.duration-0.05,math.max(bucket,chapter_start or 0)))
        local key=string.format('%.3f:%d:%d',time,w,h)
        if self.expiry then self.expiry:kill(); self.expiry=nil end
        if self.wanted and self.wanted.key==key then return end
        self.wanted={key=key,time=time,w=w,h=h}; self.frame=nil; self.visible=false
        mp.commandv('overlay-remove',42)
        if self.cache[key] then
            if self.delay then self.delay:kill(); self.delay=nil end
            self.frame=self.cache[key]; self.cache_hits=self.cache_hits+1; notify(); return
        end
        -- Update the queued position without postponing the next decode on every mouse move.
        if not self.delay then self.delay=mp.add_timeout(options.preview_delay or 0.12,start) end
    end
    function self:show(x,y)
        if not self.frame then return end
        local f=self.frame
        x,y=math.floor(x),math.floor(y)
        if self.visible and self.x==x and self.y==y then return end
        local ok,result=pcall(mp.command_native,{name='overlay-add',id=42,x=x,y=y,
            file=f.file,offset=0,fmt='bgra',w=f.width,h=f.height,stride=f.width*4},false)
        self.visible=ok and result~=false; self.x,self.y=x,y
    end
    function self:stats()
        local f=self.frame or {}
        return {visible=self.visible,busy=self.busy,decoded=self.decoded,cache_hits=self.cache_hits,
            cache_count=#self.order,file=f.file,width=f.width,height=f.height,time=f.time,media=f.media,
            x=self.x,y=self.y,error=self.error}
    end
    function self:shutdown()
        self:hide(); if self.expiry then self.expiry:kill(); self.expiry=nil end
        clear_cache()
    end
    return self
end
return M
