-- Original geometric 24-unit icons. Filled ASS paths; no font or asset package.
local M = {}
local paths = {
    menu='m 4 5 l 20 5 20 7 4 7 m 4 11 l 20 11 20 13 4 13 m 4 17 l 20 17 20 19 4 19',
    play='m 7 4 l 20 12 7 20',
    pause='m 6 4 l 10 4 10 20 6 20 m 14 4 l 18 4 18 20 14 20',
    prev='m 4 5 l 6 5 6 19 4 19 m 18 5 l 8 12 18 19',
    next='m 18 5 l 20 5 20 19 18 19 m 6 5 l 16 12 6 19',
    audio='m 3 13 l 3 10 b 3 4 7 1 12 1 b 17 1 21 4 21 10 l 21 13 19 13 19 10 b 19 6 16 3 12 3 b 8 3 5 6 5 10 l 5 13 m 2 12 l 7 12 7 21 2 21 m 17 12 l 22 12 22 21 17 21',
    volume='m 3 9 l 7 9 13 4 13 20 7 15 3 15 m 16 7 l 18 6 21 10 21 14 18 18 16 17 19 13 19 11 m 15 10 l 17 9 18 12 17 15 15 14 16 12',
    mute='m 3 9 l 7 9 13 4 13 20 7 15 3 15 m 16 7 l 22 15 20 17 14 9 m 20 7 l 22 9 16 17 14 15',
    sub='m 2 5 l 22 5 22 19 2 19 2 5 m 4 7 l 4 17 20 17 20 7 4 7 m 6 9 l 10 9 10 11 8 11 8 13 10 13 10 15 6 15 m 13 9 l 17 9 17 11 15 11 15 13 17 13 17 15 13 15',
    playlist='m 3 5 l 15 5 15 7 3 7 m 3 11 l 15 11 15 13 3 13 m 3 17 l 12 17 12 19 3 19 m 18 12 l 23 16 18 20',
    history='m 12 2 b 18 2 22 6 22 12 b 22 18 18 22 12 22 b 6 22 2 18 2 12 b 2 6 6 2 12 2 m 12 4 b 7 4 4 7 4 12 b 4 17 7 20 12 20 b 17 20 20 17 20 12 b 20 7 17 4 12 4 m 11 6 l 13 6 13 12 17 15 16 17 11 13',
    fullscreen='m 3 3 l 10 3 10 5 5 5 5 10 3 10 m 14 3 l 21 3 21 10 19 10 19 5 14 5 m 19 14 l 21 14 21 21 14 21 14 19 19 19 m 3 14 l 5 14 5 19 10 19 10 21 3 21',
    close='m 5 3 l 21 19 19 21 3 5 m 19 3 l 21 5 5 21 3 19',
}
function M.draw(name,x,y,size,color)
    local path=paths[name] or paths.menu
    return string.format('{\\an7\\pos(%.2f,%.2f)\\fscx%.2f\\fscy%.2f\\bord0\\shad0\\c&H%s&\\alpha&H00&\\p1}%s{\\p0}',
        x-size/2,y-size/2,size/24*100,size/24*100,color or 'ECF0F3',path)
end
return M
