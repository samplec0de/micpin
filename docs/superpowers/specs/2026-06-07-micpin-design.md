# MicPin — Design

- **Date:** 2026-06-07
- **Status:** Approved (design); pending implementation plan
- **Platform:** macOS 26 (Tahoe) and later, Apple Silicon + Intel

## Problem

macOS automatically switches the **default audio input** to a Bluetooth
headset's microphone the moment it connects. This both
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
- A switch away from the pinned device is reverted by rule 3 while the pinned
  device is present. This applies to **any** source: a manual change in System
  Settings *and* another app setting the default input (e.g. Zoom/Teams
  "use this mic"). MicPin will pull it back within the coalescing window — this
  reach is intended (it is the whole point), and is documented so it is not later
  filed as a bug. The only intended way to change the active microphone is to
  **re-pin** in MicPin (which writes a new pinned UID and immediately applies it).
- **Feedback-loop termination.** Our own `AudioObjectSetPropertyData` *does* fire
  the `DefaultInputDevice` listener. Termination does not rely on the write being
  silent; it relies on `reconcile()` always re-reading the *current* default
  fresh and on rule 4. Once the property settles to the pinned device, the next
  `reconcile()` reads `current == pinned` and writes nothing. Coalescing
  (below) absorbs the transient where a re-read might briefly still return the
  old value, so the loop converges rather than oscillating.
- **Error policy.** `reconcile()` is best-effort and idempotent across retries.
  `setDefaultInput` throwing (device vanished mid-switch) is swallowed; the next
  event re-runs `reconcile()`. Reconcile never propagates an error to a crash.

### Event sources

CoreAudio property listeners on the global object (`kAudioObjectSystemObject`):

- `kAudioHardwarePropertyDefaultInputDevice` — fires when the default input
  changes (auto-switch, manual change, or our own write).
- `kAudioHardwarePropertyDevices` — fires when devices are added/removed.

A short coalescing window (≈100 ms, **trailing debounce** — reset on each event,
fire after quiet) collapses bursts of events (a single Bluetooth connect emits
several) into one `reconcile()` call. Events carry no payload into reconcile;
`reconcile()` always re-reads fresh device-list and default-input state at fire
time (never acts on a captured event snapshot). The `onChange` closure in the
protocol below is intentionally parameterless to enforce this.

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

Every `AudioObjectPropertyAddress` uses **`kAudioObjectPropertyElementMain`**
(the `…ElementMaster` symbol is deprecated since macOS 12 and is a build error
under Swift 6 strict settings).

- **Enumerate inputs:** read `kAudioHardwarePropertyDevices` → for each device,
  read `kAudioDevicePropertyStreamConfiguration` on the **input** scope; keep
  devices with ≥1 input channel. Aggregate devices that expose input channels
  are valid and intentionally pinnable.
- **Per-device metadata:** `kAudioDevicePropertyDeviceUID` (UID),
  `kAudioObjectPropertyName` (display name, read on the **global** scope; take
  ownership of the returned `CFString`; if null/empty, fall back to the UID so
  the UI label is never blank), `kAudioDevicePropertyTransportType` (a `UInt32`
  constant — `kAudioDeviceTransportTypeBluetooth` / `…USB` / `…BuiltIn` / etc.;
  handle Unknown/Virtual/Aggregate for the label).
- **Read default input:** `kAudioHardwarePropertyDefaultInputDevice`
  (global scope) → `AudioDeviceID` → resolve to UID.
- **UID → device (presence + set):** `kAudioHardwarePropertyTranslateUIDToDevice`.
  The UID is passed as the **qualifier** (`inQualifierDataSize`/`inQualifierData`
  pointing at a `CFStringRef`), not in the output buffer. On a UID that matches
  no current device it returns **`kAudioObjectUnknown` (0)**, *not* an error — so
  the present/absent decision (reconcile rules 2 vs 3) compares the result
  against `kAudioObjectUnknown` rather than relying on an `OSStatus`. If two
  devices report the same UID (some virtual drivers), CoreAudio resolves the
  first match; we do not disambiguate.
- **Set default input:** translate pinned UID → `AudioDeviceID` (guard against
  `kAudioObjectUnknown`), then `AudioObjectSetPropertyData` on
  `kAudioHardwarePropertyDefaultInputDevice`. A failing set (device dropped
  between the presence check and the write) is **non-fatal**: it is logged and
  ignored, and the next event re-reconciles (see error policy below).
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
    BT Headset                  (Bluetooth)
    External USB Mic            (USB)
  BT Headset — disconnected       [dimmed, shown only if it is the pinned-but-absent device]
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

