# Live Mbps Bar 1.0.0 release baseline

Frozen: 2026-10-02 JST

## Version identity

- Product version: `1.0.0`
- Build number: `1`
- Safari extension manifest version: `1.0.0`
- Minimum supported iOS version: `18.0`

The app target, Safari extension target, extension manifest, and in-app Information screen all identify this release as Version 1.0.0.

The final Version 1.0.0 icon is the user-supplied `NCB2_icon.004.png`, a 1024×1024 PNG with SHA-256 `5d9cfebeeddf0fa82059d5c7a7f2956e8b2a3c985188ae24cc827536f94ab446`. The AppIcon and activation-row copies match it byte-for-byte, and the Safari extension icons are resized from that same image.

## Validation at freeze

- JavaScriptCore syntax validation passed for the final `content.js`.
- iOS Simulator Debug build passed with Xcode 27.0.
- Generic iPhoneOS Debug build with signing disabled passed with Xcode 27.0.
- The final `content.js` in both build products matched the source byte-for-byte.
- Built app and extension Info plists both resolved to product version `1.0.0`, build `1`.

## Accepted Version 1.0.0 behavior

- The overlay uses the original static fixed CSS sizing because stable scrolling and avoiding Safari's upper-inset tint take priority over enlarging the overlay on legacy pages.
- Pages without a mobile viewport declaration may display the Mbps bar and label smaller.
- Safari 26 can draw page content into its obscured top inset, making the fixed Mbps label appear to float below the physical screen edge. This is accepted as platform behavior for Version 1.0.0.
- Safari toolbar expansion can partially obscure the fixed label in some top-address-bar states. This is accepted as platform-dependent behavior for Version 1.0.0.

## Integrity record

`RELEASE_1.0.0.sha256` contains SHA-256 hashes for the 30 source, project, configuration, and image-asset files that define this release. Its own SHA-256 is:

`ea49c8ce0db97f4d7ee92c2eb87e5c66f6928f4713e65d97fa633eb256288e12`

Any later change to a listed file can be detected by regenerating the hashes and comparing them with that manifest.
