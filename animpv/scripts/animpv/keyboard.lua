local mp = require 'mp'
local utils = require 'mp.utils'
local M = {}

-- Scan codes for the physical positions named on a US QWERTY keyboard.
local bindings = {
    {'audio-menu', 'a', 0x1e, 'menu', 'audio'},
    {'subtitle-menu', 'j', 0x24, 'menu', 'sub'},
    {'playlist-menu', 'p', 0x19, 'menu', 'playlist'},
    {'history-menu', 'h', 0x23, 'menu', 'history'},
    {'resume', 'Ctrl+r', 0x13, 'resume'},
    {'fullscreen', 'f', 0x21, 'fullscreen'},
    {'mute', 'm', 0x32, 'mute'},
    {'subtitle-visibility', 'v', 0x2f, 'sub-visible'},
}

local function windows_keyboard()
    local ok, ffi = pcall(require, 'ffi')
    if not ok or ffi.os ~= 'Windows' then return end
    ffi.cdef[[
        void* __stdcall FindWindowExW(void*, void*, const unsigned short*, const unsigned short*);
        unsigned long __stdcall GetWindowThreadProcessId(void*, unsigned long*);
        void* __stdcall GetKeyboardLayout(unsigned long);
        unsigned int __stdcall MapVirtualKeyExW(unsigned int, unsigned int, void*);
        int __stdcall ToUnicodeEx(unsigned int, unsigned int, const unsigned char*,
            unsigned short*, int, unsigned int, void*);
    ]]
    local user = ffi.load('user32')
    local class = ffi.new('unsigned short[4]', {109,112,118,0}) -- L"mpv"
    local pid, owner = utils.getpid(), ffi.new('unsigned long[1]')
    local state, chars = ffi.new('unsigned char[256]'), ffi.new('unsigned short[10]')
    local hwnd
    local function layout()
        if hwnd ~= nil then
            local thread = user.GetWindowThreadProcessId(hwnd, owner)
            if thread ~= 0 and owner[0] == pid then return user.GetKeyboardLayout(thread) end
            hwnd = nil
        end
        repeat
            hwnd = user.FindWindowExW(nil, hwnd, class, nil)
            if hwnd ~= nil then
                local thread = user.GetWindowThreadProcessId(hwnd, owner)
                if thread ~= 0 and owner[0] == pid then return user.GetKeyboardLayout(thread) end
            end
        until hwnd == nil
    end
    local function key(hkl, scan, ctrl)
        local vk = user.MapVirtualKeyExW(scan, 3, hkl) -- MAPVK_VSC_TO_VK_EX
        if vk == 0 then return end
        local function decode(with_ctrl)
            state[0x11], state[0xa2] = with_ctrl and 0x80 or 0, with_ctrl and 0x80 or 0
            -- Translate without altering the OS dead-key buffer (Windows 10+).
            local count = math.min(math.abs(user.ToUnicodeEx(vk, scan, state, chars, 10, 4, hkl)), 10)
            if count == 0 then return 0 end
            local code = chars[count-1]
            if code >= 0xdc00 and code <= 0xdfff and count > 1 then
                local high = chars[count-2]
                if high >= 0xd800 and high <= 0xdbff then
                    code = 0x10000 + (high-0xd800)*1024 + code-0xdc00
                end
            end
            return code
        end
        local code = decode(ctrl)
        if ctrl and code < 32 then code = decode(false) end
        if code >= 32 and code ~= 127 and not (code >= 0xd800 and code <= 0xdfff) then return code end
    end
    return {layout=layout,key=key}
end

function M.bind(session)
    local ok, keyboard = pcall(windows_keyboard)
    if not ok then
        mp.msg.warn('Windows keyboard layout detection unavailable: '..tostring(keyboard))
        keyboard = nil
    end
    local previous, keys = false, {}
    local function refresh()
        local layout = keyboard and keyboard.layout() or nil
        if layout == previous then return end
        previous = layout
        local next_keys, counts = {}, {}
        for i, binding in ipairs(bindings) do
            local default, scan = binding[2], binding[3]
            local ctrl = default:match('^Ctrl%+') ~= nil
            local code = (layout and keyboard.key(layout,scan,ctrl)) or default:byte(-1)
            local key = (ctrl and 'Ctrl+' or '') .. string.format('0x%X',code)
            next_keys[i] = key
            counts[key] = (counts[key] or 0)+1
        end
        for i, binding in ipairs(bindings) do
            local name, key, action, arg = binding[1], next_keys[i], binding[4], binding[5]
            -- A character shared by two positions cannot identify either reliably.
            if counts[key] > 1 then key = nil end
            if key ~= keys[i] then
                mp.remove_key_binding(name)
                if key then mp.add_key_binding(key,name,function() session:dispatch(action,arg) end) end
                keys[i] = key
            end
        end
    end
    refresh()
    if keyboard then
        local timer = mp.add_periodic_timer(0.1,refresh)
        mp.observe_property('vo-configured','bool',function(_, configured)
            if configured then timer:resume() else timer:stop() end
            refresh()
        end)
        mp.observe_property('focused','bool',function() refresh() end)
    end
end

return M
