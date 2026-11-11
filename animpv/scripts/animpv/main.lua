-- AniMPV entry point. Original application layer over the unmodified mpv engine.
local mp = require 'mp'
local opts = require 'mp.options'
local utils = require 'mp.utils'
local o = {ui=true, state_dir='~~/state', max_depth=3, max_files=4000, max_dirs=128,
    cache_seconds=30, history_limit=300, save_interval=10, ui_scale=1,
    previews=true,preview_delay=0.12,preview_cache=16,preview_mpv=''}
opts.read_options(o, 'animpv')
for name, range in pairs({max_depth={0,8}, max_files={10,20000}, max_dirs={1,1000},
    cache_seconds={0,3600}, history_limit={1,1000}, save_interval={5,300}, ui_scale={0.6,2},
    preview_delay={0.12,1},preview_cache={1,32}}) do
    local n = tonumber(o[name])
    if not n or n ~= n then n=range[1] end
    o[name] = math.max(range[1], math.min(range[2], n))
    if name ~= 'ui_scale' and name ~= 'preview_delay' then o[name] = math.floor(o[name]) end
end
o.state_dir = mp.command_native({'expand-path', o.state_dir})
o.help = {'Пробел / левый клик по видео — плей/пауза', '← / → — перемотка на 5 секунд', 'PgUp / PgDn — предыдущая / следующая серия',
    'A — аудиодорожки', 'J — субтитры', 'P — серии / плейлист', 'H — история',
    'Ctrl+R — продолжить с сохранённой позиции', 'F5 — обновить поиск', 'F / двойной левый клик — полный экран',
    'M — выключить звук', 'V — видимость субтитров', 'Tab — показать панель',
    'F1 — справка', 'Кнопка меню / правый клик — меню', '↑ / ↓, Enter, Esc — навигация в меню'}
local session = require('session').new(require('library').new(o), require('history').new(o.state_dir, o.history_limit), o)
session.ui = require('ui').new(session, o)
require('keyboard').bind(session)
session:changed(true)
mp.msg.info('AniMPV foundation ready')
