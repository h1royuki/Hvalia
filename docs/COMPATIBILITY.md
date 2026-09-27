# Compatibility

## Evidence scope

As of 2026-09-27, a manual transaction using the same mechanism succeeded on:

- iPhone 15: `iPhone15,4`, board `D37AP`.
- iOS `27.0`, build **`24A437`**.
- MTS Belarus `25702`, bundle `com.apple.MTS_by`, version `72.0`.
- Overlay: `/var/mobile/Library/CountryBundles/Overlay/device+carrier+com.apple.Belarus+D37+72.0.plist`.

The original booleans were false. Changing three booleans to true and restarting exposed 5G On / Auto. Live modem logs subsequently showed Belarus PLMN, `kEX_3GPP_5G`, `kNRNSA`, an active PDP context and `endc_sub6` on the data interface. Neighbor NR ARFCN metrics were not used to infer a serving band.

## Admission in 0.1.1

There is no exact iOS/build/model allowlist. The phone must identify as an iPhone and report a syntactically valid hardware board. A Belarus carrier (25701, 25702 or 25704) and a numeric carrier settings version are required to construct the expected country filename. For example D37AP and 70.0 produce `device+carrier+com.apple.Belarus+D37+70.0.plist`.

The carrier version is an inference for the country filename, **not a verified country-version query**. A matching file or working transfer mechanism is not assumed. No candidate scanning or automatic mutation retry occurs. The recovered original must validate as Belarus and contain three boolean keys before it is patched. An invalid recovered original is restored unchanged. Missing/ambiguous transfer evidence enters recovery.

Public operator support is presented for MTS Belarus and life; life network results remain unverified. The existing 25701 identity mapping is retained for device recognition and legacy sessions, but A1 is not advertised as supported. Country policy can affect both Belarus SIMs. MTS Russia 25001 is not patched. The change cannot add hardware 5G support to an older phone.

New sessions save the actual attempted filename for activation, restoration and recovery. Legacy sessions without a filename retain their original D37/72.0 target. Restoration still requires the same device, board and iOS build as the backup, to avoid restoring obsolete settings after an OS update; a SIM change is allowed.

The 0.1.1 read-only check observed iPhone15,4 / D37AP on iOS 26.6.2 / 23G90 with MTS BY 70.0. This configuration is now admitted. The 0.1.1 GUI restoration/activation cycle succeeded on this configuration: restored bytes were read back exactly, then only three booleans were changed. The user confirmed the 5G options. Two live network checks reported LTE without sufficient evidence for an active NR connection. The user indicated this second phone may lack the 5G subscription; that was not independently verified.

## Mac

Initial locally verified host: Apple Silicon, macOS 27.0. The 1.0.0 package targets macOS 14.0 and later on Apple Silicon. The app and both helpers carry that minimum; Liquid Glass falls back to standard native controls before macOS 26. Runtime/device operations on macOS 14/15/26 and Intel are not validated. Private framework symbols can change even when compilation succeeds. The native helpers resolve the system frameworks; no Apple binaries are bundled.

## Operator requirements

5G provisioning and radio coverage are outside the application's control. Enabling the menu does not unlock a subscription, create coverage or add unsupported radio bands. Real network results are separately reported.
