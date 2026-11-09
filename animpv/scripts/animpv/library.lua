local mp = require 'mp'
local utils = require 'mp.utils'
local rules = require 'rules'
local filesystem = require 'filesystem'
local M = {}
function M.new(options)
    local o = options or {}
    local self = {generation=0, cache={}, reads=0}
    local max_depth, max_files, max_dirs = o.max_depth or 3, o.max_files or 4000, o.max_dirs or 128
    function self:cancel()
        self.generation = self.generation + 1
        if self.timer then self.timer:kill(); self.timer = nil end
        self.job = nil
    end
    function self:refresh() self.cache = {}; self:cancel() end
    local function incomplete(job, reason)
        job.result.incomplete, job.result.reason = true, reason
    end
    function self:begin(directory, callback)
        self:cancel()
        local cached = self.cache[directory]
        if cached and mp.get_time() - cached.time < (o.cache_seconds or 30) then
            self.job = {cached=cached.result, callback=callback, generation=self.generation}
        else
            self.job = {root=directory, queue={{path=directory, depth=0}}, cursor=1,
                count=0, dirs=1, result={videos={}, audio={}, subtitles={}, incomplete=false, reason=''},
                callback=callback, generation=self.generation}
        end
    end
    function self:step()
        local job = self.job
        if not job or job.generation ~= self.generation then return end
        local finish = job.cached ~= nil
        local started, work = mp.get_time(), 0
        while not finish and work < 64 and mp.get_time() - started < 0.004 do
            local dir = job.queue[job.cursor]
            if not dir then finish = true; break end
            if not dir.entries then
                local err
                dir.entries, err = utils.readdir(dir.path, 'all')
                self.reads = self.reads + 1
                if not dir.entries then incomplete(job, 'Ошибка чтения: ' .. tostring(err)); dir.entries = {} end
                table.sort(dir.entries, rules.natural_less); dir.index = 1
            end
            local name = dir.entries[dir.index]
            if not name then job.cursor = job.cursor + 1
            else
                dir.index = dir.index + 1; work = work + 1; job.count = job.count + 1
                if job.count > max_files then
                    incomplete(job, 'Достигнут лимит файлов (' .. max_files .. ')'); finish = true; break
                end
                local path = utils.join_path(dir.path, name)
                local info = utils.file_info(path)
                if info and info.is_dir and name:sub(1,1) ~= '.' then
                    if dir.depth >= max_depth or job.dirs >= max_dirs then
                        incomplete(job, 'Достигнут лимит глубины или каталогов')
                    else
                        local descend, err = filesystem.can_descend(path)
                        if descend then
                            job.dirs = job.dirs + 1
                            job.queue[#job.queue+1] = {path=path, depth=dir.depth+1}
                        elseif err then incomplete(job, err) end
                    end
                elseif info and info.is_file then
                    local kind = rules.kind(name)
                    if kind == 'video' and dir.depth == 0 then table.insert(job.result.videos, path)
                    elseif kind == 'audio' then table.insert(job.result.audio, path)
                    elseif kind == 'sub' then table.insert(job.result.subtitles, path) end
                end
            end
        end
        if finish then
            local result = job.cached or job.result
            if not job.cached then self.cache[job.root] = {time=mp.get_time(), result=result} end
            -- The cache is per service, with a fixed directory count as well as TTL.
            local count = 0
            for _ in pairs(self.cache) do count = count + 1 end
            if count > 8 then self.cache = {[job.root or 'cached']={time=mp.get_time(), result=result}} end
            self.job = nil
            if job.generation == self.generation and job.callback then job.callback(result) end
            return result
        end
    end
    function self:scan(directory, callback)
        self:begin(directory, callback)
        local function tick()
            self.timer = nil
            if self.job then self:step() end
            if self.job then self.timer = mp.add_timeout(0.005, tick) end
        end
        self.timer = mp.add_timeout(0, tick)
    end
    function self:scan_sync(directory)
        self:begin(directory)
        local result
        repeat result = self:step() until not self.job
        return result
    end
    return self
end
return M
