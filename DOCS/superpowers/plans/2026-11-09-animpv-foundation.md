# AniMPV Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Deliver stage one of the approved independent AniMPV design as a runnable portable configuration with original UI, episode/track discovery and history.

**Architecture:** A directory script loads focused Lua modules through mpv's documented API. Pure media rules are separated from filesystem indexing, persistence and rendering; all UI input dispatches shared actions. No changes to mpv's C core.

**Tech Stack:** mpv Lua 5.1-compatible API, ASS overlays, Python standard library for test orchestration, PowerShell launcher on Windows.

**Spec:** `DOCS/superpowers/specs/2026-11-09-animpv-independent-design.md` (approved by “Реализовывай”).

## Global Constraints

- Independent additions: no reference scripts, config, artwork or resources copied or translated; upstream mpv remains the engine.
- First validation target Windows x64; no unverified cross-platform support claims.
- Separate `animpv/` configuration; preserve user mpv configuration and the reference folder.
- Stage one only. Preview generation, clipboard, online format enumeration, exporting, recycle bin and installation are later stages.
- Default startup from beginning with explicit resume (Ctrl+R); history is the sole position owner.
- Index and history are bounded. Manual playlists take precedence. Ambiguous matches require user selection.
- Conservative playback settings; no unmeasured performance superiority claims.

## Review Focus

- Rapid file switches must not attach discoveries or restore preferences from the previous resource (integration test).
- Different filenames for the same episode must not become consecutive automatic episodes (rules test).
- Malformed history and hostile ASS text must not prevent playback or inject display instructions (persistence/render tests).
- Nested paths, Cyrillic and multiple streams in MKA must remain selectable (real media integration test).
- Menu capture must release keyboard/mouse bindings on close and seek must reflect resized coordinates (UI action integration and manual check).

## Files and interfaces

- `animpv/mpv.conf`, `input.conf`, `script-opts/animpv.conf`: isolated defaults and documented options.
- `animpv/scripts/animpv/main.lua`: composition and mpv events.
- `animpv/scripts/animpv/rules.lua`: `episode(name) -> {season,number,series}|nil`, `videos(files,current) -> entries,ambiguous`, `match(video,candidate) -> score|nil`, `track_key(track)`, natural sorting and display escaping.
- `animpv/scripts/animpv/library.lua`: `new(options,on_ready) -> service`; `scan(directory, callback)`, `refresh()`, `cancel()`. Bounded queued directory reads, cache expiry, generation cancellation.
- `animpv/scripts/animpv/history.lua`: `new(directory,limit) -> store`; `get(path)`, `save(path,record)`, `list()`. Append-only per-process journal with complete records, bounded compaction, partial-write recovery and merged readers.
- `animpv/scripts/animpv/ui.lua`: `new(model,dispatch,options) -> ui`; `invalidate()`, `open(kind)`, `close()`, `shutdown()`. Original responsive ASS rendering and conditional bindings.
- `animpv/scripts/animpv/session.lua`: controller integrating actions, playlist, discovery and resume; exposes state through `user-data/animpv` for diagnostics/IPC tests.
- `animpv/Start-AniMPV.ps1`, `Start-AniMPV.cmd`: find explicit/local/PATH engine, launch with absolute config-dir, no profile installs.
- `animpv/README.md`, `ORIGIN.md`: operation, limitations, original-code declaration and dependencies.
- `animpv/tests/run.lua`, `test_rules.lua`, `test_history.lua`, `test_library.lua`: Lua behavior tests inside a real mpv runtime.
- `animpv/tests/run.py`, `integration.py`: launch tests, generate small media fixtures, named-pipe/Unix IPC checks; no production dependency on Python.

### Task 1: Media rules and executable test harness

- [x] Write independent literal cases for S01E02, bracket episode names, exclusion of resolution/year/CRC, natural ordering, duplicate episode versions, exact/potential external track matches, preference keys and ASS escaping.
- [x] Run `python animpv/tests/run.py --mpv <engine>`; expected FAIL for missing rules implementation.
- [x] Implement rules and a runner that loads Lua tests in mpv with no user/reference config.
- [x] Run the same command; expected all rule cases PASS.

### Task 2: Bounded discovery and resilient history

Consumes Task 1 episode/matching rules. Produces library index `{videos,audio,subtitles,incomplete,reason}` and persistent records `{path,position,duration,updated,audio,sub}`.

- [x] Write discovery tests for nested files, limits, refresh, stale callbacks and cache reuse; history tests for restart, truncated journal, invalid records, preservation of useful position at EOF, cap and concurrent writers.
- [x] Run the test command; expected FAIL for missing modules.
- [x] Implement discovery in short queued steps, with generation guards and `utils.file_info` link checks; implement per-session append journal, merge on read and bounded compaction without overwriting another writer's journal.
- [x] Run complete Lua suite; expected PASS. Record limitations of a single potentially blocking filesystem call.

### Task 3: Playback controller and original UI

Consumes Task 1/2 rules, index and store. UI model includes current file, time, duration, tracks, playlist, chapters, scan status, resume position and active menu. Dispatch accepts named actions plus structured arguments.

- [x] Write IPC integration assertions for isolated startup, auto playlist, discovered subtitles/MKA, explicit resume, preference across episodes, manual playlist preservation, menu open/close, seek, pause and cancellation on rapid switches. Run against absent entrypoint; expected FAIL.
- [x] Implement controller and script bootstrap; validate options; expose compact diagnostic state. Enable headless execution without UI for CI.
- [x] Implement responsive original panel and menus, centralized actions, on-demand redraw, safe text, idle welcome, track/episode/history/key help menus, keyboard navigation and conditional mouse areas.
- [x] Add config and documented bindings, then run Lua + integration suites. Expected PASS with real media on mpv 0.39+.

### Task 4: Runnable delivery and review

- [x] Add Windows launcher (explicit/local/PATH binary, helpful error), docs and provenance, optional no-dependency CI smoke workflow. No reference executable or scripts bundled.
- [x] Launch a real visible playback window; inspect rendered UI, menus and resized geometry where computer access permits. Record any GUI verification gap honestly.
- [x] Measure baseline/added startup and cached discovery using the same fixtures; record values and limits.
- [x] Run Lua suite, media integration, `git diff --check`; confirm no changes to mpv core/reference files. Independent whole-change review, fix important findings with regression cases, rerun affected/full suite.
- [x] Update verification report and task checkboxes. Leave all authorized work reviewable; no push/merge/publish.
