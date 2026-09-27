# Working on Hvalia

## Project

Hvalia is a native macOS utility for enabling the Belarus 5G settings on an attached iPhone and restoring its original country profile. The product subtitle is **«Включение 5G на iPhone в Беларуси»** / **“Enable 5G on iPhone in Belarus”**. The public repository is `h1royuki/Hvalia`.

Target: Apple Silicon, macOS 14+, Swift 6.3 Command Line Tools with a macOS 26+ SDK. Keep the app native; do not introduce a web UI or a runtime package manager.

## Source map

- `Sources/Hvalia/`: SwiftUI app. `AppModel` coordinates UI state; `WizardShell` owns toolbar and pinned actions; `WizardContent` owns step content.
- `Sources/HvaliaCore/`: profile validation/patching, transactions, durable sessions, workflow, helper process bridge and radio evidence.
- `Native/`: Objective-C device and AirTrafficHost helpers. `HvaliaAdditions.inc` implements Books snapshot/restore behavior.
- `Tests/HvaliaCoreTests/`: standalone Swift checks with synthetic device data.
- `Tests/Native/`: production Books restore code tested against an in-memory AFC boundary.
- `scripts/`: checks, native compilation and app packaging.
- `docs/`: architecture, compatibility evidence, recovery, UI flows and release notes. Read the relevant document before changing that subsystem.

## Build and verification

```sh
./scripts/check.sh       # Swift checks and native Books scenarios; no phone writes
./scripts/build-app.sh   # dist/Hvalia.app, versioned ZIP and SHA256SUMS.txt
open dist/Hvalia.app --args --demo
```

For UI-only changes, build and inspect the affected demo screens; do not add tests that merely repeat labels or layout code. For transaction, persistence, helper or evidence changes, run the existing checks and add a regression case for the concrete failure. Tests must not require a connected phone.

Demo supports `--demo-language ru|be|en`, `--demo-light`, `--demo-dark` and `--demo-step` (for example `prepare`, `backups`, `working` or `result`). Demo writes must remain disabled and must not consume real session data. Use synthetic demo screenshots in documentation.

## Device writes and recovery invariants

A request to change app code is not permission to modify a connected phone. Use an actual device only when the user has authorized that test; respect existing authorization without asking again. Never erase or fully restore a phone as part of routine development.

Preserve these invariants:

1. Read the original from the selected phone; never substitute a generated or foreign “original”.
2. The export moves the original on the device before it can be saved. Keep this risk visible before the operation.
3. Persist the transaction and exact target path before device mutations. Maintain the operation lock and block new activation for unfinished or damaged sessions.
4. Save two durable copies and verify their hashes before installing a replacement.
5. Patch only `Show5GSwitch`, `Enable5GAutoByDefault` and `Enable5GByDefault`; validate country, structure and boolean types. Preserve all other values.
6. Restore exact original bytes and Books preimages. Do not broaden cleanup to unknown paths or ignore unexpected filesystem differences.
7. The empty regular `Books/Sync/.bookSync.lock` is a narrowly handled service artifact. Never create, truncate or unlink an active runtime lock to make verification pass.
8. Do not automatically retry a mutation after an ambiguous result. Preserve evidence and expose recovery.
9. Restore eligibility is separate from activation eligibility. A SIM change alone must not invalidate a saved country profile; device/build/path and integrity checks still apply.

Keep `~/Library/Application Support/NRBridge/sessions` compatible with older copies and journals. New Codable fields need legacy defaults or optional decoding. Never silently migrate away, overwrite or delete the user's originals.

## Compatibility and claims

There is no exact model/build allowlist. The candidate Overlay filename is inferred from the hardware board and carrier settings version; this is not proof that the file exists or that the mechanism works on that iOS version. Retain path validation and same-device checks.

Public operator mentions currently cover **МТС Беларусь** and **life:)**. Do not advertise A1 support. Carrier identity mappings and legacy backup compatibility are distinct from advertised network support; do not remove them as a cosmetic change. Exclude MTS Russia from Belarus activation.

Distinguish three results: settings applied, 5G menu observed, and active NR connection confirmed. Only modem evidence for the selected line during the check can confirm network access. Capability/preference lines, neighboring cells and the status-bar icon are insufficient. Do not claim that Hvalia provisions a carrier service or adds coverage.

## UI and writing

Keep Russian/English strings paired through the existing localization helper and Belarusian translations in Localization.swift. Use concise user-facing instructions; place builds, MCC/MNC, hashes and logs behind disclosures.

Use native SwiftUI controls and Liquid Glass for navigation/actions on macOS 26+, with native bordered buttons on earlier systems. Use standard backgrounds for content. Keep the window fixed at 720 × 520 (no resizing or full screen), spacing 20/16/8 pt, `title2` headings, and the primary action visible outside the scrolling content. Preserve keyboard shortcuts and accessibility labels. Do not claim a complete VoiceOver or accessibility audit without performing it.

README describes the product, installation and usage. Put incident details and test evidence in `docs/VALIDATION.md`, implementation details in `docs/ARCHITECTURE.md`, and recovery instructions in `docs/RECOVERY.md`. Keep historical release notes historical.

## Privacy and distribution

Never commit phone/SIM identifiers, raw modem logs, session directories, private backups or credentials. `.private/`, `sessions/`, `backups/`, build outputs and `dist/` stay ignored. Use invented identifiers in fixtures. Keep upstream license notices and component provenance intact.

Before publishing, inspect the staged files and `git diff --check`. Publish only the intended app archive and checksum file; never replace an existing version's assets silently. Update the build script version, About version and release notes together when making a new release. The app is ad-hoc signed, not notarized; successful codesign is not Apple notarization. Keep Preview status until the documented remaining acceptance checks are complete.
