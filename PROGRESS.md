# Live Mbps Bar implementation record

Updated: 2026-10-03 JST

Version 1.0.0 was declared fixed on 2026-10-02 JST. The release baseline and accepted platform-dependent behaviors are recorded in `RELEASE_1.0.0.md`; exact source and asset hashes are stored in `RELEASE_1.0.0.sha256`.

## Current state

The formal implementation, the first two iPhone 13 Pro UI feedback revisions, and the stalled `— Mbps` recovery fix are complete in `/Users/hitoshi0002/Documents/Codex/LiveMbpsBar`. The PoC at `/Users/hitoshi0002/Documents/Codex/PoC/Net_Condition_Bar2` was not modified.

The project builds successfully for both the iOS Simulator and the generic iOS device SDK with Xcode 27.0. The app was installed and launched on an iPhone 17 simulator running iOS 26.5; the Top screen, fixed 10.0 Mbps preview, icon asset compilation, and embedded Safari extension were verified.

On 2026-10-03, the Top-page description was changed to “Show live net speed as a bar at the top of Safari.”, the activation guidance to “Enable Live Mbps Bar in Safari Extensions.”, and the activation link from “Detail” to “Details”. Simulator and connected iPhone 13 Pro signed Debug builds succeeded.

## Implemented behavior

### App

- iPhone-only, English UI, iOS 18.0 minimum, dark appearance.
- Top, screenshot-based activation detail, and Information screens.
- Cold launch and foreground return recreate the Top screen.
- Detail and Settings destinations share an explicit right-swipe dismissal gesture. A rightward drag of at least 80 points with horizontal displacement greater than 1.5 times its vertical displacement returns to Top. It runs simultaneously with the Detail page's vertical ScrollView gesture, and an accessibility escape action also dismisses the destination. Existing back buttons remain available.
- Top preview is fixed at 10.0 Mbps. It uses the iPhone/Safari capture embedded in specification p.4 and reacts only to Color, Max Mbps, and Show speed settings.
- The English description under the title flows naturally into two lines. The preview address text is intentionally blank, and the former `Settings` heading is removed so the Color card follows the preview directly.
- The Top-screen gear button is now an information-circle button. It opens an `Information` screen with an Article Shelf-style accordion containing `What’s Live Mbps Bar`, `Support`, `Privacy Policy`, `Disclaimer`, and `Version`. All five sections contain the user-provided copy. The Support website and email address are blue, tappable HTTPS and `mailto:` links.
- Initial settings: green, 20.0 Mbps, Show speed ON.
- Twelve-color palette arranged as specified. Exact RGB values are replaceable constants because the specification fixed the color names/layout but did not provide RGB codes.
- Max Mbps accepts 0.1–1,000.0 with at most one decimal place. It saves on editing completion; invalid input shows an alert and restores the last valid value. A UIKit decimal field supplies a reliable `Done` accessory, and the scroll view moves the Max Mbps card directly above the keyboard while editing.
- The activation detail page uses the Settings captures embedded in specification p.4, adds consistently sized red indication arrows, and scrolls through the final `All Websites` row. The extension-selection row is rendered with the current app icon and the name `Live Mbps Bar` instead of the old `NCB_PoC` capture. On 2026-10-01, all five red arrows were moved to the positions marked by the user's blue arrows; the image is clipped before the arrow overlay so arrows aimed at top-row controls can extend above the screenshot without being cut off.
- Settings are shared with the Safari extension through `group.com.Hitoshi.LiveMbpsBar`.
- The Version 1.0.0 app icon is the final user-attached `/Users/hitoshi0002/6_NetConditionBar2/icon/NCB2_icon.004.png` supplied on 2026-10-02 (three green signal arcs, rounded outlined top bar, and rounded outlined dark-gray lower panel with the final heavier outline). The 1024×1024 non-alpha PNG is copied byte-for-byte into the AppIcon and activation-row assets. Safari extension icons at 48, 96, 128, and 512 pixels are resized from the same source.

