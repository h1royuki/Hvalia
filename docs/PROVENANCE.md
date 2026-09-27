# Component provenance

## AirLift (MIT)

Source: https://github.com/0xjohnnydev/airlift

Reviewed source revision: `c684cd41ca0ded2d1ab780c15f6ead05509ce062`.

Adapted files: `Native/device_helper.m`, `Native/airtraffic_host.m`, `Native/airlift_target.h`. Original copyright/license is retained in `Native/LICENSE.airlift`. The streaming ZIP structure and Books manifest follow that source, reimplemented in Swift.

Changes include explicit device identity, country and target-path validation; full Books snapshots and verification; a one-asset argument-count fix; device enumeration with SIM identifiers omitted; bounded reads; strict handling of AFC errors; no upstream canary finish routine; cleanup that retains recovered originals; a persistent Swift transaction coordinator and native logging.

## Native syslog

`Native/HvaliaSyslog.inc` is Hvalia code. It opens `com.apple.syslog_relay` through the installed Apple MobileDevice framework and filters relevant lines locally. The receive API declaration was cross-checked against the primary project header:

https://github.com/DerekSelander/mobdevim/blob/main/mobdevim/misc/ExternalDeclarations.h

No code from commercial activators, proprietary activation blobs or reverse-engineered license checks is included. No third-party binary is downloaded or executed by the app. libimobiledevice was useful during the original investigation but is **not** a runtime or redistributed dependency of Hvalia.

## Apple

MobileDevice.framework and AirTrafficHost.framework are system dependencies, dynamically linked and not redistributed. They expose private APIs with no compatibility guarantee. Foundation, SwiftUI, AppKit and CryptoKit are system frameworks. Swift runtime libraries are supplied by macOS.
