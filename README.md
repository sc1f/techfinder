# TechFinder

A minimal iPhone viewfinder for technical-camera photographers. Choose a lens and a back or film format, then compose through the iPhone camera with a frame that matches that setup's field of view and aspect ratio.

**Flow:** open → tap a lens (or change format) → frame the shot.

## Features (MVP)

- **Live framing.** The phone camera zooms so the taking frame fills about 85% of the view, and the scene around it is darkened. Pinch to show more or less of the surroundings; double-tap to reset.
- **Lens library.** Add, edit and delete lenses (focal length plus optional name). The list is sorted wide to long, and the angles of view shown are for the current format.
- **Formats.** Built-in presets for digital backs (Phase One IQ, Hasselblad CFV, GFX, Leica S, full frame), medium format film (6×4.5 to 6×17) and large format film (4×5, 5×7, 8×10), plus custom formats.
- **Readout.** Long × short angle of view and the full-frame-equivalent focal length. The frame turns orange when the setup is wider than the iPhone's ultra-wide can see.
- **Orientation.** The frame's long side runs along the phone's long side: hold the phone in landscape for a landscape frame. The interface stays portrait and the icons rotate, like the Camera app.
- **Liquid Glass.** Controls use `glassEffect` / `GlassEffectContainer` when built with the iOS 26+ SDK (Xcode 26+). Older SDKs fall back to a blurred material (see `TechFinder/Support/Glass.swift`).
- **Simulator.** The Simulator has no camera, so the app shows a synthetic scene with lines every 10°. Use it to check that the frame edges land at the lens's angle of view.

## How framing works

The app uses the multi-camera virtual device (ultra-wide + wide + tele), which at zoom 1 sees the ultra-wide field. It reads the horizontal field of view the camera reports (corrected for lens distortion) and its image aspect ratio. For a rectilinear lens, image size is proportional to tan(angle/2), so the frame's share of the phone image is the ratio (format side / 2f) ÷ (tan(phone half-angle) / zoom). All of this lives in `Packages/TechFinderCore/Sources/TechFinderCore/Framing.swift` and is unit tested.

## Project layout

```
project.yml                  XcodeGen spec (run `xcodegen generate` after editing)
TechFinder.xcodeproj         generated project
TechFinder/                  iOS app (SwiftUI + AVFoundation)
  App/ Camera/ Views/ Support/ Resources/
Packages/TechFinderCore/     models, format catalog, framing math, persistence, tests
```

## Build & run

- Open `TechFinder.xcodeproj`, choose the **TechFinder** scheme, and run on a Simulator or an iPhone.
- To run on an iPhone, set your team under *Signing & Capabilities* (or `DEVELOPMENT_TEAM` in `project.yml`). If `com.scif.TechFinder` is already taken, change the bundle ID.
- Run the tests with ⌘U, or `xcodebuild test -scheme TechFinder -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.
- Check the core logic without Xcode: `cd Packages/TechFinderCore && swift run CoreCheck`.

Currently built with Xcode 16.2 (iOS 18 SDK, material fallback). Building with Xcode 26 or later turns on Liquid Glass with no code changes; that needs macOS 15.6 or later.

## Liquid Glass builds with GitHub Actions

`.github/workflows/ios.yml` builds with the latest Xcode on a macOS 26 runner, so Liquid Glass is compiled in even though your Mac stays on an older macOS.

- **Every push and pull request:** builds and runs the tests on an iPhone Simulator.
- **TestFlight:** runs from *Actions › iOS › Run workflow*, or when you push a tag such as `v0.1.0`. It archives, signs, and uploads to TestFlight. The build number is the workflow run number.

One-time setup for TestFlight (requires the paid Apple Developer Program):

1. In [App Store Connect](https://appstoreconnect.apple.com) › Apps, create a new iOS app with bundle ID `com.scif.TechFinder`. Register the ID first under Certificates, IDs & Profiles › Identifiers if it isn't listed. App Store names must be unique, so choose another name if "TechFinder" is taken; the name on the home screen stays TechFinder.
2. In App Store Connect › Users and Access › Integrations › App Store Connect API, create a **Team** key with the **Admin** role. Download the `.p8` file, which you can only download once. Note the Key ID and Issuer ID.
3. In the GitHub repo › Settings › Secrets and variables › Actions, add these secrets:
   - `APPLE_TEAM_ID`: from developer.apple.com › Membership
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: paste the entire `.p8` file, including the BEGIN/END lines
4. Run the workflow. When processing finishes, install the build from the TestFlight app on your iPhone. You'll see Liquid Glass on iOS 26 or later.

## Later

Rise/fall and shift simulation, image-circle limits, saved scouting photos, and per-device field-of-view calibration.