### Safari extension

- Runs in the top frame of ordinary HTTP and HTTPS pages at `document_start`.
- Requests a sample 100 ms after the preceding response. The background script reuses concurrent/repeated native requests inside 80 ms. A native request is released after 1.5 seconds and a content-to-background request after 2.0 seconds, so an unresolved Safari extension message cannot permanently stop sampling.
- The native handler uses `NWPathMonitor` for connected/disconnected state, then sums raw received-byte deltas from `IFF_UP` `en0` and `pdp_ip*` physical interfaces only. It no longer also requires `IFF_RUNNING`, because that transient flag could leave the display at `-Mbps` after connectivity returned. VPN virtual interfaces are excluded, avoiding double counting. Physical-interface VPN overhead can remain in the value as agreed.
- The app and extension do not generate test traffic, save history, log samples, smooth values, interpolate values, or remove outliers.
- The display loop uses a 250 ms base period with ±1/3 Voss–McCartney 1/f variation. The user cannot change it.
- The bar renders 3 screen points thick at the top-left and is capped at 100% width. The numeric value remains uncapped and uses one decimal place.
- In landscape only, the speed label starts at least 52 CSS px from the left edge (or farther when the safe-area inset is larger), keeping it clear of the rounded screen corner.
- The overlay has been restored to its original static CSS sizing because avoiding Safari's upper-inset color extension takes priority over correcting the tiny display on legacy desktop-layout pages. The fixed host is `32px` high at `top: 0`, the fixed colored bar is `3px` high at `top: 0`, and the fixed label starts at `top: 3px` with a `13px/18px` font. There is no Visual Viewport scale calculation, inverse compensation, dynamic geometry refresh, scroll-coordinate synchronization, or 1 point top gap. Consequently, pages without a mobile viewport meta tag can again render the overlay smaller, as they did before the legacy-page workaround. The website's viewport and layout remain untouched.
- Valid zero traffic displays `0.0 Mbps` with a zero-width bar.
- First sample, interface-set changes, or rebaselining display `— Mbps` and hide the bar. After that single rebaseline, recovery mode calculates from interfaces that exist in both consecutive reads; persistent `pdp_ip*` membership changes or delivery intervals over 1 second therefore cannot force every sample back to `baseline`.
- An absent active physical interface displays `-Mbps` and hides the bar.
- Any per-interface counter decrease displays `-Mbps`, does not calculate wraparound, and rebases from the current counters.
- A generic acquisition failure preserves the last displayed valid value for that value's selected render interval plus 0.5 seconds. It then displays `— Mbps`; cached duplicates do not extend the deadline.
- `Show speed` OFF hides the label while preserving bar behavior.
- Fullscreen API, Safari fullscreen video, direct image documents, and large site image viewers detected through fullscreen/modal/media geometry hide both bar and label.

## Implementation choices made at the start of coding

These details were not numerically fixed in the specification and remain easy to change:

- The first successful read after a gap over 1.0 second discards continuity and establishes a baseline. If Safari continues delivering every request more than 1.0 second apart, recovery mode accepts the following intervals so the display can return to a numeric value instead of remaining at `— Mbps`. Normal short cadence exits recovery mode.
- Each native extension process supplies a UUID with its sample sequence. This prevents a relaunched native process whose numeric sample IDs restart at 1 from colliding with IDs already rendered by the content script.
- The 12 palette colors use the hex constants in `BarColorChoice.choices`; the initial green is `#58DE2F`.
- Physical interfaces require `IFF_UP`; `IFF_RUNNING` is deliberately ignored so the sampler can recover after a temporary disconnect.
- Site-specific image viewer detection is heuristic. It requires a nearly full-viewport fixed/absolute dialog/viewer containing large visible media, so ordinary inline images remain eligible for the bar.

## Verification completed

