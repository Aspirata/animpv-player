"""Exercise real hover decoding, caching, cancellation and timeline drag in mpv."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import time
from integration import Player, fixtures
from run import engine

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mpv')
args=parser.parse_args()
root=Path(__file__).resolve().parent / '.artifacts'
root.mkdir(exist_ok=True)
media=root / 'Медиа с пробелами'
if not media.exists():
    media=fixtures(root)
state=root / 'preview-state'
state.mkdir(exist_ok=True)
p=Player(engine(args.mpv),state,[media/'Show S01E01.mkv'],visible=True)
try:
    p.ready(); p.command('set_property','geometry','1100x700')
    p.command('set_property','sid','no')
    def ui():
        return p.get('user-data/animpv').get('ui',{})
    def geometry():
        return p.wait(lambda: (v:=ui()).get('geometry') and
                      abs(v.get('physical_width',0)-p.get('osd-width'))<2 and v['geometry'],
                      'published UI geometry matching the resized window')
    def hover(fraction):
        g=geometry()
        p.command('mouse',round(g['seek_left']+(g['seek_right']-g['seek_left'])*fraction),round(g['seek_y']))
    g=geometry()
    assert g['bottom']-g['top']<100
    assert ui()['preview']['decoded']==0,'Decoding should start only on hover'
    hover(1/3)
    frame=p.wait(lambda: (v:=ui().get('preview',{})).get('visible') and v,'decoded preview')
    raw=Path(frame['file']).read_bytes()
    assert len(raw)==frame['width']*frame['height']*4
    first_hash=hashlib.sha256(raw).hexdigest()
    p.command('screenshot-to-file',str(root/'timeline-preview.png'),'window')
    before=frame['decoded']
    hover(0.34)
    time.sleep(0.3)
    assert ui()['preview']['decoded']==before,'Same time bucket should reuse a frame'
    p.command('keypress','MOUSE_LEAVE')
    p.wait(lambda: not ui()['preview']['visible'],'native mouse-leave clears image')
    time.sleep(0.3)
    assert not ui()['preview']['visible'],'Preview reappeared after native mouse-leave'
    hover(0.34)
    hover(2/3)
    frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and v.get('time',0)>=18 and v,'different preview frame')
    assert hashlib.sha256(Path(frame['file']).read_bytes()).hexdigest()!=first_hash
    print('PASS demand decoding, exact BGRA size, temporal frame change and cached bucket')
    # A menu owns input and must remove both the image and pending preview work.
    p.hotkey('audio-menu')
    p.wait(lambda: not ui()['preview']['visible'] and not ui()['preview']['busy'],'menu clears preview')
    p.command('keypress','ESC')
    p.command('mouse',0,0)
    p.wait(lambda: not ui()['preview']['visible'],'leave clears preview')
    hover(0.25)
    time.sleep(0.05)
    p.command('loadfile',str(media/'Show S01E02.mkv'),'replace')
    p.wait(lambda: 'S01E02' in p.get('path'),'new file')
    p.ready(); hover(0.4)
    frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and 'S01E02' in v.get('media','') and v,
                 'preview belongs to latest file')
    print('PASS modal/leave cleanup and stale decoder cancellation on file replacement')
    for size in ['1100x700','480x320']:
        p.command('set_property','geometry',size)
        p.wait(lambda: abs(p.get('osd-width')-int(size.split('x')[0]))<5,'resize')
        p.wait(lambda: abs(ui().get('physical_width',0)-int(size.split('x')[0]))<5,'resized geometry')
        hover(0.25); time.sleep(0.05)
        p.command('keydown','MBTN_LEFT')
        hover(0.75); time.sleep(0.08)
        p.command('keyup','MBTN_LEFT')
        p.wait(lambda: abs(p.get('time-pos')-22.5)<0.3,'drag seeking at resized coordinates')
        p.wait(lambda: not ui().get('dragging'),'drag capture released')
        hover(0.01)
        frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and v,'left edge preview')
        assert frame['x']>=0 and frame['y']>=0
        assert frame['x']+frame['width']<=p.get('osd-width')
        assert frame['y']+frame['height']<=p.get('osd-height')
        p.command('screenshot-to-file',str(root/f'preview-{size}.png'),'window')
    print('PASS timeline drag, release and preview edge placement at both sizes')
    hover(0.3)
    p.command('set_property','pause',False)
    p.wait(lambda: not ui()['visible'] and not ui()['preview']['visible'],
           'stationary timeline hover expires with the playback deadline',timeout=2.8)
    hover(0.31)
    p.wait(lambda: ui()['visible'] and ui()['preview']['visible'],'movement brings preview back')
    p.command('set_property','pause',True)
    print('PASS stationary hover expires; movement brings the preview back')
    # Two colored halves expose pixel rotation as well as the declared aspect ratio.
    anamorphic=root/'anamorphic.mkv'
    subprocess.run(['ffmpeg','-v','error','-nostdin','-y','-f','lavfi','-i',
        'color=c=red:s=720x576:r=1,drawbox=x=iw/2:y=0:w=iw/2:h=ih:color=blue:t=fill,setsar=16/15',
        '-t','4','-c:v','mpeg4','-q:v','2',str(anamorphic)],check=True)
    p.command('loadfile',str(anamorphic),'replace'); p.ready()
    hover(0.3)
    frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and 'anamorphic' in v.get('media','') and v,
                 'anamorphic preview')
    assert abs(frame['width']/frame['height']-4/3)<0.02,frame
    p.command('set_property','video-rotate',90)
    p.wait(lambda: p.get('video-params')['rotate']==90,'rotated video')
    hover(0.4)
    frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and v['height']>v['width'] and v,'rotated preview')
    assert abs(frame['width']/frame['height']-3/4)<0.02,frame
    raw=Path(frame['file']).read_bytes()
    def pixel(x,y):
        i=(y*frame['width']+x)*4
        return raw[i:i+4]
    top=pixel(frame['width']//2,frame['height']//4)
    bottom=pixel(frame['width']//2,3*frame['height']//4)
    assert top[2]>top[0]+100 and bottom[0]>bottom[2]+100,(top,bottom)
    print('PASS anamorphic display aspect and clockwise pixel rotation')

    chapter_file=root/'chapters.mkv'
    metadata=root/'chapters.ffmeta'
    long_title='Основная часть: ОченьДлинноеСловоБезПробеловИПереноса и описание времени события'
    metadata.write_text(f''';FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=11500
title=Вступление
[CHAPTER]
TIMEBASE=1/1000
START=11500
END=20000
title={long_title}
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=30000
''',encoding='utf-8')
    subprocess.run(['ffmpeg','-v','error','-nostdin','-y','-i',str(media/'Show S01E01.mkv'),
        '-i',str(metadata),'-map','0','-map_chapters','1','-c','copy',str(chapter_file)],check=True)
    p.command('set_property','video-rotate',0)
    p.command('mouse',0,0)
    p.command('loadfile',str(chapter_file),'replace'); p.ready()
    p.wait(lambda: ui().get('chapter')=='Вступление','current chapter at playback position')
    hover(0.39)
    frame=p.wait(lambda: (v:=ui()['preview']).get('visible') and v,'chapter thumbnail')
    boundary=p.get('chapter-list')[1]['time']
    assert frame['time']>=boundary-0.001,('Thumbnail shows the previous chapter',frame,boundary,ui()['hover'])
    assert ui()['hover']['chapter']==long_title
    assert ui()['chapter']=='Вступление','Hover changed the current playback chapter'
    p.command('screenshot-to-file',str(root/'timeline-chapter.png'),'window')
    p.command('mouse',0,0)
    p.action('seek-time',22)
    p.wait(lambda: ui().get('chapter')=='Глава 3','untitled chapter gets a fallback name')
    p.command('loadfile',str(media/'Show S01E01.mkv'),'replace'); p.ready()
    p.wait(lambda: not ui().get('chapter'),'chapter title clears on a file without markers')
    print('PASS current chapter, hover chapter, chapter boundary thumbnail and file switch')
finally:
    p.close()
assert not list(state.glob('preview-*.bgra')),'Preview cache should be cleaned on shutdown'
p=Player(engine(args.mpv),state,[chapter_file],visible=True,extra=[
    '--script-opts-append=animpv-ui_scale=2',
    f'--script-opts-append=animpv-preview_mpv={state}/missing-mpv.exe'])
try:
    p.ready(); p.command('set_property','geometry','320x180')
    p.wait(lambda: abs(p.get('osd-width')-320)<5,'small high-scale window')
    g=geometry(); scale=ui()['scale']
    assert scale>=1.5
    p.command('mouse',round(g['play_x']),round(g['controls_y']))
    time.sleep(0.15); p.command('keypress','MBTN_LEFT')
    p.wait(lambda: not p.get('pause'),'high-scale play icon activates playback')
    assert p.get('user-data/animpv')['menu']=='','High-scale controls activated an overlapping menu'
    p.command('set_property','pause',True)
    hover(0.4)
    p.wait(lambda: ui()['preview'].get('error') and not ui()['preview']['busy'],'missing decoder gracefully falls back')
    assert p.get('duration')>0 and not ui()['preview']['visible']
    assert ui()['hover']['chapter']==long_title
    p.command('screenshot-to-file',str(root/'timeline-full-chapter.png'),'window')
    p.command('set_property','geometry','1100x700')
    p.wait(lambda: abs(p.get('osd-width')-1100)<5,'wide window for full chapter title')
    hover(0.4)
    p.wait(lambda: (ui().get('hover') or {}).get('chapter')==long_title,'full chapter title in wide window')
    p.command('screenshot-to-file',str(root/'timeline-full-chapter-wide.png'),'window')
    print('PASS small high-scale controls and missing-decoder fallback')
finally:
    p.close()
assert not list(state.glob('preview-*.bgra')),'Failed decoder should leave no cached frames'
print('ANIMPV_PREVIEWS_OK')