The window is an explicitly managed `NSWindow` hosting the SwiftUI view via
`NSHostingController` — **not** the SwiftUI `Settings {}` scene, which is awkward
to open programmatically from an `NSStatusItem` menu across OS versions.

Activation policy: app launches as `.accessory` (menu-bar only, no Dock icon;
`LSUIElement = true` in Info.plist coexists with the runtime `.regular` switch).
When the settings window opens, switch to `.regular`, call `NSApp.activate()`,
and order the window front (otherwise it can appear behind other apps). On close
(`NSWindowDelegate.windowWillClose`), revert to `.accessory` on a
`DispatchQueue.main.async` hop to avoid a momentary ghost Dock icon.

## Persistence

`UserDefaults` (app suite):

- `pinnedInputDeviceUID: String?`
- `pinnedInputDeviceName: String?` (display only, for the disconnected case;
  refreshed whenever the pinned device is next seen present, since macOS lets
  users rename devices)

`LoginItem` reads its state from `SMAppService.mainApp.status`, not UserDefaults.

## Login item

`SMAppService.mainApp.register()` / `.unregister()` (macOS 13+). Caveat for a
self-built, ad-hoc-signed app: registration is keyed off the signed bundle
location and can be unreliable until the `.app` lives in `/Applications`;
`SMAppService.mainApp.status` may read `.notRegistered` right after a successful
`register()` until the app is relaunched from `/Applications`. Therefore the
toggle **re-queries `.status` each time the settings window opens** (never caches
it) and surfaces failures inline in the settings window rather than failing
silently. README documents this. A LaunchAgent plist pointing at the
`/Applications` path is a documented fallback (in practice often *more* reliable
for self-built apps) — not implemented in v1.

## Build & packaging

Swift Package Manager; no `.xcodeproj` checked in (openable in Xcode regardless).

- `Package.swift`: `MicPinCore` library target, `MicPin` executable target,
  `MicPinCoreTests` test target. Platform `.macOS(.v26)`.
- `scripts/bundle.sh`: `swift build -c release`, then assemble
  `MicPin.app/Contents/{MacOS/MicPin, Resources/, Info.plist}` with the
  executable placed at `Contents/MacOS/MicPin` matching `CFBundleExecutable`.
  `Info.plist` keys: `CFBundleIdentifier = com.micpin.app`, `CFBundleExecutable`,
  `CFBundleName`, `CFBundlePackageType = APPL`, `CFBundleShortVersionString`,
  `CFBundleVersion`, `LSMinimumSystemVersion = 26.0`, `LSUIElement = true`. The
  menu bar icon is a system SF Symbol loaded at runtime via
  `NSImage(systemSymbolName:)` (no asset bundling needed), not an Info.plist
  concern. Ad-hoc codesign the single bundle (`codesign -s -`, no `--deep`)
  **after** the Info.plist and executable are in place; re-running `swift build`
  invalidates the signature, so re-sign each time.
- README documents: build, bundle, move to `/Applications`, enable Start at
  Login, and the `xcode-select` note (full Xcode vs Command Line Tools).

## Testing strategy

- `PinControllerTests` against `FakeAudioSystem`, covering each behavior rule:
  no pin → no-op; pin absent → no-op; pin present & wrong → one set; pin present
  & correct → no set; reconnect → restores; manual switch away → reverted;
  re-pin → new UID applied.
- **Feedback-loop test:** the `FakeAudioSystem`'s `setDefaultInput` synthesizes
  an `onChange` (as the real listener would); assert `reconcile()` converges to
  the pinned device with a finite number of sets and no infinite recursion.
- **Failure test:** `setDefaultInput` throws → `reconcile()` stays stable (no
  crash, no propagation) and a subsequent event reconciles cleanly.
- `CoreAudioSystem` is a thin, hardware-touching adapter exercised by manual
  smoke testing (documented checklist), not unit tests.
- Test-driven: write the failing `PinController` tests before its implementation.

## Privacy / no personal data

The repository must contain **no** personal data: no hardcoded user paths
(`/Users/...`), no machine names, no personal email addresses, no device serials.
Bundle id is the neutral `com.micpin.app`. LICENSE is MIT with a neutral
copyright holder ("MicPin Authors"). Real device names appear only at runtime
from the live system, never committed.

## Out of scope / possible future work

- Output-device pinning (same mechanism, `kAudioHardwarePropertyDefaultOutputDevice`).
- Multiple named profiles / quick toggles between two devices.
- Optional notification when an auto-switch is corrected.
- Lower deployment target via `if #available(macOS 26)` glass gating.
- Signed/notarized release + Homebrew cask.
```
