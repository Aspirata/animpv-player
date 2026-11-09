"""Run AniMPV's Lua behavior suite inside a clean mpv, without Lua packages."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def engine(value=None):
    candidate = value or os.environ.get("ANIMPV_MPV") or shutil.which("mpv")
    if not candidate:
        raise SystemExit("Pass --mpv PATH or set ANIMPV_MPV to a standalone mpv executable.")
    path = Path(candidate).resolve()
    # Windows mpv.com is a console wrapper; execute the engine directly for IPC/capture.
    if path.suffix.lower() == '.com' and path.with_suffix('.exe').is_file():
        path = path.with_suffix('.exe')
    return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv")
    args = parser.parse_args()
    script = Path(__file__).with_name("run.lua").resolve()
    with tempfile.TemporaryDirectory(prefix="animpv-tests-") as root:
        fixture = Path(root)
        (fixture / "history").mkdir()
        (fixture / "library" / "Озвучка Studio").mkdir(parents=True)
        for name in ["Show - 01.mkv", "Show - 02.mkv", "cover.jpg"]:
            (fixture / "library" / name).touch()
        (fixture / "library" / "Озвучка Studio" / "Show - 01.mka").touch()
        if os.name == 'nt':
            subprocess.run(['cmd', '/d', '/c', 'mklink', '/J', str(fixture / 'library' / 'Loop'),
                            str(fixture / 'library')], capture_output=True, check=False)
        result = subprocess.run(
            [engine(args.mpv), "--no-config", "--load-scripts=no", "--vo=null", "--ao=null",
             "--idle=yes", "--terminal=yes", "--msg-level=all=warn,run=info",
             f"--script-opts=animpv-test-root={root}", f"--script={script}"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45,
        )
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    if "ANIMPV_TESTS_OK" not in result.stdout:
        return result.returncode or 1
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
