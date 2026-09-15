# Validation results

Verified on September 15, 2026, on macOS 27.0 build 26A428.

- 18 Swift tests pass, including four session-state cases in the parameterized session test.
- Five Python release tests pass, including changed-bundle rejection, diagnostic metadata checks, architecture checks, signing identity selection, and pending notarization rejection.
- Universal release compilation succeeds for arm64 and x86_64.
- The read-only probe reports an unlocked session and an available private lock function when run outside the development sandbox.
- The app launches and writes its initial local diagnostic entries in diagnostic-only mode, with no device selected.
- Apple accepted notarization submission `8cda94a0-b2f8-4f26-9eef-d3435e84065c` for prototype build 1.
- Stapling, staple validation, strict code-signature verification, and Gatekeeper assessment succeed. Gatekeeper reports Notarized Developer ID.

Artifact: `build/prototypes/1/Unlocker-prototype-1.zip`. The sibling `release.json` records its SHA-256, and `sources.json` records the packaged source hashes. Documentation updated after packaging is not part of that source snapshot.

Native UI inspection timed out twice. Visual layout and control interaction have not been verified. The launch log confirms startup, not UI quality or Bluetooth reliability.

No Watch has been selected, no automatic or manual lock has been invoked during validation, and no physical proximity traces have been collected. The hardware checklist remains pending, including current Watch identity stability, actual lock confirmation, macOS 26 runtime testing, Intel runtime testing, and second-Mac installation. Sparkle integration and update testing belong to the next milestone after hardware acceptance.

## Build 2: launch-window fix

Added an AppKit-owned diagnostics window with explicit launch, menu, and Finder-reopen handling. Closing the window keeps the menu bar app running. The window opens on startup in this diagnostic milestone, including login launch.

All 18 Swift tests and five release tests pass. The universal build is notarized under submission `209d586d-4624-453f-b1be-45b7c287875e`; stapling and Gatekeeper assessment pass.

Native UI inspection now succeeds. The Diagnostics window and controls were inspected in the accessibility tree and a screenshot. Subsequent inspection showed Bluetooth ready and a named Apple Watch in the discovery list. No Watch was selected by the agent and no lock was invoked. A close/reopen interaction test was left pending because the user had begun scanning in the window.

Use `build/prototypes/2/Unlocker-prototype-2.zip` instead of build 1. The hardware acceptance gate remains in place.

## Build 3: stable Watch picker

Removed live RSSI sorting. Results retain discovery order, new devices append, and stale entries remain until an explicit rescan. Added name/UUID search, fixed-height rows, and a bounded scroll area so discovery does not move calibration controls. Discovery no longer stores unrelated devices outside an explicit scan.

All 18 Swift tests and five release tests pass. Universal build 3 passed notarization, stapling, and Gatekeeper assessment. The new search field and bounded list were inspected in the native accessibility tree and a screenshot. Live selection interaction was not completed because the UI tool repeatedly reported that app state had changed.

Artifact: `build/prototypes/3/Unlocker-prototype-3.zip`.

## Build 4: native menu bar control

Replaced the SwiftUI MenuBarExtra with an explicitly retained NSStatusItem. It uses the standard lock.fill template image, a tooltip and accessibility label, and a text fallback if the image fails. The native menu refreshes monitoring status when opened and provides Diagnostics, Pause/Resume, Lock Now, logs, and Quit. A menuBarRegistered trace records item visibility and button/image creation.

All 18 Swift tests and five release tests pass. Universal build 4 passed notarization, stapling, and Gatekeeper assessment. The previous Watch symbol was verified to exist, so its absence was not established as the cause. System menu bar inspection timed out. The new native item has not yet been visually verified; the user's running copy was left open to preserve unsaved calibration changes.

Artifact: `build/prototypes/4/Unlocker-prototype-4.zip`.

## Build 5: Latch branding

The public app, executable, window title, permission text, and menu labels now use Latch. The bundle ID, signing designated requirement, Application Support directory, and window autosave key remain unchanged. The original Watch selection and calibration files were not modified.

Added the generated silver-latch icon and a native menu bar latch drawing with a paused outline state. AppKit successfully reads all 11 ICNS representations. The built bundle was checked for its name, executable, embedded icon, unchanged bundle ID, and unchanged signing designated requirement.

All 18 Swift tests and five release tests pass. The universal Latch build passed notarization, stapling, strict signature verification, and Gatekeeper assessment. The existing running app was not restarted. Hardware acceptance remains pending.

Artifact: `build/prototypes/5/Latch-prototype-5.zip`.

## Guided calibration development

Added a ten-second desk baseline, a walk-away-and-return recording step, a suggested threshold with explicit save, a live signal chart, and readable timestamped lock previews. Watch selection and manual settings collapse when not needed. The suggestion rejects isolated dips, sparse data, unstable desk signals, and overlapping desk/away signals. Active tests stop on pause or session/configuration changes; Lock Now is disabled during recording.

All 27 Swift tests and five release tests pass. The final local preview is built at `build/Latch.app` with build number 6. Automatic locking remains disabled.

The first notarization attempt could not read `netnewswire-notary` while the Mac was locked. After the user unlocked it, the same profile worked. The failed attempt artifacts are preserved in `build/failed-prototypes/6-notary-attempt`.

Apple accepted build 6 under submission `029845bf-c352-480f-82ac-45b4af903bfa`. Stapling, staple validation, signature verification, and Gatekeeper assessment passed. Artifact: `build/prototypes/6/Latch-prototype-6.zip`.

Inspected the native layout and live signal chart. A real ten-second desk recording advanced to the walk-away instructions. Starting and canceling the walk recording returned to the initial guide. The user's saved threshold remained -72 dBm. No suggested setting was saved and no lock was invoked. A physical walk-away test and the hardware acceptance checklist remain pending.

## Build 7: opt-in automatic locking

Added a persisted automatic-locking switch to the main window and menu bar. Older settings default to preview. Enabling discards old readings and requires a fresh nearby signal. Starting calibration saves automatic locking as off; it stays off until explicitly enabled again. The existing confirmation and failure handling now receives automatic lock requests.

All 31 Swift tests and five release tests pass. Tests cover mode changes, stale preview readings, weak-signal lock requests, pending confirmation, and settings migration. The universal build passed notarization, stapling, signature verification, and Gatekeeper assessment. Submission: `ca1b978b-b68f-443b-b506-427dbce972b6`. Artifact: `build/prototypes/7/Latch-prototype-7.zip`.

Launched the signed build and verified that the enabled automatic-locking control appears in the native window, initially off with the existing Watch selection. No actual lock was triggered during this check. Physical walk-away and lock confirmation remain hardware checks.

## Sparkle and release pipeline

Added Sparkle 2.9.5, an independent Latch update key, fixed feed URL, update settings, and local release packaging adapted from HighDock. Existing bundle identity and settings storage stay unchanged. GitHub Actions runs tests, builds a universal development ZIP, and deploys the feed from published personal releases.

Local validation passes 34 Swift tests and 25 Python tests. The update flow between two installed versions still needs a second-Mac test.
