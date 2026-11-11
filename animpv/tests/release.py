"""Read-only smoke test against a user-provided local episode folder."""
import argparse
from pathlib import Path
import re
import time

from integration import Player
from run import engine


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mpv')
    parser.add_argument('--media',required=True,type=Path)
    args=parser.parse_args()
    episodes=sorted(args.media.glob('*.mkv'))
    assert episodes,'No MKV episodes in supplied folder'
    root=Path(__file__).resolve().parent/'.artifacts'
    state=root/'release-state'
    state.mkdir(parents=True,exist_ok=True)
    p=Player(engine(args.mpv),state,[episodes[0]],visible=True)
    try:
        p.ready()
        playlist=p.get('playlist')
        assert len(playlist)==len(episodes)
        numbers=[int(re.search(r' - (\d+) ',Path(item['filename']).name)[1]) for item in playlist]
        assert numbers==list(range(1,len(episodes)+1)),numbers
        tracks=p.get('track-list')
        external=next(t for t in tracks if t['type']=='audio' and t.get('external'))
        assert p.get('chapter-list'),'Chapter markers should be loaded'
        p.command('set_property','geometry','1100x700')
        p.wait(lambda: abs(p.get('osd-width')-1100)<5,'resize')
        p.action('menu','playlist')
        p.wait(lambda: p.get('user-data/animpv')['menu']=='playlist','episode menu')
        time.sleep(0.25)
        p.command('screenshot-to-file',str(root/'release-playlist.png'),'window')
        p.command('set_property','geometry','480x320')
        p.wait(lambda: abs(p.get('osd-width')-480)<5,'small window')
        time.sleep(0.25)
        p.command('screenshot-to-file',str(root/'release-playlist-small.png'),'window')
        p.action('menu-close')
        p.action('select-track','audio',external['id'])
        p.action('next')
        p.wait(lambda: p.get('path').replace('\\','/')==str(episodes[1]).replace('\\','/'),'next episode')
        p.ready()
        p.wait(lambda: any(t['type']=='audio' and t.get('external') and t.get('selected')
                          for t in p.get('track-list')),'external voice preference retained')
        assert all('- 02 ' in t['external-filename'] for t in p.get('track-list') if t.get('external'))
        print(f'PASS {len(playlist)} ordered episodes, playlist screenshots, chapters and external voice on next episode')
    finally:
        p.close()


if __name__=='__main__':
    main()
