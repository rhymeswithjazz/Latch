# Latch

A macOS menu bar app that locks your Mac or starts its screen saver when your Apple Watch moves away.

Choose **Lock Screen** or **Start Screen Saver** under **When I walk away** in Settings, then turn on the walk-away switch. The menu bar menu can also turn it on or off. Both choices survive relaunch. Lock Screen remains the default, and automatic actions are opt-in. Latch requires a fresh nearby signal before arming and waits for confirmation of the selected action.

Screen saver mode starts your macOS screen saver. Your macOS Lock Screen settings control when a password is required. Monitoring pauses while the saver runs. Dismissing it requires a fresh nearby Watch reading before Latch can act again. Changing the selected action also discards earlier readings.

Requires macOS 26+, Xcode with Swift 6.2+, and Python 3.11+. Sparkle 2.9.5 is pinned in Package.resolved.

## Build and run

```sh
./scripts/test.sh
./scripts/build.sh --universal
open build/Latch.app
```

Open Settings from the latch icon in the menu bar. Click Scan, grant Bluetooth access, and select your Watch by comparing its signal as you move it. Device names are hints, not proof of ownership. Use the same Apple Account on the Mac and Watch; stable identity remains a hardware acceptance requirement.

### Guided calibration

1. Sit at your laptop wearing the selected Watch and wait for a fresh signal.
2. Under **Find your walk-away setting**, click **Record my desk signal** and stay seated for ten seconds.
3. Click **Start walk-away test**. Walk to the spot where you want the selected action to run, stay for fifteen seconds, then return. You do not need to watch the screen while away.
4. Click **I’m back — review my test** within two minutes. Latch compares the desk signal with a sustained weaker part of the walk and suggests a threshold.
5. Click **Use this setting** to save it. Your existing delays remain unchanged.
6. Wait for **Observing proximity**, then repeat your walk. The in-app **Action previews** list shows whether and when Latch would have run the selected action. The signal chart shows your saved threshold and preview event markers.

Unstable, missing, or overlapping readings produce a retry explanation without applying a recommendation. Pausing, changing the Watch or settings, locking, or sleeping interrupts calibration. Adjust the threshold under **Walk-away signal level** and click **Save signal level**. The saved level applies to the current mode and persists between launches without changing your delays. Delays, passive mode, and the manual action button are under **Advanced settings**. Starting calibration turns the automatic walk-away action off. Turn it back on after testing your saved setting.

Passive mode listens for advertisements instead of maintaining a connection. Use it to compare radio reliability or investigate interference with headphones, keyboards, mice, or Personal Hotspot. Missing signals after monitoring is armed trigger the selected action, or a preview when automatic actions are off, even if Bluetooth turns off. Pause suspends observation; resume, unlock, and wake require a fresh nearby reading.

Use **Lock Now** or **Start Screen Saver Now** in the menu bar or advanced settings to run the selected action immediately. The last event and logs show whether it was confirmed. No password is stored and Latch never unlocks the Mac. Launch at login is optional; put the signed app in a stable location first.

## Diagnostics

Reveal Diagnostic Logs opens `~/Library/Application Support/Unlocker/`. It contains:

- `configuration.json`: selected Core Bluetooth UUID, device name, calibration, and walk-away action.
- `diagnostics.jsonl`: timestamped selected-device samples, sample gaps, session changes, Bluetooth errors, action previews, and action results. Action entries include the selected action; existing lock event names remain for log compatibility.
- `diagnostics.previous.jsonl`: previous log after rotation at approximately 5 MB.

Logs stay local and have owner-only file permissions. They contain device identifiers and names; review them before sharing. Invalid settings are kept untouched and the app refuses to overwrite them. Move the invalid configuration file aside and relaunch to reset setup.

## Project layout

- `UnlockerCore`: deterministic proximity policy and persisted settings.
- `UnlockerPlatform`: Core Bluetooth, session state, the private lock function, screen saver launch, and local storage.
- `Unlocker`: diagnostic window, menu bar, and launch at login.

No root helper, Accessibility permission, or private Bluetooth address access is used. Screen saver mode launches the system ScreenSaverEngine app through NSWorkspace. `SACLockScreenImmediate`, session lock keys, and distributed lock and screen saver notifications are undocumented integrations. Verify them on every supported OS release.

## Release and acceptance

See [release setup](docs/PersonalReleases.md) and the [hardware checklist](docs/HardwareAcceptance.md). Passing unit tests or notarization does not prove Watch tracking. Automatic locking is available for local testing. Watch identity stability, physical walk-away reliability, and actual lock confirmation still need hardware validation. See [personal releases](docs/PersonalReleases.md) for signed builds, Sparkle updates, and GitHub Pages deployment.

## Latch name and icon

The app is now Latch. Its bundle ID, local data directory, and internal Swift target names retain Unlocker for continuity. Existing Watch selection and calibration stay in place. Quit the old copy before opening Latch. When moving the app to its permanent location, register Launch at Login from that copy. See [brand assets](docs/Brand.md).

## Updates and CI

GitHub Actions tests Swift and release tooling, builds a universal development app, and uploads its ZIP. Development builds have updates disabled.

Signed releases are packaged locally with Developer ID, notarized, and signed with Latch’s own Sparkle key. Publishing a `personal-*` GitHub release rebuilds the GitHub Pages appcast. Distribution builds offer **Check for Updates**, automatic update checks, and an opt-in test-build channel. Update installation preserves the bundle identity and local settings.
