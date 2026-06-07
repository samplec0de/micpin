# MicPin — Design

- **Date:** 2026-06-07
- **Status:** Approved (design); pending implementation plan
- **Platform:** macOS 26 (Tahoe) and later, Apple Silicon + Intel

## Problem

macOS automatically switches the **default audio input** to a Bluetooth
headset's microphone the moment it connects (e.g. Huawei FreeBuds). This both
overrides the user's preferred microphone and forces the headset into the
low-quality HFP profile (degrading playback). macOS offers no built-in way to
pin a specific input device so it survives reconnections and the connection of
new devices.

## Goal

A small macOS app that lets the user **pin one input device**. While the pinned
device is present, the app keeps it as the system default input even when other
devices connect or something tries to switch away. The user changes the active
microphone only through the app.

## Non-goals (v1)

- Managing **output** devices (the app concerns microphones only).
- Notifications / toasts when an auto-switch is corrected.
- Code signing / notarization / Gatekeeper distribution (the user builds it
  locally; ad-hoc signing only).
- Per-app input routing, profiles, or scheduling.
- Lowering the deployment target below macOS 26 (can be revisited later behind
  availability checks).

## Behavior specification (the core)

A device is identified by its **UID** (`kAudioDevicePropertyDeviceUID`) — a
stable string that survives reconnects and reboots. The numeric `AudioDeviceID`
changes between connections, so it is never persisted; only the UID is.

State: an optional **pinned UID** (with a cached display name for UI).

`reconcile()` runs on every relevant CoreAudio event. Its rules:

1. **No pin set** → do nothing.
2. **Pin set, pinned device absent** from the current input device list → do
   nothing. macOS chooses the default freely. (Sticky-idle.)
3. **Pin set, pinned device present, current default input ≠ pinned** → set the
   default input to the pinned device.
4. **Pin set, pinned device present, current default input == pinned** → do
   nothing.

Consequences of these rules:

- When the pinned device **reconnects**, the next event triggers rule 3 and the
  input snaps back to it.
- A manual change in **System Settings** is treated as an unwanted switch and is
  reverted by rule 3 (while the pinned device is present). The only intended way
  to change the active microphone is to **re-pin** in MicPin (which writes a new
  pinned UID and immediately applies it).
- `reconcile()` is **idempotent**: rule 4 means our own write does not cause a
  correcting write, so the listener feedback loop terminates after one set.

### Event sources

CoreAudio property listeners on the global object (`kAudioObjectSystemObject`):

- `kAudioHardwarePropertyDefaultInputDevice` — fires when the default input
  changes (auto-switch, manual change, or our own write).
- `kAudioHardwarePropertyDevices` — fires when devices are added/removed.

A short coalescing window (≈100 ms) collapses bursts of events (a single
Bluetooth connect emits several) into one `reconcile()` call.

## Architecture

Two modules. Core logic is isolated from CoreAudio behind a protocol so it is
unit-testable without hardware.

```
MicPinCore  (library, no AppKit/UI)
  AudioDevice          value type: uid, name, isInput, transportType
  AudioSystem          protocol: enumerate inputs, read/set default input UID,
                       subscribe to change events
  CoreAudioSystem      real implementation wrapping CoreAudio C APIs
  PinController        owns pinned UID + persistence; implements reconcile()

MicPin  (executable, AppKit + SwiftUI)
  main.swift           NSApplication bootstrap, .accessory activation policy
  AppDelegate          wires PinController + CoreAudioSystem + UI together
  StatusItemController NSStatusItem + NSMenu (quick pin)
  SettingsView         SwiftUI settings window
  LoginItem            SMAppService wrapper (start at login)
```

`PinController` depends only on the `AudioSystem` protocol and a persistence
abstraction (`UserDefaults` by default). The UI observes `PinController` for the
device list and pinned state and calls `pin(uid:)` / `unpin()`.

### AudioSystem protocol (sketch)

```swift
protocol AudioSystem: AnyObject {
    func inputDevices() -> [AudioDevice]
    func defaultInputUID() -> String?
    func setDefaultInput(uid: String) throws
    var onChange: (() -> Void)? { get set }   // fired (coalesced) on any event
}
```

`PinController.reconcile()` uses only these calls, so tests inject a
`FakeAudioSystem` to drive every branch of the behavior spec.

## CoreAudio details

- **Enumerate inputs:** read `kAudioHardwarePropertyDevices` → for each device,
  read `kAudioDevicePropertyStreamConfiguration` on the **input** scope; keep
  devices with ≥1 input channel.
- **Per-device metadata:** `kAudioDevicePropertyDeviceUID` (UID),
  `kAudioObjectPropertyName` (display name),
  `kAudioDevicePropertyTransportType` (to label Bluetooth/USB/built-in).
- **Read default input:** `kAudioHardwarePropertyDefaultInputDevice`
  (global scope) → `AudioDeviceID` → resolve to UID.
- **Set default input:** translate pinned UID → current `AudioDeviceID` via
  `kAudioHardwarePropertyTranslateUIDToDevice`, then
  `AudioObjectSetPropertyData` on `kAudioHardwarePropertyDefaultInputDevice`.
- Listeners registered with `AudioObjectAddPropertyListenerBlock` on a dedicated
  serial dispatch queue; `onChange` is hopped to the main actor for UI.