- `plutil -lint` passed for the project file, both Info plists, and both entitlements files.
- JSON validation passed for the manifest and asset catalog metadata files, including the activation-page icon asset.
- JavaScriptCore parsed both `background.js` and `content.js` successfully.
- Xcode recognized the app and extension targets and the shared `LiveMbpsBar` scheme.
- Simulator Debug build: succeeded.
- Generic iPhoneOS Debug build with signing disabled: succeeded.
- The 2026-09-30 feedback revision builds successfully for both the iOS Simulator and generic iPhoneOS device target with Xcode 27.0.
- Built app contains compiled AppIcon output, `Assets.car`, the embedded `.appex`, `background.js`, `content.js`, and `manifest.json`.
- Built Info plists contain iOS 18.0, the formal bundle IDs, the Safari Web Extension point, and iPhone-only device family.
- iPhone 17 simulator install/launch succeeded and visual inspection matched the revised p.5 layout and fixed 50%-width 10.0/20.0 preview.
- Original simulator screenshot: `evidence/top-screen-iphone17-simulator.png`.
- Revised simulator screenshot: `evidence/2026-09-30-revised-top-simulator.png`; visual inspection confirmed the two-line description, iPhone/Safari preview, black `apple.com`, fixed 10.0 Mbps overlay, and settings layout.
- The three user-annotated acceptance images are preserved as `evidence/2026-09-30-user-debug-001.png` through `003.png`.
- Earlier replacement icons are preserved as `evidence/2026-09-30-replacement-app-icon.png`, `evidence/2026-09-30-replacement-app-icon-v2.png`, and `evidence/2026-10-02-final-app-icon-v3.png`. The final Version 1.0.0 icon is preserved as `evidence/2026-10-02-final-app-icon-v4.png`; its SHA-256 (`5d9cfebeeddf0fa82059d5c7a7f2956e8b2a3c985188ae24cc827536f94ab446`) matches both the AppIcon and activation-row assets exactly.
- The second feedback images are preserved as `evidence/2026-09-30-user-debug-round2-001.png` and `evidence/2026-09-30-user-debug-round2-002.png`.
- Second-feedback simulator screenshots are `evidence/2026-09-30-round2-top-simulator.png` and `evidence/2026-09-30-round2-activation-simulator.png`. Visual inspection confirmed the blank preview address, removed `Settings` heading, compacted cards, aligned arrows, current icon, and `Live Mbps Bar` extension name.
- After restoring normal Top-screen startup, both the iOS Simulator and generic iPhoneOS Debug builds succeeded again. The temporary direct-to-activation verification route is not present in the final source.
- The device screenshot showing the stalled `— Mbps` state is preserved as `evidence/2026-09-30-device-stuck-dash-mbps.png`.
- Recovery-state assertions passed for persistent long intervals, changing `pdp_ip*` membership, Wi-Fi/cellular carrier replacement, and counter reset. The background watchdog test confirmed that a timed-out native request releases the shared in-flight promise and permits the next request.
- JavaScriptCore syntax validation passed for the revised background and content scripts. The revised recovery code then built successfully for both the iOS Simulator and generic iPhoneOS targets.
- 2026-10-01: reviewed the missing Detail-to-Top swipe. Detail hides the navigation bar and previously had no explicit swipe handler. Added `SwipeBackModifier` to both Detail and the secondary destination (now Information). Simulator and generic iPhoneOS builds succeeded with signing disabled. The Simulator GUI could not be accessed through the available computer-use tool, so actual horizontal swipe, vertical-scroll preservation, and back-button behavior still need physical-device verification. The user's navigation diagram is saved as `evidence/2026-10-01-user-swipe-back-navigation.png`.
- 2026-10-01: measured the five blue-arrow centers in the user's annotated activation screenshot and updated the corresponding relative positions for Extensions, the extension enable row, both permission switches, and All Websites. Verified the upper and lower sections visually in an iPhone 17 Pro simulator using temporary direct-to-Detail/top-and-bottom startup states, then removed those temporary states. The final app again starts on Top. The user reference and simulator evidence are saved as `evidence/2026-10-01-user-activation-arrow-positions.png`, `evidence/2026-10-01-activation-arrows-top-simulator.png`, and `evidence/2026-10-01-activation-arrows-bottom-simulator.png`. Final simulator and generic iPhoneOS builds succeeded with signing disabled.
- 2026-10-01: replaced the Top-screen gear with an information-circle button and replaced the Settings placeholder with an Article Shelf-style `Information` accordion. The five requested sections are present and expandable. Simulator visual verification confirmed the revised Top button and the five-row Information layout. The user reference and simulator evidence are saved as `evidence/2026-10-01-user-information-accordion.png`, `evidence/2026-10-01-information-button-simulator.png`, and `evidence/2026-10-01-information-accordion-simulator.png`.
- 2026-10-01: added the supplied `What’s Live Mbps Bar` and `Support` copy. The Support website opens `https://sonocam.app/`, and the email address opens a `mailto:` URL. Both link labels are blue as requested.
- 2026-10-01: added the supplied `Privacy Policy`, `Disclaimer`, and `Version` copy, completing all five Information accordion sections.
- 2026-10-02: diagnosed a tiny overlay on `http://warbirds.jp/truth/`, whose legacy HTML has no viewport meta tag and is rendered in Safari's wide default layout viewport. Added overlay-only inverse viewport-scale compensation and viewport/orientation refresh handling; the site document and its viewport remain untouched.
- 2026-10-02: JavaScriptCore syntax validation passed for the viewport-compensation revision. Calculation checks covered responsive portrait/landscape pages, a 980 CSS px legacy viewport in both orientations, and 2× pinch zoom while preserving a rendered 13 pt label and 3 pt bar. Simulator and generic iPhoneOS Debug builds both succeeded with signing disabled, and their packaged `content.js` files match the source byte-for-byte.
- 2026-10-02 physical-device result: the label is now correctly sized on legacy wide-layout pages. On `fast.com`, iOS Safari filled the status/safe-area inset with the selected bar color when the fixed bar touched the visual viewport's top edge; the 3 pt bar itself was not laid out at the full inset height. User evidence: `evidence/2026-10-02-responsive-page-expanded-bar.png`. A document-absolute Visual Viewport synchronization approach was tested as a workaround, but physical-device tests showed that the overlay did not follow Safari page scrolling, so the approach was abandoned.
- 2026-10-02 top-address-bar follow-up: while Safari's top URL bar expanded/collapsed during scrolling, the numeric label could remain partly above the unobscured page area. User evidence: `evidence/2026-10-02-top-address-bar-clipped-label.png`. Both absolute-position variants (`pageTop/pageLeft` and scroll-plus-offset), followed by a native-fixed host with a 1 point transparent gap, failed to follow physical-device scrolling reliably. At the user's request, the implementation was rolled back exactly to the earlier known stage: host, bar, and label all use Safari-native `position: fixed; top: 0`; all JavaScript scroll-coordinate synchronization and the 1 point gap were removed; legacy-page inverse scale compensation was retained. JavaScriptCore syntax validation and simulator/device unsigned Debug builds passed, and both packaged `content.js` files match the source. Expected device behavior at this stage is restored scroll following, with the previously observed top-address-bar label clipping and possible `fast.com` status-area tint still unresolved.
- 2026-10-02 follow-up after rollback: physical testing confirmed that scroll following returned, but the status-area color tint also returned. The requested 1 point website line was therefore added without changing the fixed positioning model: the fixed host remains at `top: 0`, the fixed bar moves to screen point 1, and the fixed label moves to screen point 4. Unlike the earlier failed 1 point experiment, the children remain `position: fixed` rather than becoming absolute inside the host. Scale calculations preserve a rendered 1 point gap and 3 point bar on responsive, legacy 980 px, and 2× pinch-zoom viewports. JavaScriptCore syntax validation and both unsigned Debug builds passed.
- 2026-10-02 one-point-gap device result: the white website line is visibly present above the colored bar, but Safari still fills the status/address-bar inset with the bar color. `fast.com` itself declares a white `theme-color`, so the colored inset is not supplied by the site. This matches WebKit's Safari 26 scroll-edge behavior: a viewport-constrained fixed/sticky element near an obscured edge can trigger a solid color extension into that inset. A 1 point separation therefore does not opt the overlay out of Safari's heuristic.
- 2026-10-02 priority rollback: at the user's direction, avoiding Safari's upper-inset color fill takes priority over enlarging the overlay on old pages. The complete legacy-page sizing workaround was removed: oriented-screen/Visual-Viewport scale detection, inverse scaling of all dimensions, geometry refresh scheduling, and the subsequent 1 point gap are gone. The overlay is back to the original static fixed CSS dimensions (`bar top 0 / height 3px`, `label top 3px`). Old pages without a viewport meta tag are expected to show the small overlay again. JavaScriptCore syntax validation and both simulator and generic-device unsigned Debug builds passed.
- 2026-10-02 edge-to-edge observation: with Safari's address bar at the bottom and collapsed, some pages are painted into the upper status-bar inset while the native fixed overlay remains anchored to Safari's CSS viewport boundary, making the Mbps label appear to float below the physical screen edge. This is primarily Safari 26's edge-to-edge/obscured-inset behavior; WebKit also has known iOS 26 inconsistencies around fixed elements and Visual Viewport offsets. No source change was made for this observation because prior manual Visual Viewport synchronization broke physical-device scroll following. User evidence: `evidence/2026-10-02-edge-to-edge-floating-label.png`.
- 2026-10-02 final Version 1.0.0 icon: replaced the AppIcon, activation-row icon, and all Safari extension icon sizes with `NCB2_icon.004.png`, the user's final attached design. The 1024px assets match the source byte-for-byte; extension sizes are 48, 96, 128, and 512px. Asset compilation, simulator Debug build, and generic-device unsigned Debug build all succeeded. The Version 1.0.0 checksum baseline was regenerated afterward.

