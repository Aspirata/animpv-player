local M = {}
local ok, ffi = pcall(require, 'ffi')
local kernel
if ok and ffi.os == 'Windows' then
    pcall(ffi.cdef, [[
        int MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
        unsigned long GetFileAttributesW(const unsigned short*);
    ]])
    kernel = ffi.load('kernel32')
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
