"""Real media + mpv IPC integration tests for AniMPV (Python standard library)."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

from run import engine

CONFIG = Path(__file__).resolve().parents[1]


class Player:
    def __init__(self, binary, state, files=(), visible=False, baseline=False, extra=()):
        self.root = Path(state)
        self.address = (rf"\\.\pipe\animpv-test-{os.getpid()}-{time.monotonic_ns()}"
                        if os.name == "nt" else str(self.root / "ipc.sock"))
        self.log = open(self.root / "player.log", "w", encoding="utf-8")
        configuration = (["--no-config", "--load-scripts=no", "--osc=no", "--vo=gpu-next",
                          "--hwdec=auto-safe", "--sub-auto=no", "--audio-file-auto=no"]
                         if baseline else [f"--config-dir={CONFIG}"])
        args = [binary, *configuration, "--idle=yes", "--pause=yes",
                "--terminal=yes", "--keep-open=yes", f"--input-ipc-server={self.address}",
                f"--gpu-shader-cache-dir={state}/shader-cache",
                f"--script-opts=animpv-state_dir={state},animpv-ui={'yes' if visible else 'no'}"]
        if not visible:
            args += ["--vo=null", "--ao=null", "--force-window=no"]
        self.process = subprocess.Popen(args + list(extra) + [str(f) for f in files], stdout=self.log,
                                        stderr=subprocess.STDOUT)
        self.pipe = None
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                if os.name == "nt":
                    self.pipe = open(self.address, "r+b", buffering=0)
                else:
                    sock = socket.socket(socket.AF_UNIX)
                    sock.connect(self.address)
                    self.pipe = sock.makefile("rwb", buffering=0)
                    self.sock = sock
                break
            except OSError:
                if self.process.poll() is not None:
                    break
                time.sleep(0.03)
        if not self.pipe:
            self.close()
            raise AssertionError((self.root / "player.log").read_text(encoding="utf-8"))
        self.counter = 0
        self.pending = b''
        if os.name == 'nt':
            import msvcrt
            from ctypes import wintypes
            self.handle = msvcrt.get_osfhandle(self.pipe.fileno())
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.PeekNamedPipe.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD,
                wintypes.LPVOID, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
            self.kernel.PeekNamedPipe.restype = wintypes.BOOL
        else:
            self.sock.settimeout(0.1)

    def command(self, *args):
        self.counter += 1
        self.pipe.write((json.dumps({"command": list(args), "request_id": self.counter}) + "\n").encode())
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            while b'\n' in self.pending:
                line, self.pending = self.pending.split(b'\n', 1)
                message = json.loads(line)
                if message.get('request_id') == self.counter:
                    assert message.get('error') == 'success', message
                    return message.get('data')
            if os.name == 'nt':
                available = ctypes.c_ulong()
                if not self.kernel.PeekNamedPipe(self.handle, None, 0, None, ctypes.byref(available), None):
                    raise OSError('IPC pipe closed')
                if not available.value:
                    time.sleep(0.01)
                    continue
                self.pending += self.pipe.read(min(available.value, 65536))
            else:
                try:
                    self.pending += self.sock.recv(65536)
                except socket.timeout:
                    pass
        raise AssertionError(f'No IPC response for {args}')

    def get(self, name):
        return self.command("get_property", name)

    def action(self, name, *args):
        return self.command("script-message-to", "animpv", "action", name, *map(str, args))

    def wait(self, predicate, description, timeout=8):
        deadline, last = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            try:
                last = predicate()
                if last:
                    return last
            except (AssertionError, KeyError, TypeError):
                pass
            time.sleep(0.03)
        raise AssertionError(f"Timed out: {description}; last={last}\n" +
                             (self.root / "player.log").read_text(encoding="utf-8"))

    def ready(self):
        return self.wait(lambda: (s := self.get("user-data/animpv")) and
                         s.get("ready") and not s.get("scan_pending") and
                         s.get('path') == self.get('path').replace('\\', '/') and s,
                         "AniMPV initialized and indexed media")

    def close(self):
        if getattr(self, "process", None) and self.process.poll() is None:
            try:
                if self.pipe:
                    self.command("quit")
                self.process.wait(timeout=3)
            except (OSError, AssertionError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.wait(timeout=3)
        if self.pipe:
            self.pipe.close()
        self.log.close()


def fixtures(root):
    media = root / "Медиа с пробелами"
    audio = media / "Озвучка Studio"
    subs = media / "Субтитры Team"
    audio.mkdir(parents=True)
    subs.mkdir()
    first = media / "Show S01E01.mkv"
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-f", "lavfi", "-i",
                    "testsrc2=size=480x270:rate=24", "-f", "lavfi", "-i", "sine=frequency=220",
                    "-t", "30", "-c:v", "mpeg4", "-q:v", "8", "-c:a", "aac", str(first)], check=True)
    mka = audio / "Show S01E01.mka"
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-f", "lavfi", "-i",
                    "sine=frequency=440", "-f", "lavfi", "-i", "sine=frequency=880", "-t", "30",
                    "-map", "0:a", "-map", "1:a", "-c:a", "aac", "-metadata:s:a:0", "title=East",
                    "-metadata:s:a:1", "title=West", "-metadata:s:a:0", "language=rus",
                    "-metadata:s:a:1", "language=rus", str(mka)], check=True)
    for n in [1, 2, 3]:
        name = f"Show S01E{n:02}"
        if n != 1:
            shutil.copyfile(first, media / f"{name}.mkv")
            shutil.copyfile(mka, audio / f"{name}.mka")
        (subs / f"{name}.srt").write_text("1\n00:00:00,000 --> 00:00:29,000\nAniMPV test\n", encoding="utf-8")
    (media / "cover.jpg").touch()
    return media


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv")
    args = parser.parse_args()
    binary = engine(args.mpv)
    with tempfile.TemporaryDirectory(prefix="animpv-integration-") as temporary:
        root = Path(temporary)
        media = fixtures(root)
        state = root / "state"
        state.mkdir()
        player = Player(binary, state, [media / "Show S01E01.mkv"])
        try:
            s = player.ready()
            assert player.get("playlist-count") == 3, s
            tracks = player.get("track-list")
            assert len([t for t in tracks if t["type"] == "audio"]) == 3, tracks
            assert len([t for t in tracks if t["type"] == "sub"]) == 1, tracks
            print("PASS real nested MKA/subtitle discovery and video-only episode playlist")
            player.action("menu", "audio")
            player.wait(lambda: player.get("user-data/animpv").get("menu") == "audio", "audio menu")
            player.action("menu-close")
            player.wait(lambda: player.get("user-data/animpv").get("menu") == "", "menu release")
            player.action("seek", 0.5)
            player.wait(lambda: abs(player.get("time-pos") - 15) < 0.2, "proportional seek")
            player.action("pause")
            player.wait(lambda: player.get("pause") is False, "pause action")
            player.command("set_property", "pause", True)
            west = next(t for t in tracks if t.get("title") == "West")
            player.action("select-track", "audio", west["id"])
            player.command("playlist-next", "force")
            player.wait(lambda: "S01E02" in player.get("path"), "next episode")
            player.ready()
            player.wait(lambda: any(t.get("title") == "West" and t.get("selected")
                                     for t in player.get("track-list")), "voice preference")
            print("PASS menu lifecycle, proportional seek, pause and voice retention")
            # Rapid switches must not attach episode 1 tracks to episode 3.
            player.command("loadfile", str(media / "Show S01E01.mkv"), "replace")
            player.command("loadfile", str(media / "Show S01E03.mkv"), "replace")
            player.wait(lambda: "S01E03" in player.get("path"), "rapid switch")
            player.ready()
            assert all("S01E03" in t["external-filename"] for t in player.get("track-list")
                       if t.get("external")), player.get("track-list")
            print("PASS stale discovery cancellation")
        finally:
            player.close()
        # The saved position belongs to episode one, which was left at 15 seconds.
        player = Player(binary, state, [media / "Show S01E01.mkv"])
        try:
            s = player.ready()
            assert player.get("time-pos") < 0.3, s
            assert s.get("resume_position", 0) >= 14, s
            player.action("resume")
            player.wait(lambda: player.get("time-pos") >= 14, "explicit resume after restart")
            print("PASS startup from beginning and explicit persisted resume")
        finally:
            player.close()
        manual = root / "manual"
        manual.mkdir()
        player = Player(binary, manual, [media / "Show S01E01.mkv", media / "Show S01E03.mkv"])
        try:
            player.ready()
            assert player.get("playlist-count") == 2
            print("PASS user-supplied playlist preserved")
        finally:
            player.close()
        preference = root / 'preference-at-start'; preference.mkdir()
        player = Player(binary, preference, [media / 'Show S01E01.mkv'])
        try:
            player.ready()
            west = next(t for t in player.get('track-list') if t.get('title') == 'West')
            player.action('select-track', 'audio', west['id'])
        finally:
            player.close()
        player = Player(binary, preference, [media / 'Show S01E01.mkv'])
        try:
            player.ready()
            assert any(t.get('title') == 'West' and t.get('selected') for t in player.get('track-list'))
            print('PASS voice choice persists even before playback starts')
        finally:
            player.close()
    print("ANIMPV_INTEGRATION_OK")


if __name__ == "__main__":
    main()
