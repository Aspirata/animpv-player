"""Exercise physical letter positions in the test player's Windows window."""
import argparse
import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import time

from integration import Player, fixtures
from run import engine


def win32(name, result, *args):
    fn = getattr(c.windll.user32, name)
    fn.restype, fn.argtypes = result, args
    return fn


layout_list = win32('GetKeyboardLayoutList', c.c_int, c.c_int, c.POINTER(w.HANDLE))
get_layout = win32('GetKeyboardLayout', w.HANDLE, w.DWORD)
find_window = win32('FindWindowExW', w.HWND, w.HWND, w.HWND, w.LPCWSTR, w.LPCWSTR)
get_thread = win32('GetWindowThreadProcessId', w.DWORD, w.HWND, c.POINTER(w.DWORD))
map_key = win32('MapVirtualKeyExW', w.UINT, w.UINT, w.UINT, w.HANDLE)
post = win32('PostMessageW', w.BOOL, w.HWND, w.UINT, w.WPARAM, w.LPARAM)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mpv')
    args = parser.parse_args()
    layouts = (w.HANDLE * layout_list(0, None))()
    layout_list(len(layouts), layouts)
    us = next((layout for layout in layouts if layout & 0xFFFFFFFF == 0x04090409), None)
    ru = next((layout for layout in layouts if layout & 0xFFFFFFFF == 0x04190419), None)
    if not (us and ru):
        print('SKIP: US and Russian layouts must already be loaded in Windows')
        return

    root = Path(__file__).resolve().parent / '.artifacts'
    media = root / 'Медиа с пробелами'
    if not media.exists():
        media = fixtures(root)
    state = root / 'keyboard-state'
    state.mkdir(exist_ok=True)
    episode = media / 'Show S01E01.mkv'
    p = Player(engine(args.mpv), state, [episode], visible=True)
    try:
        p.ready()
        p.action('seek-time', 12)
        p.wait(lambda: abs(p.get('time-pos')-12)<0.2, 'set a resume point')
        p.command('loadfile', str(episode), 'replace')
        p.wait(lambda: p.get('user-data/animpv')['resume_position'] >= 11, 'load saved resume point')
        p.wait(lambda: p.get('time-pos') < 1, 'reopen at the start')

        def own_window():
            hwnd = None
            while (hwnd := find_window(None, hwnd, 'mpv', None)):
                pid = w.DWORD()
                thread = get_thread(hwnd, c.byref(pid))
                if pid.value == p.process.pid:
                    return hwnd, thread

        hwnd, thread = p.wait(own_window, 'test player window')
        for layout, resume_key in [(ru, 'Ctrl+к'), (us, 'Ctrl+r'), (ru, 'Ctrl+к')]:
            assert post(hwnd, 0x0050, 0, layout), 'request layout only in test player window'
            p.wait(lambda: get_layout(thread) == layout, 'Windows switched test window layout')
            time.sleep(0.25)
            scan = 0x1E  # physical US A position, Russian Ф
            vk = map_key(scan, 3, layout)
            key_data = (scan << 16) | 1
            assert post(hwnd, 0x0100, vk, key_data)
            assert post(hwnd, 0x0101, vk, key_data | 0xC0000000)
            p.wait(lambda: p.get('user-data/animpv')['menu'] == 'audio', 'physical A opens audio menu')
            p.command('keypress', 'ESC')
            p.wait(lambda: p.get('user-data/animpv')['menu'] == '', 'Escape closes menu')
            p.command('keypress', resume_key)
            p.wait(lambda: abs(p.get('time-pos')-12)<0.2, 'localized Ctrl+R resumes playback position')
            p.action('seek-time', 0)
            p.wait(lambda: p.get('time-pos')<0.2, 'return to start for the next layout')
        print('PASS physical A and Ctrl+R survive live RU/US/RU changes in the same mpv window')
    finally:
        p.close()

    custom = state / 'custom-input.conf'
    custom.write_text('ф set volume 31\n', encoding='utf-8')
    p = Player(engine(args.mpv), state, [episode], visible=True, extra=[f'--input-conf={custom}'])
    try:
        p.ready()
        hwnd, thread = p.wait(own_window, 'test player window with custom input.conf')
        assert post(hwnd, 0x0050, 0, ru)
        p.wait(lambda: get_layout(thread) == ru and any(
            item['key'] == 'ф' and item['cmd'].endswith('script-binding animpv/audio-menu')
            for item in p.get('input-bindings')), 'both the Russian default and user binding are present')
        p.command('keypress', 'ф')
        p.wait(lambda: p.get('volume') == 31, 'input.conf still overrides the localized binding')
        assert p.get('user-data/animpv')['menu'] == ''
        print('PASS explicit input.conf binding overrides layout defaults')
    finally:
        p.close()


if __name__ == '__main__':
    main()