No microphone TCC permission is required: the app only reads device metadata and
sets the default-device property; it never opens an input stream or records.

## UI design

Target the **macOS 26 SDK** so standard SwiftUI/AppKit controls adopt Liquid
Glass automatically. The guiding principle (Apple HIG): Liquid Glass belongs to
the floating navigation/control layer, **not** to content. Therefore:

- The **device list is content** → plain `List`/`Form` rows, no glass on rows,
  no per-row tint.
- Explicit glass is used **sparingly**: at most the single primary action
  (e.g. "Open Settings" / a prominent pin action) via `.buttonStyle(.glass)` or
  `.glassProminent`. Multiple adjacent glass elements, if any, are wrapped in a
  single `GlassEffectContainer` (glass cannot sample glass).
- **No stacking** glass, no decorative tinting — laconic by default. System
  components already carry the new look; we add almost nothing.
- Accessibility (Reduced Transparency, Increased Contrast, Reduced Motion) is
  honored automatically because we use the system material rather than faking it.

### Menu bar (`NSStatusItem`)

SF Symbol icon (e.g. `mic.fill` / `pin.fill` overlay when a pin is active). Menu:

```
Pinned input
  ✓ MacBook Microphone          (built-in)
    HUAWEI FreeBuds             (Bluetooth)
    External USB Mic            (USB)
  HUAWEI FreeBuds — disconnected  [dimmed, shown only if it is the pinned-but-absent device]
─────────────────────────────
  Unpin (follow system)
─────────────────────────────
  Open Settings…
  Start at Login            ✓
  Quit MicPin
```

- Clicking a listed device pins it and immediately switches to it.
- A checkmark marks the pinned device.
- If the pinned device is currently absent, it is shown dimmed with a
  "— disconnected" suffix so the user knows what is pinned.
- The menu is a system `NSMenu`; we do not hand-apply glass to it.

### Settings window (SwiftUI)

A small, fixed-size window opened from the menu. Contents:

- **Microphones** section: live list of all input devices. Each row shows name,
  transport label, a marker for the **pinned** device and a marker for the
  **currently active** default input (these can differ briefly during a switch).
  A pin/unpin control per row.
- If the pinned device is disconnected, it appears as a dimmed row labeled
  "disconnected" so the pin is never invisible.
- **Start at Login** toggle (bound to `LoginItem`).
- Footer: app name + version.

Activation policy: app launches as `.accessory` (menu-bar only, no Dock icon).
When the settings window opens, switch to `.regular` and activate; when it
closes, return to `.accessory`.

## Persistence

`UserDefaults` (app suite):

- `pinnedInputDeviceUID: String?`
- `pinnedInputDeviceName: String?` (display only, for the disconnected case)

`LoginItem` reads its state from `SMAppService.mainApp.status`, not UserDefaults.

## Login item

`SMAppService.mainApp.register()` / `.unregister()` (macOS 13+). Caveat for a
self-built, ad-hoc-signed app: registration can be unreliable until the `.app`
lives in `/Applications`. README documents this; the toggle surfaces failures
rather than failing silently. (LaunchAgent plist is a documented fallback if
needed — not implemented in v1.)

## Build & packaging

Swift Package Manager; no `.xcodeproj` checked in (openable in Xcode regardless).

- `Package.swift`: `MicPinCore` library target, `MicPin` executable target,
  `MicPinCoreTests` test target. Platform `.macOS(.v26)`.
- `scripts/bundle.sh`: `swift build -c release`, then assemble
  `MicPin.app/Contents/{MacOS/MicPin, Resources/, Info.plist}`. `Info.plist`
  sets `LSUIElement = true`, bundle id `com.micpin.app`, version, and the SF
  Symbol-based menu bar icon. Ad-hoc codesign (`codesign -s -`) so it launches.
- README documents: build, bundle, move to `/Applications`, enable Start at
  Login, and the `xcode-select` note (full Xcode vs Command Line Tools).

## Testing strategy

- `PinControllerTests` against `FakeAudioSystem`, covering each behavior rule:
  no pin → no-op; pin absent → no-op; pin present & wrong → one set; pin present
  & correct → no set (idempotency / no feedback loop); reconnect → restores;
  manual switch away → reverted; re-pin → new UID applied.
- `CoreAudioSystem` is a thin, hardware-touching adapter exercised by manual
  smoke testing (documented checklist), not unit tests.
- Test-driven: write the failing `PinController` tests before its implementation.

## Privacy / no personal data

The repository must contain **no** personal data: no hardcoded user paths
(`/Users/...`), no machine names, no personal email addresses, no device serials.
Bundle id is the neutral `com.micpin.app`. LICENSE is MIT with a neutral
copyright holder ("MicPin Authors"). Real device names (e.g. "HUAWEI FreeBuds")
appear only at runtime from the live system, never committed.

## Out of scope / possible future work

- Output-device pinning (same mechanism, `kAudioHardwarePropertyDefaultOutputDevice`).
- Multiple named profiles / quick toggles between two devices.
- Optional notification when an auto-switch is corrected.
- Lower deployment target via `if #available(macOS 26)` glass gating.
- Signed/notarized release + Homebrew cask.
```
