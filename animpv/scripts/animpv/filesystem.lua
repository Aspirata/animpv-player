local M = {}
local ok, ffi = pcall(require, 'ffi')
local kernel
if ok and ffi.os == 'Windows' then
    pcall(ffi.cdef, [[
        int MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
        unsigned long GetFileAttributesW(const unsigned short*);
        unsigned long GetModuleFileNameW(void*, unsigned short*, unsigned long);
        int WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
    ]])
    kernel = ffi.load('kernel32')
end
function M.executable()
    if kernel then
        local buffer=ffi.new('unsigned short[32768]')
        local length=tonumber(kernel.GetModuleFileNameW(nil,buffer,32768))
        if length>0 and length<32768 then
            local n=kernel.WideCharToMultiByte(65001,0,buffer,length,nil,0,nil,nil)
            local output=ffi.new('char[?]',n)
            kernel.WideCharToMultiByte(65001,0,buffer,length,output,n,nil,nil)
            return ffi.string(output,n)
        end
    end
    local path=require('mp').command_native({'expand-path','~~/bin/mpv.exe'})
    if require('mp.utils').file_info(path) then return path end
    return nil
end
-- file_info follows directory links. Inspect Windows attributes before descending.
function M.can_descend(path)
    if not kernel then return nil, 'Проверка ссылок недоступна: вложенный поиск отключён' end
    local size = kernel.MultiByteToWideChar(65001, 0, path, #path, nil, 0)
    if size == 0 then return nil, 'Некорректный путь' end
    local wide = ffi.new('unsigned short[?]', size + 1)
    kernel.MultiByteToWideChar(65001, 0, path, #path, wide, size)
    local attr = tonumber(kernel.GetFileAttributesW(wide))
    if attr == 4294967295 then return nil, 'Каталог недоступен' end
    return math.floor(attr / 1024) % 2 == 0 -- FILE_ATTRIBUTE_REPARSE_POINT
end
return M
