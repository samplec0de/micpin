# MicPin

**English** · [Русский](README.ru.md)

A tiny macOS menu-bar app that **pins one microphone** as the system default
input. macOS likes to switch the default input to a Bluetooth headset's mic the
moment it connects (which also drops the headset into low-quality HFP). MicPin
keeps your chosen mic as the default and re-asserts it whenever something
switches away.

<p align="center">
  <img src="assets/screenshot-menu.png" alt="MicPin menu bar menu — pick a microphone to pin; the built-in mic is pinned" width="440">
</p>

## Install

1. Download `MicPin-<version>.dmg` from the
   [latest release](../../releases/latest).
2. Open the DMG and drag **MicPin** into the **Applications** folder.
3. Launch MicPin from Applications. A microphone icon appears in the menu bar.

> **First launch — Gatekeeper.** The app is open-source and ad-hoc signed (not
> notarized by Apple), so on first run macOS may say it "cannot be opened".
> Right-click the app → **Open** → **Open**, or run once:
> ```bash
> xattr -dr com.apple.quarantine /Applications/MicPin.app
> ```

## How it works

- Pick a microphone in the menu bar (or the settings window) to **pin** it.
- While the pinned mic is connected, MicPin keeps it as the default input —
  even when new devices connect or another app tries to switch.
- If the pinned mic is **disconnected**, MicPin does nothing; macOS chooses
  freely. When the mic reconnects, MicPin snaps the input back to it.
- To switch mics, pin a different one in MicPin. (A manual change in System
  Settings is reverted while the pin is active — that is the point.)

MicPin only reads device metadata and sets the default-input property. It never
records audio and needs no microphone permission.

## Requirements

- macOS 26 (Tahoe) or later

## Build from source

Requires the Swift 6.3+ toolchain (full Xcode recommended).

```bash
git clone https://github.com/samplec0de/micpin.git
cd micpin
./scripts/bundle.sh     # builds dist/MicPin.app
./scripts/make_dmg.sh   # builds dist/MicPin-<version>.dmg
```

`bundle.sh` uses full Xcode automatically if only the Command Line Tools are
selected. (To select Xcode globally instead:
`sudo xcode-select -s /Applications/Xcode.app`.)

## Develop

```bash
swift build      # compile
swift test       # run the core unit tests
```

If `swift` resolves to the Command Line Tools and `swift test` reports
`no such module 'Testing'`, prefix commands with the full toolchain:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Open `Package.swift` in Xcode to debug.

## Architecture

- `MicPinCore` — pin logic behind an `AudioSystem` protocol, with a CoreAudio
  implementation. Devices are identified by their stable UID. The core is fully
  unit-tested with an in-memory fake.
- `MicPin` — AppKit menu bar (`NSStatusItem`) + a SwiftUI settings window.

## License

MIT — see [LICENSE](LICENSE).
