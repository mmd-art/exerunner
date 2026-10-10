# ExeRunner

Run Windows programs and games on Apple Silicon Macs. One app with a step-by-step setup, a
library of your launchers, games and programs, and shortcuts in Applications for each of them.

Under the hood: Wine 11.16 with CodeWeavers' CrossOver 26.3 changes, Apple's D3DMetal for
DirectX 11 and 12, DXVK on MoltenVK for launchers' Chromium windows, and a compatibility module of
our own that picks the graphics path per program, even for games a launcher starts.

Status: private alpha, tested on an M2 Pro with macOS 27. Russian interface for now.

## What it does

- Installs and runs Steam, and lists your Steam games from every library folder. A game goes to
  a running Steam or starts it; Stop closes the game alone.
- Launcher presets for Steam, EA app, Epic Games Launcher, Ubisoft Connect, Battle.net and the
  Rockstar Games Launcher (all but Steam experimental).
- A compatibility database (from Whisky) that sets graphics, Windows components and variables
  per game.
- Crash diagnosis from wine's log and Unreal's crash reports, a helper with checks and fixes for
  eight kinds of problems, and a report zip with secrets and your user name removed.
- Per-bottle audio, fonts, and a bridge for games' Discord status.

## Build

Needs Xcode's command line tools, Rosetta, and x86_64 Homebrew in `/usr/local` with the
libraries the engine links (freetype, gnutls, gstreamer, ffmpeg, …), plus arm64 Homebrew for
mingw-w64 and cabextract.

```sh
scripts/build-engine.sh all          # the engine into engine/dist (15–30 minutes)
scripts/build-engine.sh portable     # a copy that needs no Homebrew, for the app to carry
scripts/build-app.sh                 # build/app.noindex/ExeRunner.app
scripts/make-dmg.sh                  # build/ExeRunner-<version>.dmg to hand out
tests/cxcompatdb-test.sh && tests/core-test.sh
```

D3DMetal comes from Apple's [Game Porting Toolkit](https://developer.apple.com/download/all/?q=Game%20Porting%20Toolkit):
import its `.dmg` in the app once, and builds carry it from then on (see [CREDITS.md](CREDITS.md)).

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md) for what comes from where.
