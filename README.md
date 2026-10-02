# Live Mbps Bar

Live Mbps Bar is an iPhone app with a Safari Web Extension that shows the device's current download rate as a 3 CSS px bar at the top of ordinary HTTP and HTTPS pages.

## Project

- Xcode project: `LiveMbpsBar.xcodeproj`
- App target: `LiveMbpsBar`
- Safari extension target: `LiveMbpsBar Extension`
- Minimum OS: iOS 18.0
- App bundle ID: `com.Hitoshi.LiveMbpsBar`
- Extension bundle ID: `com.Hitoshi.LiveMbpsBar.SafariExtension`
- App Group: `group.com.Hitoshi.LiveMbpsBar`

The app screen is a settings interface. Its Safari preview always uses 10.0 Mbps as an example and never measures traffic itself. Live measurement runs only in the Safari extension.

## Build

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project LiveMbpsBar.xcodeproj \
  -scheme LiveMbpsBar \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath work/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Before installing on a physical device, register the two bundle IDs and the App Group in the Apple Developer account, then confirm that both targets use matching provisioning profiles.

## Source layout

- `LiveMbpsBar/LiveMbpsBarApp.swift`: Top, activation detail, settings placeholder, shared setting persistence, and fixed 10.0 Mbps preview.
- `LiveMbpsBar Extension/SafariWebExtensionHandler.swift`: physical Wi-Fi/cellular counter acquisition and raw Mbps calculation.
- `LiveMbpsBar Extension/Resources/background.js`: request coalescing and native messaging.
- `LiveMbpsBar Extension/Resources/content.js`: 250 ms base 1/f rendering, expiry behavior, page overlay, and fullscreen/image-viewer suppression.
- `PROGRESS.md`: implementation decisions, verification, remaining device checks, and restart instructions.

