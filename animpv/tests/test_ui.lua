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

test('main menu shows file variants only when present and puts help last',function()
    local session=module('session')
    for _,candidates in ipairs({{},{{label='Альтернативная серия'}}}) do
        local items=session.main_items(candidates,0)
        local found=0
        for _,item in ipairs(items) do
            assert(item.action~='refresh','Refresh should not be a menu button')
            if item.args and item.args[1]=='found' then
                equal(item.label,'Варианты файлов'); found=found+1
            end
        end
        equal(found,#candidates>0 and 1 or 0)
        equal(items[#items].label,'Клавиши')
        equal(items[#items].args[1],'help')
    end
end)

test('chapter hint keeps the entire title within a narrow window', function()
    local ui=module('ui')
    local title='Длинное название главы с уточнением и ОченьДлиннымСловомБезПробеловВДополнении'
    local hint=ui.chapter_hint(title,'00:12',184,60)
    assert(#hint.lines>1,'Long titles should wrap')
    assert(hint.width<=184 and hint.height<=60,'Wrapped text should fit above the timeline')
    equal(table.concat(hint.lines,' '),title)
    for _,line in ipairs(hint.lines) do
        assert(not line:find('…',1,true),'Fallback title should not have an ellipsis')
    end
end)

test('chapter hint widens for long titles and never breaks an oversized word', function()
    local ui=module('ui')
    local title=('Длинное название главы с дополнительными подробностями '):rep(3)..'в конце'
    local wide=ui.chapter_hint(title,'00:12',1000,250)
    assert(wide.width>440,'The text-only card should use the wider window')
    equal(table.concat(wide.lines,' '),title)

    local word=('я'):rep(90)
    local narrow=ui.chapter_hint(word..' конец','00:12',184,60)
    equal(narrow.lines[1],word)
    equal(table.concat(narrow.lines,' '),word..' конец')
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
