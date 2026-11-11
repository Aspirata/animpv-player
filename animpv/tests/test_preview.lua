test('preview fits aspect ratio and never upscales small source frames',function()
    local p=module('preview')
    local w,h=p.dimensions(1920,1080,240,136)
    equal(w,240); equal(h,135)
    w,h=p.dimensions(1080,1920,240,136)
    equal(w,76); equal(h,136)
    w,h=p.dimensions(80,60,240,136)
    equal(w,80); equal(h,60)
    equal(p.dimensions(0,0,240,136),nil)
end)
test('preview placement stays within window at both timeline edges',function()
    local p=module('preview')
    for _, x in ipairs({0,160,320}) do
        local box=p.placement(x,110,240,135,320,180)
        assert(box.x>=8 and box.x+box.w<=312)
        assert(box.y>=8 and box.y+box.h<=172)
    end
end)
test('preview eligibility rejects streams and invalid duration without reading them',function()
    local p=module('preview')
    equal(p.eligible('https://example.org/movie.mkv',100,1920,1080),false)
    equal(p.eligible('av://device',100,1920,1080),false)
    equal(p.eligible('C:/Медиа/Show.mkv',100,1920,1080),true)
    equal(p.eligible('C:/Медиа/Show.mkv',0,1920,1080),false)
end)

test('preview uses display aspect and clockwise rotation',function()
    local p=module('preview')
    local w,h=p.display_dimensions({w=720,h=576,dw=768,dh=576,rotate=0})
    equal(w,768); equal(h,576)
    w,h=p.display_dimensions({w=720,h=576,dw=768,dh=576,rotate=90})
    equal(w,576); equal(h,768)
end)

test('preview completion respects the newest hover deadline',function()
    local mp=require 'mp'
    local utils=require 'mp.utils'
    local saved={}
    local clock,timers,workers,requests=0,{},{},{}
    local function replace(t,key,value)
        saved[#saved+1]={t,key,t[key]}; t[key]=value
    end
    replace(mp,'get_time',function() return clock end)
    replace(mp,'add_timeout',function(delay,fn)
        local timer={at=clock+delay,fn=fn,active=true}
        function timer:kill() self.active=false end
        timers[#timers+1]=timer; return timer
    end)
    replace(mp,'commandv',function() end)
    replace(mp,'abort_async_command',function() end)
    replace(mp,'command_native_async',function(cmd,fn)
        requests[#requests+1]=table.concat(cmd.args,' ')
        workers[#workers+1]=fn; return #workers
    end)
    replace(utils,'file_info',function() return {size=240*135*4} end)
    replace(os,'remove',function() end)
    local function advance(to)
        clock=to
        for _,timer in ipairs(timers) do
            if timer.active and timer.at<=clock then timer.active=false; timer.fn() end
        end
    end
    local ok,err=pcall(function()
        local p=module('preview').new({state_dir='.',preview_mpv='test-mpv',previews=true,preview_delay=0.12})
        p:set_media('test.mkv',30,1920,1080,1)
        p:request(2,240,135); advance(0.06); p:request(4,240,135)
        advance(0.12); equal(#workers,1)
        assert(requests[1]:find('--start=4.000',1,true),'Pending hover should decode the latest position')
        advance(0.2); p:request(8,240,135)
        advance(0.21); workers[1](true,{status=0})
        equal(#workers,1)
        advance(0.33); equal(#workers,2)
        p:shutdown()
    end)
    for i=#saved,1,-1 do local v=saved[i]; v[1][v[2]]=v[3] end
    assert(ok,err)
end)
