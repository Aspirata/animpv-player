# AniMPV

[Русский](README.md) | **English**

AniMPV is a fork of [mpv](https://github.com/mpv-player/mpv) with independently developed additions for watching anime. The project is developing its own interface and tools for episodes, external tracks, and watch history.

## About the project

AniMPV is inspired by the excellent Adventurer Kun build and explores similar ideas. It was created with the aim of bringing those ideas to multiple platforms, addressing some shortcomings, and developing a more open project with open source code.

AniMPV is an independent alternative with a different implementation and its own final look and feel. It is not an “improved” version of Adventurer Kun or a direct replacement for that build.

## Features

- Compact controls, menus, and seek previews.
- Discovery of external audio tracks and subtitles, with voice track selection and preferences.
- Automatic episode ordering and a choice between file variants.
- Local watch history and playback resumption on request.

## Project status

The basic features are usable. The interface is preliminary and will be redesigned. Testing currently focuses on Windows x64; Linux and macOS support has not yet been verified. An installer, updater, and several additional media tools have not yet been implemented.

## Getting started

Releases are intended to include the mpv engine as a ready-to-use AniMPV package.

When running from the source repository, provide the engine separately: place standalone mpv with LuaJIT and its required libraries in `animpv/bin/`, set `ANIMPV_MPV` to its path, or add mpv to PATH. Testing has covered mpv 0.39 and 0.42. Then run `animpv/Start-AniMPV.cmd` or drag a video onto it.

Detailed instructions, controls, limitations, and verification commands are available in the [AniMPV guide](animpv/README.md) (Russian).

## Versioning

Release names follow **AniMPV vX — vY**: the first number identifies the AniMPV version, and the second identifies the bundled mpv engine. For example, `AniMPV v1 — v0.42.0-11` identifies AniMPV `v1` with an mpv build made after release 0.42.0.

The AniMPV version is incremented as a whole number when the project changes; when only the engine is updated, its version changes. Future updates are intended to use stable mpv releases. For builds between releases, the release details include the full version with commit identifier, source, and checksum. Git tags use the format `v1_v0.42.0-11`.

## Development and documentation

Yes, this project is made with the help of AI — ChatGPT Sol 6.1 High. But the approach is more than just “make it look nice”: I try to make sure the results come together as a cohesive project.

- [Original mpv README](README.mpv.md) — information about the upstream project, building, and mpv licensing.
- [Origin and license of AniMPV additions](animpv/ORIGIN.md) (Russian).
- [AniMPV verification results and limitations](animpv/VERIFICATION.md) (Russian).
- [Architecture and development direction](DOCS/superpowers/specs/2026-11-09-animpv-independent-design.md) (Russian).

AniMPV additions are located in `animpv/`; the mpv source remains at the repository root. Use AniMPV’s separate configuration during development to avoid changing the settings of an installed mpv.
