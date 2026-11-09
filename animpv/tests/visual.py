"""Open a synthetic-media AniMPV session for interactive GUI verification."""
import argparse
from pathlib import Path
import time
from integration import Player, fixtures
from run import engine

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mpv')
parser.add_argument('--hold', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent / '.artifacts'
root.mkdir(exist_ok=True)
media = root / 'Медиа с пробелами'
if not media.exists():
    media = fixtures(root)
state = root / 'visual-state'
state.mkdir(exist_ok=True)
player = Player(engine(args.mpv), state, [media / 'Show S01E01.mkv'], visible=True)
try:
    player.ready()
    player.command('set_property', 'geometry', '1100x700')
    player.command('set_property', 'sid', 'no')
    time.sleep(0.3)
    player.action('show-ui')
    time.sleep(0.2)
    player.command('screenshot-to-file', str(root / 'panel.png'), 'window')
    player.command('keypress', 'a')
    player.wait(lambda: player.get('user-data/animpv').get('menu') == 'audio', 'keyboard opens audio menu')
    time.sleep(0.2)
    player.command('screenshot-to-file', str(root / 'audio-menu.png'), 'window')
    player.command('keypress', 'DOWN')
    player.command('keypress', 'DOWN')
    player.command('keypress', 'DOWN')
    player.command('keypress', 'ENTER')
    player.wait(lambda: player.get('aid') == 3, 'keyboard selects second external stream')
    volume = player.get('volume')
    player.command('keypress', 'DOWN')
    player.wait(lambda: player.get('volume') == volume - 5, 'menu releases DOWN after closing')
    player.command('keypress', 'a')
    player.wait(lambda: player.get('user-data/animpv').get('menu') == 'audio', 'modal open')
    time.sleep(0.2)
    was_paused = player.get('pause')
    w, h = player.get('osd-width'), player.get('osd-height')
    scale = max(0.8, min(2, h / 720))
    player.command('mouse', round(w * 0.29), round(h - 66 * scale))
    time.sleep(0.15)
    player.command('keypress', 'MBTN_LEFT')
    player.wait(lambda: player.get('user-data/animpv').get('menu') == '', 'outside click closes modal')
    assert player.get('pause') == was_paused, 'Modal click activated hidden playback controls'
    for geometry in ['1100x700', '480x320']:
        player.command('set_property', 'geometry', geometry)
        player.wait(lambda: abs(player.get('osd-width') - int(geometry.split('x')[0])) < 5, 'resize window')
        time.sleep(0.2)
        w, h = player.get('osd-width'), player.get('osd-height')
        scale = max(0.8, min(2, h / 720))
        player.command('mouse', round(w/2), round(h-100*scale))
        time.sleep(0.15)
        player.command('keypress', 'MBTN_LEFT')
        player.wait(lambda: abs(player.get('time-pos') - 15) < 0.3, 'mouse seek after resize')
        player.command('screenshot-to-file', str(root / f'panel-{geometry}.png'), 'window')
    print('PASS rendered panel/menu, keyboard selection, input release and mouse seek at two sizes', flush=True)
    if args.hold:
        print('GUI READY. Press Enter here to finish verification.', flush=True)
        input()
finally:
    player.close()
