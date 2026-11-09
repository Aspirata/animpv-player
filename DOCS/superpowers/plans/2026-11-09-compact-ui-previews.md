# Compact AniMPV UI and hover previews

> **For agentic workers:** Use superpowers:executing-plans, with test-driven-development and verification-before-completion. The user's direct request authorizes this focused extension of the existing approved design; no new application stack or external script is introduced.

**Goal:** Compact the panel, replace control labels with original vector icons/tooltips, improve the timeline, and show real video previews on hover.

**Architecture:** Keep the original Lua/ASS interface; separate geometry and drawing, vector paths, and asynchronous preview lifecycle. Decode one bounded BGRA frame per request with an isolated instance of the running mpv engine and show it through the documented overlay API. No thumbfast/uosc/reference-build code, fonts or assets.

**Tech stack:** Lua 5.1-compatible mpv APIs, ASS vectors, raw BGRA, Python integration tests.

**Spec:** User request in this chat plus `DOCS/superpowers/specs/2026-11-09-animpv-independent-design.md` (preview belongs to the next stage and is now explicitly requested).

## Constraints and choices

- Retain Windows x64 / mpv 0.39+ validation; preserve existing controls and modal isolation.
- Panel around 76 logical pixels high, narrower maximum width; use original vector icons, no dependency on symbol-font glyphs. Tooltips remain readable Russian text.
- Timeline: larger invisible hit area, thicker hover state, scrubber, chapter markers, buffered ranges where available, hover timestamp and drag seeking.
- Preview defaults: local seekable video only; approximately 240×136 maximum logical size, fit original aspect ratio, minimum 120 ms hover delay, 2-second time buckets, at most one decoder and 16 cached frames, decoder timeout 5 seconds.
- Decoder uses the running Windows executable path (portable fallback provided), `--no-config --load-scripts=no --osc=no`; never inherits AniMPV/user/reference configuration or scripts. No FFmpeg executable dependency.
- On leave/menu/file change/shutdown, clear overlay and cancel work; ignore stale completions and clean only files created by this preview instance. Expire cache after inactivity. Missing encoder/unsupported files produce a time-only tooltip with no playback failure.
- No new installation, clipboard, exporting or online-format work.

## Review focus

Stale decoder results after a file change; process storms during mouse movement; media paths with spaces/Cyrillic; resize/DPI causing incorrect pointer mapping; mouse bindings surviving a modal; output buffers not matching declared BGRA dimensions; missing/failed decoder cleanup.

## Tasks

### 1. Geometry and preview rules

Files: `ui.lua`, new `preview.lua`, `icons.lua`, `test_ui.lua`, new `test_preview.lua`, `tests/run.lua`.

- [x] Add failing behavior cases for compact bounded geometry, nonoverlapping controls, pointer clamping, preview aspect fit/edge placement and local-file eligibility.
- [x] Run Lua suite and observe missing/new behavior failures; implement pure layout/dimension/placement helpers and vector icons.
- [x] Run all Lua tests to PASS.

### 2. Original preview service

Files: `preview.lua`, `filesystem.lua` (executable discovery), `main.lua`/options.

- [x] Add real-mpv integration tests for lazy decoding, exact raw frame size, cached reuse, cancellation and stale file results. Observe FAIL before service implementation.
- [x] Implement debounce, single asynchronous subprocess, timeout, generation checks, capped cache and scoped cleanup. Expose compact diagnostics through the existing UI diagnostic state.
- [x] Verify actual frames and no external executable/config dependency.

### 3. Compact panel and interactive timeline

Files: `ui.lua`, `icons.lua`, `session.lua`, `tests/visual.py`, options/docs.

- [x] Update input tests for compact layout, mouse click/drag, hover tooltip, rendered preview and no preview in menus/after leave. Existing input behaviors must remain covered.
- [x] Render original vector icon controls, hover highlights/tooltips, timeline buffer/chapters/handle, precise drag, preview frame and time.
- [x] Inspect actual panel and preview screenshots at normal and small sizes. Run Lua, media integration and visual checks on both engines.
- [x] Independent read-only review, regression fixes, update verification/docs, commit in current feature branch. Keep the existing untracked reference audit untouched.

## Execution evidence

- Geometry/preview helper and missing-service cases were observed failing before implementation. New review regressions likewise produced 3 failures, then 28/28 passed after fixes.
- Panel height reduced from 126 to 76 logical pixels. Original filled vector icons replace labels; Russian tooltips retain discoverability. Very narrow panels move optional controls to the existing menu/hotkeys.
- Real decoding is lazy, single-worker, debounced, cached, timed out, and scoped to local video. The same isolated mpv engine produces exact-size BGRA frames; no external script or FFmpeg executable is used by playback.
- On both mpv 0.39.0 and v0.42.0-11-g8bc468896: 28 Lua tests, 6 media IPC groups, rendered/input checks, and 6 preview/input groups passed. Actual screenshots inspected at 1100x700, 480x320 and 320x180/ui_scale=2. Anamorphic aspect and 90-degree rotation verified with pixel checks.
- Independent read-only review found 3 important issues: narrow controls overlap, coded/display aspect mismatch, and worker completion skipping hover debounce. All reproduced with failing tests, fixed, and re-reviewed with no remaining concrete defect in those changes.
- Additional regression fixes: native mouse-leave no longer redisplays stale frames; timeline capture temporarily disables/restores built-in window dragging; latest discovery reconciles only AniMPV-owned stale tracks after rapid file replacement.
- Documentation describes preview limits and options. Historical foundation measurements remain explicitly labeled as pre-preview results. HDR/heavy 4K, network previews, other platforms and physical multi-monitor/DPI behavior remain unvalidated.
- Integration: keep the current local feature branch; do not merge or push. Existing untracked reference audit preserved.
