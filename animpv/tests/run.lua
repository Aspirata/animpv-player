local mp = require 'mp'
local utils = require 'mp.utils'
local here = mp.get_script_directory() or debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]')
package.path = here .. '/../scripts/animpv/?.lua;' .. here .. '/?.lua;' .. package.path
local tests, failed = 0, 0
function test(name, fn)
    tests = tests + 1
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then failed = failed + 1; print('FAIL ' .. name .. '\n' .. err)
    else print('PASS ' .. name) end
end
function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
end
function module(name)
    local ok, value = pcall(require, name)
    assert(ok, 'Missing or invalid implementation: ' .. name .. '\n' .. tostring(value))
    return value
end
mp.add_timeout(0, function()
    for _, name in ipairs({'test_rules', 'test_history', 'test_library', 'test_ui'}) do
        local path = utils.join_path(here, name .. '.lua')
        if utils.file_info(path) then
            local ok, err = pcall(dofile, path)
            if not ok then failed = failed + 1; print('FAIL suite ' .. name .. ': ' .. err) end
        end
    end
    print(string.format('%d tests, %d failures', tests, failed))
    if failed == 0 and tests > 0 then print('ANIMPV_TESTS_OK') end
    mp.commandv('quit', failed == 0 and tests > 0 and 0 or 1)
end)
