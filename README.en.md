# Shogi Studio

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

A free shogi app for Android and Windows, built with Godot 4.7.2 and a local YaneuraOu engine. Current version: **0.32.0**. **All existing features are free: no membership, purchase screen or paid unlock.**

![Wooden board](docs/images/board-0.20.png)

## Install

Source and packages are public: [0.32.0 Release](https://github.com/DipperHide/shogi-studio/releases/tag/v0.32.0). Daily tournament updates are enabled, and the first cloud refresh completed successfully.

Download `Shogi-0.32.0-android-arm64.apk` from [Releases](https://github.com/DipperHide/shogi-studio/releases) for ARM64 Android devices. On Windows, extract `Shogi-0.32.0-windows-x64.zip`, run `Shogi.exe` and keep the `engines` folder beside it.

Android package: `org.shogistudio.artpreview`, versionCode 50. This build uses the release template with the previous development signing key for upgrade compatibility. Private keys are excluded. Back up your games before installing a build with a different signer.

## Features

- Six computer levels, local two-player games, engine matches, direct IP play and Android Bluetooth; legal moves, promotion and captured-piece drops.
- 2D/3D boards, light/dark themes, custom colors, flipping, dragging, coordinates and proportional captured pieces. Version 0.20 makes the wooden board wider and brighter.
- Main-toolbar undo, animated replay, analysis snapshots, candidate previews and continuation from a selected position.
- Local analysis with 1–5 candidate lines, quick/deep reports, suggested continuations, bad-move alerts, estimated winning chances, mistake practice and phase statistics.
- Version 0.21 adds separate player rows, a winner trophy, proportional phase bars and wrapping metric summaries, with touch and keyboard detail controls. Rating estimates remain unavailable (—) pending shogi calibration.
- JSON/KIF/CSA/USI/SFEN exchange, position editing, interactive lessons, archives and backup/restore. Dragon King 「龍」 app icon.
- Version 0.22 adds two advantage zones and significant-move icons to the score chart, with icon selection, keyboard/drag navigation and aligned phase boundaries.
- Version 0.23 adds expandable category statistics and weighted quality doughnuts, with explanations, rotation, keyboard selection and category navigation back to the board.
- Version 0.24 retargets replay from the currently visible piece poses, preserving position, size and promotion flips across captures, drops, reverse replay and board flipping.
- Version 0.25 adds nested variations, a two-row move ribbon, long-press promotion, undoable deletion and branch-specific comments. Keep the main line or replace it automatically; JSON preserves the complete tree for export and backup.
- Version 0.26 adds a ticked evaluation bar with score/depth, smart/left/bottom placement and continuous animation. Report replay preserves mate distance, with continuation available in the side layout.
- Version 0.27 adds private editor evaluation, pause, piece dragging, per-setup undo/redo, saved setups and SFEN clipboard controls, with fixed Cancel/Done buttons and hand inputs that fit narrow screens.
- Version 0.28 displays the starting pose before advancing piece animations through actual rendered frames. Stalls no longer skip the remaining movement. Playback may take longer on slow devices; Windows rendering stalls remain unresolved.
- Version 0.29 adds category/side filters, multilingual aliases and separate animated opening previews. The original game stays intact until loading; the selected move is retained and landscape shows the full board. The catalog remains nine teaching examples without master-game statistics.
- Version 0.30 adds inline analysis import, paste/file actions, source tabs and recent-game search. A private worker checks full records and comments, including long text and UTF-8/CP932 files. Successful loads open analysis; dismissed or stale replies leave the current record intact.
- Version 0.31 adds a full tournament list with a bottom filter sheet, multiple events, per-game download/cache state and whole-row loading. Recent/offline sources keep separate list state within the session; private validation workers ignore stale navigation results.
- Version 0.32 hints explicitly show Promote / Do not promote, with matching numbered badges on 2D and 3D boards. Alternatives to the same square stay distinct; continuations and full practice hints identify declined promotion. See [promotion hints](docs/PROMOTION-HINTS.md).

[Variation guide](docs/VARIATIONS.md) · [0.32 test results](docs/TESTING-0.32.md) (Chinese) · [Evaluation bar / 評価バー / 评价条](docs/EVALUATION-BAR.md) · [Position editor / 局面編集 / 局面编辑](docs/POSITION-EDITOR.md) · [Opening preview / 戦法プレビュー / 开局预览](docs/OPENING-PREVIEW.md) · [Analysis import / 棋譜入力 / 分析导入](docs/ANALYSIS-IMPORT.md) · [Tournament archive / 大会棋譜 / 大赛棋谱](docs/TOURNAMENT-ARCHIVE.md)

Advanced screens and lessons are mainly in Chinese. Basic navigation supports Chinese, English and Japanese; these READMEs do not imply a fully translated UI.

## Updating Japanese tournament records

Recent events currently contain **26 games**, through the **140-move Ōi game played September 8–9, 2026**. The separate offline archive includes **195 complete games / 23,115 moves**.

The [scheduled workflow](.github/workflows/update-tournaments.yml) checks official pages daily around 21:23 UTC. The app checks its HTTPS catalog once per day when recent events are opened, with a manual refresh button. New entries do not require another APK. GitHub schedules can be delayed and must remain enabled on the default branch.

The published index contains game facts, official links and move hashes. Selecting a game downloads its public KIF, decodes UTF-8/CP932, strips commentary, verifies the move hash and validates every move before caching it locally. Failed updates preserve existing data. Downloaded games and the historical archive remain usable offline.

Availability follows official sites. The collector checks Ōi, Ōza, Kiō, Kisei, Eiō and Ryūō pages, but some have no accessible recent complete KIF. It does not cover every Japanese event, paid sources or live games. See the [official event list](https://www.shogi.or.jp/match/) and [maintenance notes](docs/TOURNAMENT-UPDATES.md).

## Build and test

Use Windows, Python 3.11+, Godot **4.7.2** with matching export templates, JDK 17, Android SDK 36, Build Tools 36.0.0 and NDK 28.1.13356709. Adapt [toolchain.example.json](toolchain.example.json) and save it as `%USERPROFILE%/Development/toolchain.json`.

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements-dev.txt
./scripts/build_android.ps1
./scripts/build_windows.ps1 -OutputDirectory builds/windows-0.32.0
./scripts/test_chessis20.ps1
./scripts/test_chessis20.ps1 -CoreOnly -Network
./scripts/test_chessis23.ps1
./scripts/test_chessis24.ps1
./scripts/test_chessis31.ps1 -CoreOnly
./scripts/test_chessis31.ps1
./scripts/test_chessis32.ps1
```

Open `godot/project.godot` in Godot for desktop development. Runtime assets, engines and NNUE are included; builds restore engine source from its packaged archive. For a release APK, set `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER` and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` locally, then run `./scripts/build_android.ps1 -Release`. Never commit signing credentials.

[CI](.github/workflows/ci.yml) runs core tests on pushes and pull requests. Local tests also cover four screen sizes, both orientations, themes, captures, promotion, drops, continuous animation and the actual engine. See [0.23 statistics validation](docs/TESTING-0.23.md) and [0.20 board/tournament validation](docs/TESTING-0.20.md). Tests cannot guarantee zero bugs. No physical Android device was connected for this release; Bluetooth pairing and background recovery still need device validation.

An approximately 450 ms rendering stall also occurs in an empty Windows window on the test machine and remains unresolved. This release does not claim consistently smooth animation on every device. See [0.24 animation validation](docs/TESTING-0.24.md).

## Data and attribution

Saves remain in the existing `ShogiStudio` user directory; Android uses private app storage. Tournament downloads live in `user://tournaments/`. Updates do not upload personal games.

This independent shogi adaptation is not affiliated with Chessis, the Japan Shogi Association or tournament organizers, and does not claim complete feature/UI parity. See [known differences](docs/CHESSIS-PARITY.md). YaneuraOu ships with corresponding GPL source. Piece calligraphy, fonts, evaluation data and reference artwork retain their own terms and are not relicensed as MIT. See [third-party notices](THIRD_PARTY_NOTICES.md).
