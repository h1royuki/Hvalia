# Contributing

Run `./scripts/check.sh` and `./scripts/build-app.sh` with Swift 6.3 Apple Command Line Tools and a macOS 26+ SDK. The deployment target is macOS 14; older-host runtime and private-framework checks remain separate acceptance work. Tests never write to a phone. Native helper changes require careful review of every device-side mutation; use a spare phone for integration work.

New compatibility profiles need the exact model/board, iOS/build, carrier bundle, original policy structure and independently confirmed modem evidence. Do not generalize from a menu toggle. Do not submit subscriber identifiers, full backups, unredacted logs, IMEI, ICCID, EID, IMSI, serial numbers or device UDIDs. Use synthetic fixtures for tests.

A stable release requires a packaged-app activation and rollback on a spare supported device, interruption exercises, UI/accessibility checks, and a decision on notarized distribution. Current preview is source-first, ad-hoc signed and macOS/Apple Silicon only.
