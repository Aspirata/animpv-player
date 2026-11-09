test('panel seek coordinates stay inside small and large windows', function()
    local ui = module('ui')
    for _, size in ipairs({{320,180},{1280,720},{3840,2160}}) do
        local g = ui.layout(size[1], size[2], 1)
        assert(g.left >= 0 and g.right <= size[1])
        assert(g.top >= 0 and g.bottom <= size[2])
        assert(g.seek_left < g.seek_right)
        assert(g.seek_y >= g.top and g.seek_y < g.bottom)
    end
end)
test('compact panel leaves more video visible and controls never overlap',function()
    local ui=module('ui')
    for _, size in ipairs({{200,112},{240,150},{320,180},{480,320},{1100,700},{3840,2160}}) do
        local g=ui.layout(size[1],size[2],1)
        assert(g.bottom-g.top<=80,'Panel should stay compact')
        assert(g.right-g.left<=960,'Panel should not stretch across the entire large screen')
        local last=g.left
        for _, control in ipairs(g.controls) do
            assert(control.x1>=last and control.x2<=g.right,'Controls overlap or leave the panel')
            last=control.x2
        end
        equal(ui.seek_fraction(g,g.seek_left-100),0)
        equal(ui.seek_fraction(g,g.seek_right+100),1)
        equal(ui.seek_fraction(g,(g.seek_left+g.seek_right)/2),0.5)
    end
end)
