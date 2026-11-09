"""Small reproducible timings; results describe this machine and fixture only."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import statistics
import tempfile
import time
from integration import Player, fixtures
from run import engine


def resources(pid):
    if os.name != 'nt':
        return {}
    from ctypes import wintypes
    class Counters(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('faults', wintypes.DWORD)] + [
            (name, ctypes.c_size_t) for name in ['peak_ws', 'ws', 'peak_paged', 'paged',
                                               'peak_nonpaged', 'nonpaged', 'pagefile', 'peak_pagefile']]
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    handle = kernel.OpenProcess(0x410, False, pid)
    if not handle:
        return {}
    try:
        c = Counters()
        c.cb = ctypes.sizeof(c)
        created, exited, system, user = [wintypes.FILETIME() for _ in range(4)]
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(c), c.cb):
            return {}
        if not kernel.GetProcessTimes(handle, *map(ctypes.byref, [created, exited, system, user])):
            return {}
        seconds = sum((f.dwHighDateTime << 32) + f.dwLowDateTime for f in [system, user]) / 1e7
        return {'working_set_mib': round(c.ws / 1048576, 2), 'cpu_seconds': seconds}
    finally:
        kernel.CloseHandle(handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mpv')
    args = parser.parse_args()
    binary = engine(args.mpv)
    result = {}
    with tempfile.TemporaryDirectory(prefix='animpv-benchmark-') as tmp:
        root = Path(tmp)
        media = fixtures(root)
        for baseline in [True, False]:
            values = []
            for n in range(3):
                state = root / f'state-{baseline}-{n}'
                state.mkdir()
                start = time.perf_counter()
                p = Player(binary, state, [media / 'Show S01E01.mkv'], baseline=baseline)
                try:
                    if baseline:
                        p.wait(lambda: p.get('duration') > 0, 'baseline loaded')
                        values.append((time.perf_counter()-start)*1000)
                    else:
                        first = p.ready()
                        values.append((time.perf_counter()-start)*1000)
                        reads = first['index_reads']
                        p.command('playlist-next', 'force')
                        p.wait(lambda: 'S01E02' in p.get('path'), 'next episode')
                        second = p.ready()
                        result['cached_index_extra_directory_reads'] = second['index_reads'] - reads
                        result['first_index_ms'] = round(first['index_seconds']*1000, 2)
                        result['cached_index_ms'] = round(second['index_seconds']*1000, 2)
                finally:
                    p.close()
            if values:
                label = 'baseline' if baseline else 'animpv'
                result[label + '_headless_startup_ms_median'] = round(statistics.median(values),2)
        state = root / 'visible'; state.mkdir()
        p = Player(binary, state, [media / 'Show S01E01.mkv'], visible=True)
        try:
            p.ready(); p.command('set_property', 'mute', True)
            p.command('set_property', 'pause', False)
            time.sleep(4)
            for mode in ['hidden', 'menu']:
                if mode == 'menu':
                    p.action('menu', 'main'); time.sleep(0.2)
                before = resources(p.process.pid)
                start = time.perf_counter(); time.sleep(2)
                after = resources(p.process.pid)
                if before and after:
                    result[mode] = {'working_set_mib': after['working_set_mib'],
                        'cpu_one_core_percent': round((after['cpu_seconds']-before['cpu_seconds']) /
                                                      (time.perf_counter()-start)*100,2)}
        finally:
            p.close()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
