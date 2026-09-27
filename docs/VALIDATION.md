# Validation

## Local checks

`swift run HvaliaChecks` builds a standalone Swift check executable (no XCTest/Xcode requirement). All fixtures are synthetic. It covers:

- exact three-key patch and preservation of emergency/other values;
- rejecting integer booleans, foreign country, foreign operators and invalid profile path components;
- strict NR evidence vs menus, neighbors, wrong PLMN and ambiguous dual SIM;
- JSON amid framework output; CRC-32 known vector; system unzip ZIP integrity;
- original checksum mismatch and corrupt journal blocking;
- durable originals before the second sync;
- successful rollback to exact original bytes;
- injected failures at ten transaction boundaries, persistence and blocked retry;
- putting an unrecognized exported file back unchanged;
- cross-process operation lock;
- wizard connection/trust transitions, explicit restart acknowledgement, wrong-device reconnect and persisted navigation;
- legacy journals without overlayLeaf, backup eligibility and original selection;
- all three Belarus carriers through the same transaction, followed by exact restoration after SIM removal;
- pre-install recovery and refusal after an ambiguous install.

The suite contains 16 checks, including ten injected transaction failure boundaries.

The checks use a fake device backend and do not change a connected iPhone.

## Historical hardware observations (0.1.0)

On the development Mac (Apple Silicon / macOS 27.0): native USB enumeration correctly detected iPhone 15, build 24A437 and separate Belarus/Russia carrier records. The native syslog client opened the read-only service and received live CommCenter output. The app's SwiftUI build is inspected locally. These checks do not constitute an app activation/rollback test.

The preceding manual method was verified with real modem NR NSA evidence. These initial observations did not include a full GUI activation/rollback cycle; the subsequent 0.1.1 cycle is recorded below. Controlled physical-disconnect recovery remains outstanding. Synthetic tests do not prove activation on every admitted phone.

## Hvalia 0.1.0 preview acceptance

- 14 synthetic checks passed with zero failures, including ten injected failure paths.
- Release bundle built and its ad-hoc signature verified.
- Updated native discovery returned one ready USB phone (read-only).
- Native UI was visually inspected in dark appearance; AX inspection confirmed Russian/English labels, headings, primary actions and a disabled demo write action.
- Full keyboard navigation and spoken VoiceOver testing remain outstanding; the Computer Use connection ended during UI inspection. No accessibility certification is claimed.
- No activation or restore was run on the user's already configured phone during application development.

## 0.1.1

- 16 Swift checks pass: profile path inference/validation, same-target restoration, byte preservation, session persistence and ten injected transaction failure points.
- 10 native Books scenarios compile the **shipping Objective-C implementation** against an in-memory AFC filesystem. They exercise fresh empty locks with/without existing directories, repeat restoration, unknown files, nonempty locks, symlinks, access failures, changed original bytes and disappearing/changed existing runtime locks. They never call device discovery/session functions.
- The real full-restore regression was a new empty `Books/Sync/.bookSync.lock`: every original file already matched, but the old path-set comparison rejected the new lock. The corrected restore preserves an empty service lock and its required directories; unexpected content still fails. An existing runtime lock is never created, truncated or unlinked by restoration.
- Native responses are saved under each session's `operations/` directory. Failures include the helper reason/path instead of losing that detail.

### GUI/device exercise (2026-09-27)

Through the packaged app's buttons on iPhone 15 / D37AP, iOS 26.6.2 / 23G90, MTS Belarus 70.0:

1. Selected the earliest original backup, verified it, restored, and reached the restart screen without full-restore failure.
2. The user restarted the phone. A disabled restart acknowledgement was found and fixed: acknowledgement now waits for a fresh connection independently of transient USB polling.
3. Started activation from the home screen. The original read from the phone **exactly matched** the pre-activation original, verifying the preceding restoration.
4. The replacement differed in exactly Show5GSwitch, Enable5GAutoByDefault and Enable5GByDefault, all set to true. Both Books restores passed. The app reached restartNeeded.
5. The user restarted and confirmed that 5G appeared.
6. Ran two 60-second modem checks through the GUI, including one after airplane-mode reattachment. Neither confirmed active NR. LTE was observed; a `kNRNSA` mention in an IMS capability/preference line was correctly insufficient to claim a serving 5G connection. The user indicated the second phone might lack the carrier's 5G service.
7. Read-only connection timeout during reboot was incorrectly shown as a write failure; it now shows a waiting-for-connection state. A toolbar action now opens network diagnostics without rerunning activation.

Do not describe this as verified real 5G access on every admitted build or carrier. The earlier manual NR result is separate evidence. Phone identifiers, private backups and raw radio logs are excluded from the repository.

### UI inspection in 0.1.1

Russian light and English dark demo windows were visually inspected, including the 580 × 440 minimum window and pinned actions. Enter and Escape transitions were exercised. Tab/Shift–Tab were sent but focus movement could not be conclusively verified through accessibility output. Spoken VoiceOver, Reduce Transparency and Increase Contrast acceptance remain outstanding; no complete accessibility audit is claimed.


## Hvalia 1.0.0 Preview — synthetic validation

- `check.sh`: 16 core checks (including ten transaction fault boundaries), ten native Books scenarios and the app model checks passed. No test writes to a phone.
- Model checks cover early demo isolation before `SessionStore` construction, no preference writes in demo, mutation guards, typed operation progress, independent result evidence, backup validation, wrong-device recovery, damaged storage, busy navigation fixed window/hidden zoom control, clean-launch navigation reset and recovery priority.
- App and both native helpers build with `LC_BUILD_VERSION minos 14.0`; `LSMinimumSystemVersion` agrees. Liquid Glass calls are availability-guarded; the Swift compiler checks the macOS 14 deployment target.
- Synthetic renders cover 36 screens/scenarios × RU/BE/EN × light/dark at the fixed layout (216 renders). Selected preparation, network, result and error layouts are visually inspected; producing the matrix does not constitute manual review of every image. AppKit cache renders do not reproduce compositor Liquid Glass, so native windows are checked separately.
- Native demo inspection includes Enter/Escape navigation, headings and disabled write controls in the accessibility tree, pinned warning/actions with expanded details and a relocated app bundle. Agent-generated documentation screenshots contain synthetic data only; the final README screenshot was supplied by the project author.
- Full spoken VoiceOver, Increase Contrast/Reduce Transparency acceptance and real runtime/device tests on macOS 14/15/26 remain outstanding. No new real-device writes were performed. Older-system support is a lowered build/launch target, not a verified private-framework compatibility claim.

- Belarusian UI translations were checked for coverage of all 169 localized UI keys; dates use the selected locale. Synthetic Belarusian screens were rendered alongside Russian and English. Helper diagnostics retain source wording.

- An earlier synthetic homepage image was captured using macOS window capture with its native shadow. The final README image (`home-dark.png`) was supplied by the project author and copied unchanged; its capture mode and demo provenance were not independently verified. It displays no phone/SIM identifiers.
