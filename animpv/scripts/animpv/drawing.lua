-- Small ASS drawing surface for the original AniMPV panel.
local rules=require 'rules'
local icons=require 'icons'
local M={}
function M.new()
    local self={parts={}}
    function self:rect(x1,y1,x2,y2,color,alpha,radius)
        if x2<=x1 or y2<=y1 then return end
        local r=math.min(radius or 0,(x2-x1)/2,(y2-y1)/2)
        local path
        if r>0 then
            local c=r*0.5523
            path=string.format('m %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f',
                x1+r,y1,x2-r,y1,x2-r+c,y1,x2,y1+r-c,x2,y1+r,x2,y2-r,
                x2,y2-r+c,x2-r+c,y2,x2-r,y2,x1+r,y2,x1+r-c,y2,x1,y2-r+c,x1,y2-r,
                x1,y1+r,x1,y1+r-c,x1+r-c,y1,x1+r,y1)
        else path=string.format('m %f %f l %f %f %f %f %f %f',x1,y1,x2,y1,x2,y2,x1,y2) end
        self.parts[#self.parts+1]=string.format('{\\an7\\pos(0,0)\\fscx100\\fscy100\\bord0\\shad0\\c&H%s&\\alpha&H%s&\\p1}%s{\\p0}',color,alpha or '00',path)
    end
    function self:text(x,y,value,font,color,align,single_line_scale)
        self.parts[#self.parts+1]=string.format('{\\an%d\\pos(%.1f,%.1f)\\fscx%.2f\\fscy100\\fnSegoe UI\\fs%.1f%s\\bord0\\shad0\\alpha&H00&\\c&H%s&}%s',
            align or 7,x,y,single_line_scale or 100,font or 15,single_line_scale and '\\q2' or '',color or 'ECF0F3',rules.escape(value))
    end
    function self:icon(...) self.parts[#self.parts+1]=icons.draw(...) end
    function self:result() return table.concat(self.parts,'\n') end
    return self
end
return M
