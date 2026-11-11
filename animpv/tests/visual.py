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
    def ui():
        return player.get('user-data/animpv')['ui']

    def click():
        player.command('keydown', 'MBTN_LEFT')
        player.command('keyup', 'MBTN_LEFT')

    def double_click():
        click()
        time.sleep(0.05)
        click()

    w, h = player.get('osd-width'), player.get('osd-height')
    player.command('mouse', w // 2, h // 2)
    click()
    player.wait(lambda: not player.get('pause'), 'single click resumes playback')
    assert not player.get('fullscreen')
    click()
    player.wait(lambda: player.get('pause'), 'single click pauses playback')
    click()
    time.sleep(0.05)
    assert player.get('pause'), 'First half of a double click toggled playback'
    click()
    player.wait(lambda: player.get('fullscreen'), 'double click enters fullscreen')
    time.sleep(0.4)
    assert player.get('pause'), 'Double click also toggled playback'
    double_click()
    player.wait(lambda: not player.get('fullscreen'), 'double click leaves fullscreen')
    time.sleep(0.4)
    assert player.get('pause'), 'Leaving fullscreen also toggled playback'
    player.command('keypress', 'SPACE')
    player.wait(lambda: not player.get('pause'), 'Space still resumes playback')
    player.command('keypress', 'SPACE')
    player.wait(lambda: player.get('pause'), 'Space still pauses playback')
    g = player.wait(lambda: ui().get('geometry'), 'panel after fullscreen')
    w, h = player.get('osd-width'), player.get('osd-height')
    player.command('mouse', round(g['menu_x']), round(g['controls_y']))
    player.wait(lambda: ui().get('hover', {}).get('kind') == 'control', 'on-screen menu button hover')
    click()
    player.wait(lambda: player.get('user-data/animpv')['menu'] == 'main', 'on-screen button opens menu')
    player.command('keypress', 'ESC')
    player.wait(lambda: player.get('user-data/animpv')['menu'] == '', 'Escape closes on-screen menu')
    player.command('mouse', 0, 0)
    player.command('keypress', 'MBTN_RIGHT')
    player.wait(lambda: player.get('user-data/animpv')['menu'] == 'main', 'right click opens main menu')
    player.command('mouse', w // 2, h // 2)
    hover = player.wait(lambda: (v := ui().get('hover')) and v.get('kind') == 'menu-item' and v,
                        'hovering a menu item highlights it')
    targets = {2: 'sub', 3: 'playlist', 4: 'chapters', 5: 'history', 7: 'help'}
    assert hover['index'] in targets
    player.command('screenshot-to-file', str(root / 'context-menu-hover.png'), 'window')
    player.command('mouse', 0, 0)
    player.wait(lambda: not ui().get('hover'), 'leaving a menu item clears its hover')
    player.command('mouse', w // 2, h // 2)
    player.wait(lambda: ui().get('hover', {}).get('index') == hover['index'], 'same row highlights again')
    player.command('keypress', 'MBTN_LEFT')
    player.wait(lambda: player.get('user-data/animpv')['menu'] == targets[hover['index']],
                'click activates the highlighted row')
    player.command('mouse', w // 5, h // 5)
    time.sleep(0.35)
    double_click()
    player.wait(lambda: player.get('user-data/animpv')['menu'] == '', 'outside click dismisses menu')
    time.sleep(0.4)
    assert player.get('pause') and not player.get('fullscreen'), 'Double click leaked through the dismissed menu'
    player.hotkey('audio-menu')
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
    g = player.wait(lambda: ui().get('geometry'), 'panel geometry')
    player.hotkey('audio-menu')
    player.wait(lambda: player.get('user-data/animpv').get('menu') == 'audio', 'modal open')
    time.sleep(0.2)
    was_paused = player.get('pause')
    player.command('mouse', round(g['play_x']), round(g['controls_y']))
    time.sleep(0.15)
    player.command('keypress', 'MBTN_LEFT')
    player.wait(lambda: player.get('user-data/animpv').get('menu') == '', 'outside click closes modal')
    assert player.get('pause') == was_paused, 'Modal click activated hidden playback controls'
    for geometry in ['1100x700', '480x320']:
        player.command('set_property', 'geometry', geometry)
        player.wait(lambda: abs(player.get('osd-width') - int(geometry.split('x')[0])) < 5, 'resize window')
        player.wait(lambda: abs(player.get('user-data/animpv')['ui'].get('physical_width',0)-int(geometry.split('x')[0]))<5,'panel resize')
        g=player.get('user-data/animpv')['ui']['geometry']
        player.command('mouse',round((g['seek_left']+g['seek_right'])/2),round(g['seek_y']))
        time.sleep(0.15)
        double_click()
        player.wait(lambda: abs(player.get('time-pos') - 15) < 0.3, 'mouse seek after resize')
        time.sleep(0.35)
        assert player.get('pause'), 'Double click on timeline toggled playback'
        assert not player.get('fullscreen'), 'Double click on timeline toggled fullscreen'
        player.command('screenshot-to-file', str(root / f'panel-{geometry}.png'), 'window')
    print('PASS single-click pause, double-click fullscreen, menu button, modal isolation and mouse seek', flush=True)
    if args.hold:
        print('GUI READY. Press Enter here to finish verification.', flush=True)
        input()
finally:
    player.close()
