# Execution ledger — plan: DOCS/superpowers/plans/2026-11-09-animpv-foundation.md

- User approved implementation after reviewing the design summary; execute inline without another plan approval round.
- Baseline: upstream mpv sources, no additions or configured C build; available standalone mpv 0.39.0 passes isolated `--no-config --load-scripts=no --version`.
- Ruling: use a dedicated branch in the supplied writable checkout rather than create a second checkout — preserve the existing untracked audit/spec and keep all deliverables visible in the user's workspace. No upstream source changes planned.
- Git branch: codex/animpv-foundation; initial sandbox denial resolved through approved branch creation.
- Ruling: preserve immutable completed per-session history journals and replace only the current writer's compacted file using remove+rename with recovery — avoids Windows rename-over-existing and races between different writers; interrupted current compaction can lose only that writer's newest record, recovered when its complete temporary file exists.
- Pre-flight: Task 1 rules consumed by Tasks 2/3; Task 2 library records consumed by Task 3; model/dispatch consumed by UI in Task 3. Interfaces compatible.
- Task 1: complete — independent rules and real mpv Lua harness, observed RED then GREEN.
- Task 2: complete — bounded discovery, Windows reparse-point guard, per-writer recoverable journals; observed RED then GREEN. Junction cycle fixture is exercised on Windows.
- Task 3: complete — controller, original overlay and menus, centralized actions, video/track/history integration; observed missing-entrypoint and UI failures before implementation. Tests use expected path readiness during rapid transitions, not a previous file's diagnostic snapshot.
- Task 4: complete — two launchers, original-code provenance, documentation, local independently sourced engine with verified SHA-256, measurements and rendered/input checks. Native desktop capture could not reliably capture the GPU window, so no ungrounded coordinate clicks were made; mpv screenshots and its real input pipeline were tested instead.
- Ruling: preserve per-writer journals, read up to 32 recent journals, prune inactive extras after one day — avoids deleting another active writer's state; very large numbers of concurrent/recent sessions may leave more physical journal files temporarily. History display and per-file parsing remain capped.
- Ruling: use a verified generic shinchiro standalone mpv build locally rather than compile native upstream sources — no native changes/toolchain; code and runtime are separate, and fork-native build/platform support remains unverified. Pin/version/hash are in animpv/runtime.json, binary directory ignored by Git.
- Final review: fresh independent reviewer, read-only. Critical: none. Important findings: mixed filename episode order and modal hit testing, both reproduced RED then fixed GREEN. Malformed-history fixture corrected to exercise the reader. Preference-at-zero regression reproduced RED then fixed GREEN. No deferred confirmed minors.
- Final review scope rulings: broad real-release naming, crash/power-loss durability, Linux/macOS and hardware/HDR/multimonitor compatibility remain unverified and documented; independent authorship is stated as provenance, not as an external guarantee. IPC/media and rendered/input checks supplied evidence the reviewer did not personally collect.
- Final tests: 22/22 Lua tests on mpv 0.39 and 0.42; six real-media IPC groups; rendered menu/panel, modal isolation, keyboard release and resized pointer checks. See animpv/VERIFICATION.md for evidence and reproducible commands.
- Integration decision: keep codex/animpv-foundation locally; no merge, push or publication requested.

## Compact interface and previews extension

- User explicitly requested a smaller interface, icon controls, improved timeline and hover previews. Completed under `2026-11-09-compact-ui-previews.md`, preserving the original Lua/ASS stack and untouched native core.
- Final extension evidence: 28 Lua tests, 6 media IPC groups, rendered/input checks, and 6 preview/input groups pass on both validated engines. Independent review's 3 findings reproduced, fixed and re-reviewed. See updated `animpv/VERIFICATION.md`; the earlier 22-test count and measurements above describe the original foundation commit.

## Usable baseline checkpoint — 2026-11-11

- User explicitly requested committing the current usable base, with substantial GUI changes still expected. README records this provisional interface status.
- Includes subsequent compact-menu polish, contextual file variants, episode-first playlist labels, chapter captions/full word-wrapped pending preview labels, Windows layout-aware letter keys, single-click pause/double-click fullscreen, and shared cursor/panel inactivity deadlines (2s paused, 1s playing).
- Fresh final checks: 32 Lua tests on both available engines; all current media integration, visual/input, keyboard, preview and autohide scripts on mpv 0.42. All graphical test players use null audio output and mute. One supplied real release was also checked read-only earlier: 12 episodes, nested external voice and chapter markers.
- Read-only independent checkpoint review found no critical/important regression. Keyboard seek/volume/mute/fullscreen visibility-trigger behavior is noted as a future interaction clarification in VERIFICATION.md. No native build, release publication, or GUI redesign is included in this checkpoint.
- Existing unrelated untracked reference audit remains outside the program commit; engines, history, screenshots and test media remain ignored.
