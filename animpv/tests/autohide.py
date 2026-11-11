"""Verify pause/play overlay deadlines using a real mpv window."""
import argparse
from pathlib import Path
import time
from integration import Player, fixtures
from run import engine

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mpv')
args=parser.parse_args()
root=Path(__file__).resolve().parent/'.artifacts'
media=root/'Медиа с пробелами'
if not media.exists():
    media=fixtures(root)
state=root/'autohide-state'
state.mkdir(exist_ok=True)
p=Player(engine(args.mpv),state,[media/'Show S01E01.mkv'],visible=True,
         extra=['--script-opts-append=animpv-previews=no','--cursor-autohide=no','--cursor-autohide-fs-only=yes'])
try:
    p.ready()
    def visible():
        return p.get('user-data/animpv')['ui']['visible']
    def hidden_after(seconds,cursor_transition=False):
        start=time.monotonic()
        p.wait(visible,'panel shown')
        assert p.get('cursor-autohide') is False,'Cursor must remain visible with the panel'
        if cursor_transition:
            time.sleep(min(0.5,seconds*0.2))
            p.command('keypress','MOUSE_LEAVE')
            p.command('keypress','MOUSE_ENTER')
        time.sleep(seconds-0.7-(min(0.5,seconds*0.2) if cursor_transition else 0))
        assert visible(),'Panel hid before its deadline'
        assert p.get('cursor-autohide') is False,'Cursor hid earlier than the panel'
        p.wait(lambda: not visible(),'panel hides on its deadline',timeout=1.2)
        assert p.get('cursor-autohide')=='always','Cursor remained after the panel hid'
        assert not p.get('cursor-autohide-fs-only'),'Windowed mode must use the same cursor deadline'
        elapsed=time.monotonic()-start
        assert seconds-0.15<=elapsed<=seconds+0.8,elapsed

    p.command('mouse',0,0)
    p.action('show-ui')
    hidden_after(2,cursor_transition=True)
    assert p.get('pause'),'Hiding the overlay should leave playback paused'
    print('PASS paused deadline starts at activity; cursor hover transitions do not restart it')

    p.command('set_property','pause',False)
    p.wait(visible,'resuming reveals panel')
    time.sleep(0.3)
    p.command('set_property','pause',True)
    hidden_after(2)
    print('PASS changing to pause replaces the playback deadline with two seconds')

    p.command('set_property','pause',False)
    hidden_after(1)
    print('PASS playing overlay hides after one second')

    p.action('show-ui')
    g=p.wait(lambda: p.get('user-data/animpv')['ui'].get('geometry'),'panel geometry')
    p.command('mouse',round(g['play_x']),round(g['controls_y']))
    hidden_after(1)
    p.command('mouse',round(g['play_x'])+2,round(g['controls_y']))
    p.wait(visible,'real movement reveals the panel again')
    hidden_after(1,cursor_transition=True)
    print('PASS stationary cursor does not pin the panel; real movement restarts the deadline')

    p.action('menu','main')
    p.wait(visible,'menu shown')
    time.sleep(2.2)
    assert visible() and p.get('cursor-autohide') is False,'Menu must keep both panel and cursor visible'
    p.action('menu-close')
    hidden_after(1)
    print('PASS cursor and overlay share visibility through menus and windowed-mode overrides')
    assert p.command('expand-text',p.get('title'))==p.get('media-title')+' — AniMPV'
    print('PASS window title places AniMPV after the current media title')
finally:
    p.close()
