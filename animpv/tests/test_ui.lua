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
