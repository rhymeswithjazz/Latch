# Hardware acceptance

Status: pending. No physical Watch reliability or actual lock transition has been verified yet.

Use the signed prototype, record the Mac model, macOS build, Watch model, watchOS build, selected device UUID, mode, and calibration. Keep the corresponding diagnostic logs with the test notes. Do not infer stable identity from a device name or one scan.

## Session and lock function

1. Start unlocked and confirm diagnostics says Select your Watch or Waiting for a nearby reading, not Suspended.
2. Click Lock Now. Unlock normally, then check for `lockRequested` followed by `lockConfirmed`. A `lockFailed` event blocks acceptance.
3. Repeat with the screen saver password delay set to a non-immediate value. Lock Now must still lock immediately. Restore the original setting after testing.
4. Lock manually, sleep/wake, close/open the lid, and switch users. Confirm observation suspends and only rearms after a fresh nearby reading. Confirm no repeated lock loop after manual unlock without the Watch nearby.

## Watch identity and readings

1. Discover and select the Watch using its movement and RSSI response. Confirm the Mac and Watch use the same Apple Account.
2. Observe for at least 60 minutes, spanning several potential address rotations. Include the Watch display sleeping. Confirm UUID and valid readings persist; inspect sample gaps.
3. Relaunch the app, restart the Watch, and sleep/wake the Mac. Confirm the saved selection reconnects without manual reselection. Watch restart may temporarily cause a signal-loss proposal, but identity must recover.
4. Repeat with Bluetooth headphones, keyboard, mouse, Wi-Fi traffic, and any Personal Hotspot you use. Compare active and passive modes. Record unexplained disconnects, sample gaps, and peripheral interference.
5. Record Mac CPU use and Watch battery change during a normal work session. Note any regression compared with the app stopped.

## Proximity

1. Calibrate at the desk and departure point. Perform ten walk-away/return trials in the room where the app will run.
2. Confirm a proposal follows sustained filtered weakness within the configured delay plus two polling intervals. Do not measure timing from an assumed distance crossing.
3. Stay at the desk for at least one normal work session. Move your wrist normally. Require zero unexplained lock proposals before enabling automatic locking.
4. Test a brief RSSI drop, departure beyond radio range, Watch power-off, and Mac Bluetooth off. Brief drops must recover; missing samples must produce a proposal after the configured 30-second default timeout, within two polling intervals.
5. Return nearby after a proposed lock and confirm the next departure produces a new event.

## Release gate

Build 7 adds opt-in automatic locking for local hardware testing at the user’s request. Complete these checks before broader distribution. If selected identity rotates or valid readings repeatedly disappear while the Watch is nearby, keep the diagnostic build and investigate the traces. Do not silently select a device with the same name.

Before wider distribution, repeat on macOS 26 and the current macOS release, and test on a second Mac. Universal compilation alone does not prove Intel runtime compatibility.
