# Architecture and UI

## Stack

- **SwiftUI / AppKit**: native Mac window, system fonts, dark/light appearance, RU/BE/EN text.
- **Swift + Foundation + CryptoKit**: profile validation, a bounded ZIP STORE encoder, SHA-256, durable local sessions, subprocess lifecycle and modem evidence parsing.
- **Objective-C helpers**: Apple's MobileDevice and AirTrafficHost system frameworks. Modified MIT AirLift code for bounded file transfers; a small native read-only syslog_relay client.
- **Swift Package Manager**: no downloaded package dependencies. Command Line Tools suffice. No Electron, local web server, Python runtime or Homebrew dependency for users.
- **Local ad-hoc signing**: no paid certificate. Developer ID / notarization is a future distribution decision, not falsely implied by codesign success.

## Screens

A focused wizard in a fixed 720 × 520 native window:

- Home: Hvalia / «Включение 5G на iPhone в Беларуси», Enable 5G and Restore original settings.
- Shared connection/trust steps with automatic polling, a device selector and Finder guidance.
- Activation: carrier selection, preparation, structured progress, restart, phone settings and optional 60-second modem check.
- Restoration: compatible backups, verified original selection, confirmation, progress, restart and call/data check.
- An unfinished journal takes priority over normal navigation and opens recovery first.

`WizardState` keeps the existing `wizard.json` encoding for compatibility, but the app does not read it on launch. Startup and main-window close reset navigation to a fresh home state; unfinished or damaged sessions force recovery. The last window closing terminates the app. `SessionRecord` remains authoritative for writes. `ConnectionSnapshot` exposes ready/needsTrust/locked/unavailable without guessing an unknown error. `TransactionProgress` drives saving/applying/restoring/finishing labels. Restoration identity checks do not require the previous SIM. `BackupEligibility` validates device/build/profile and recommends the earliest original separately from later snapshots.

Progress is indeterminate. Closing during an operation is refused; force quit and cable removal remain possible. Restart requires a user acknowledgement plus a ready connection to the same phone, because USB reconnection alone cannot prove a reboot. Technical data is under disclosure controls. The demo uses synthetic data and disables writes. See [the complete flows](UI.md).

The storage directory remains `~/Library/Application Support/NRBridge/sessions` to retain earlier backups and share the existing process lock. Rename does not silently copy or discard original settings.

## Transaction

1. Lock concurrent Hvalia instances. Refuse unfinished or damaged journals. Re-read device identity and selected line. Infer and persist one expected country filename; do not treat admission as proof of platform support.
2. Capture tracked and complete Books preimages, ensure agreement, fsync and compare with device.
3. Persist transfer plan before staging. Start live ATC log capture.
4. Export original using StreamingZip + two ATC assets. A fresh generated Media path is used for each operation.
5. Read the recovered original. Write **two** private host copies, fsync, re-read SHA-256. Persist the journal.
6. Restore Books, compare every original byte/path, unlink only the generated link and staging directory. Retain recovered original.
7. Validate country and boolean types. Change exactly three keys. If validation fails after export, reinstall the original unchanged.
8. Repeat snapshot/stage for a fresh-file install. Require the exact session's Airlock move log plus AFC `OBJECT_NOT_FOUND` for the payload source. An ATC send acknowledgement alone is insufficient. Destination is often redacted; this is transfer evidence, not target readback.
9. Restore Books and clean own staging objects. Mark restart needed. NR is a separate user-triggered capture.

Two copies on the same Mac protect against transaction mistakes, not disk loss. Snapshot restoration does not guarantee ATC in-memory cache invalidation; originals must be durable before the next sync can reconcile previous assets. The mechanism cannot read the original without first moving it: disclose that risk in the setup sheet.

## Failure policy

No automatic mutation retry. Any ambiguous result persists recoveryRequired and blocks subsequent setup. Safe pre-install recovery is implemented; post-install ambiguity requires investigation. The app never claims guaranteed rollback under every disconnect. Low-level helper commands are developer interfaces, not a security sandbox against a malicious local user.

## Implementation / release stages

- [x] Native USB identity and local syslog capture.
- [x] Compatibility gate and three-key patch.
- [x] Native UI, backup/rollback flow, persistent transaction and bounded recovery.
- [x] Synthetic fault-injection checks, local build, read-only hardware validation.
- [x] GUI activation + restoration on iPhone 15 / iOS 26.6.2; original readback verified.
- [ ] Controlled physical disconnect exercises on a spare device.
- [ ] Accessibility/VoiceOver audit and full English error localization.
- [ ] Additional iOS builds; real life:) network verification.
- [ ] Intel/earlier macOS investigation and signed/notarized distribution if desired.

No Windows implementation is planned in this repository version.

## 0.1.1 presentation

`WizardShell` owns the unified compact toolbar, scrollable content and pinned progress/actions. `WizardContent` contains the individual steps. `WizardActionBar` uses GlassEffectContainer, native glassProminent buttons and one regular glass back control. Content uses standard system backgrounds. The toolbar menu contains language, backup-folder and recovery links; About is in the system app menu. Layout tokens are 20/16/8 pt. Demo scene arguments allow synthetic visual checks without touching an iPhone.

`FullRestore` permits only the observed empty service lock and the necessary newly created parent directories after sync. Strict preflight comparison still rejects any new tree entry. Runtime lock removal by iOS is accepted only for a previously empty regular lock. Native regression tests invoke the production implementation with an in-memory AFC boundary.

## 1.0.0 presentation

`WavePresentation` is an app-internal title and explanation derived from existing
workflow state. Route position is computed from the same state. It does not persist
another workflow or alter `HvaliaCore` APIs. `WizardShell` owns scrolling, the pinned
warning and action bar; `WizardContent` owns step-specific controls. `WaveComponents`
supplies text headings, notices, result facts, the named left route sidebar
and operation progress. Runtime
transaction progress is a typed, non-persisted model property.

The connected route sidebar uses native SF Symbols; there are no raster illustration resources. Result facts check the
saved operation record before claiming settings were applied; standalone diagnostics
do not make that claim. Navigation enums and journal/wizard encodings remain unchanged.

`Resources/AppIcon.png` is the generated application icon master. `build-icon.sh`
creates the ten standard icon representations using system `sips` and packages
an ICNS using `iconutil`. Packaging copies it into `Contents/Resources/AppIcon.icns`
and declares `CFBundleIconFile`. There are no runtime source-directory dependencies.
The generation prompt and provenance are in `docs/ICON.md`.

Demo exits model initialization before constructing `SessionStore`, and language
changes in demo do not update user preferences. Synthetic scenario injection is
separate from mutation handlers, which continue to refuse demo execution.
`check-ui.sh` compiles the app sources with a separate check entry point and tests
model guards without launching phone helpers. `--render` creates synthetic view
renders in ignored `.private/wave-qa`; these inspect content/layout, while native
window inspection is needed for compositor-rendered Liquid Glass controls.

The minimum deployment target is macOS 14.0 for both Swift targets and native
helpers, matching `LSMinimumSystemVersion`. Liquid Glass APIs are guarded by
`#available(macOS 26.0, *)`; older systems use native bordered buttons. AppKit
locks the outer window to 720 × 520, disables resizing/zoom/full screen, hides the zoom button and resets
previously saved dimensions. The minimum OS is a build/launch requirement;
private device-framework compatibility on older systems still needs hardware testing.

`Localization` provides RU/BE/EN selection, with Belarusian UI text keyed by the existing Russian localization keys. Saved language preference and demo language flags accept all three locales. Diagnostic payloads are preserved in their original wording.
