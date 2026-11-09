local utils = require 'mp.utils'
local mp = require 'mp'
local M = {}
local sequence = 0
local function finite(n) return type(n) == 'number' and n == n and n >= 0 and n < 1e12 end
local function valid(r)
    return type(r) == 'table' and r.version == 1 and type(r.path) == 'string'
        and #r.path > 0 and #r.path < 8192 and finite(r.position) and finite(r.updated)
        and (r.duration == nil or finite(r.duration))
        and (r.audio == nil or type(r.audio) == 'string' and #r.audio < 2048)
        and (r.sub == nil or type(r.sub) == 'string' and #r.sub < 2048)
end
function M.new(directory, limit)
    sequence = sequence + 1
    limit = math.max(1, math.min(1000, limit or 300))
    local filename = string.format('history-%010d-%d-%06d.jsonl', os.time(), utils.getpid(), sequence)
    local self = {file=utils.join_path(directory, filename), lines=0, error=nil, parsed={}}
    local function files()
        local result, seen = {}, {}
        for _, name in ipairs(utils.readdir(directory, 'files') or {}) do
            name = name:gsub('%.tmp$', '')
            if name:match('^history%-%d+%-%d+%-%d+%.jsonl$') and not seen[name] then
                seen[name] = true
                local path = utils.join_path(directory, name)
                local info = utils.file_info(path) or utils.file_info(path .. '.tmp')
                result[#result+1] = {path=path, time=info and info.mtime or 0}
            end
        end
        table.sort(result, function(a,b) if a.time == b.time then return a.path > b.path end; return a.time > b.time end)
        -- Only AniMPV journal names in this state directory are ever pruned.
        for i = #result, 33, -1 do
            if result[i].path ~= self.file and result[i].time < os.time()-86400 then os.remove(result[i].path) end
        end
        return result
    end
    function self:list()
        local by_path = {}
        for i, entry in ipairs(files()) do
            if i > 32 then break end
            for _, path in ipairs({entry.path, entry.path .. '.tmp'}) do
                local info = utils.file_info(path)
                local cached = self.parsed[path]
                if info and (not cached or cached.size ~= info.size or cached.mtime ~= info.mtime) then
                    local records = {}
                    local f = io.open(path, 'rb')
                    if f then
                    -- Bound memory before parsing; reject enormous/corrupt journals.
                    local content = f:read(4*1024*1024 + 1) or ''; f:close()
                    if #content <= 4*1024*1024 then
                        for line in content:gmatch('([^\n]*)\n') do
                            if #line <= 16384 then
                                local r = utils.parse_json(line)
                                if valid(r) then records[#records+1]=r end
                            end
                        end
                    end
                    end
                    cached={size=info.size,mtime=info.mtime,records=records}
                    self.parsed[path]=cached
                end
                if info and cached then
                    for _, r in ipairs(cached.records) do
                        if not by_path[r.path] or by_path[r.path].updated <= r.updated then by_path[r.path]=r end
                    end
                end
            end
        end
        local result = {}
        for _, r in pairs(by_path) do result[#result+1] = r end
        table.sort(result, function(a,b) if a.updated == b.updated then return a.path < b.path end; return a.updated > b.updated end)
        while #result > limit do table.remove(result) end
        return result
    end
    function self:get(path)
        for _, r in ipairs(self:list()) do if r.path == path then return r end end
    end
    function self:save(path, value)
        if type(value) ~= 'table' then return false end
        local r = {version=1, path=path, position=value.position, duration=value.duration,
            audio=value.audio, sub=value.sub, updated=os.time() + (mp.get_time() % 1)}
        if not valid(r) then return false end
        local old = self:get(path)
        if old then r.updated=math.max(r.updated,old.updated+0.000001) end
        if r.duration and r.duration > 0 and r.position >= r.duration - 2 and old then
            r.position = old.position
        end
        r.audio, r.sub = r.audio or (old and old.audio), r.sub or (old and old.sub)
        local line = utils.format_json(r) .. '\n'
        if #line > 16384 then return false end
        local f, err = io.open(self.file, 'ab')
        if not f then self.error = tostring(err); return false end
        local ok = f:write(line)
        local closed = f:close()
        if not ok or not closed then self.error = 'Не удалось записать историю'; return false end
        self.lines = self.lines + 1
        if self.lines > math.min(limit * 2, 128) then
            local temp = self.file .. '.tmp'
            local out = io.open(temp, 'wb')
            if out then
                local complete, bytes = true, 0
                for _, record in ipairs(self:list()) do
                    local record_line=utils.format_json(record) .. '\n'
                    bytes=bytes+#record_line
                    if bytes>2*1024*1024 then break end
                    if not out:write(record_line) then complete = false; break end
                end
                complete = out:close() and complete
                if complete then
                    -- Only this process writes this journal; others have different filenames.
                    if os.remove(self.file) then
                        local renamed = os.rename(temp, self.file)
                        if renamed then self.lines = 0; self.parsed[self.file]=nil; self.parsed[temp]=nil end
                    end
                end
            end
        end
        return true
    end
    return self
end
return M