The Xcode metadata extractor emits its normal warning that there is no AppIntents framework dependency. The app defines no App Intents, so this is not a product error.

## Remaining physical-device acceptance checks

The code is ready for device testing. These checks require signing/provisioning and representative real-world environments:

1. Enable the Safari extension and confirm the app-group settings propagate without reloading a page.
2. Recheck Wi-Fi, cellular, Wi-Fi-to-cellular switching, airplane mode, and recovery from `-Mbps`/`— Mbps` after the adaptive continuity and request-watchdog fixes.
3. Confirm representative VPN apps show the physical-side device total without adding a tunnel interface.
4. Confirm direct image URLs, Safari video fullscreen, and several site-specific image viewers hide the overlay and restore it correctly afterward.
5. Measure battery/CPU and agree the final D7 acceptance limits.
6. Check the extension across iOS 18, 19, 20, and current iOS where test devices are available.
7. Verify Detail and Information return to Top on a right swipe, and Detail vertical scrolling and its back button still work. Try starting the swipe on a screenshot and on the page background.
8. Confirm on a physical device that the complete removal of the legacy-page sizing workaround restores the earlier behavior without Safari upper-inset color fill and preserves scroll following. The small overlay on old pages is now an accepted tradeoff. Safari 26 can still paint page content into an obscured top inset and make the fixed label appear to float; top-address-bar label clipping also remains a separate platform-dependent limitation.

## Fast restart

Version 1.0.0 is fixed. Open `/Users/hitoshi0002/Documents/Codex/LiveMbpsBar/RELEASE_1.0.0.md` first and use `RELEASE_1.0.0.sha256` to detect any later source drift. The complete legacy-page sizing workaround and its 1 point-gap follow-up have been removed. The overlay uses its original static fixed CSS sizing: bar `top: 0 / height: 3px`, label `top: 3px`, with no viewport-scale or scroll-coordinate calculations. The small overlay on legacy pages and Safari 26's edge-to-edge fixed-label appearance are accepted Version 1.0.0 behaviors. Treat any subsequent product change as post-1.0.0 work.
