# TechFinder

A minimal iPhone viewfinder for technical-camera photographers. Choose a lens and a back or film format, then compose through the iPhone camera with a frame that matches that setup's field of view and aspect ratio.

**Flow:** open → tap a lens (or change format) → frame the shot.

## Features (MVP)

- **Live framing.** The phone camera zooms so the taking frame fills about 85% of the view, and the scene around it is darkened. Pinch to show more or less of the surroundings. Tap the image to focus and meter there. An optional rule-of-thirds grid sits inside the frame.
- **Lens library.** Add, edit and delete lenses (focal length plus optional name). The list is sorted wide to long, and the angles of view shown are for the current format.
- **Formats.** Digital backs are grouped by sensor size with their models listed (53.4 × 40, 53.7 × 40.4, 44 × 33, 45 × 30, 36 × 24). Film covers medium format (6×4.5 to 6×17) and large format (4×5, 5×7, 8×10). You can add custom formats.
- **Controls.**
  - The top bar has the menu (grid, reset frame size), the lens button centred on screen, and the format button to its right. Tap lens or format to change them.
  - The lens selector at the bottom is Apple's segmented control. On iOS 26 the selection lifts into a glass lens as you drag across it, as in the Photos app. When there are more lenses than fit, it becomes a sliding pill like the Camera app's mode switcher.
  - Tap the image to focus and meter at that point, then drag up or down to brighten or darken, like the Camera app's sun. Tap elsewhere to move the point, or tap the square to return to automatic.
  - Press and hold any control or lens for a tip.
- **Landscape.** Hold the phone sideways and the readout and menu move to the viewer's top edge. Lenses and Format open as rotated cards.
- **Readout.** The lens button shows the long × short angle of view and the full-frame-equivalent focal length. When the setup is wider than the iPhone's ultra-wide can see, the frame turns orange and the button adds a warning line.
- **Orientation.** The frame's long side runs along the phone's long side: hold the phone in landscape for a landscape frame. The interface stays portrait like the Camera app. Icons and lens labels rotate, even with Rotation Lock on, and in landscape the readout moves to the side edge that is currently up.
- **Liquid Glass.** Controls use `glassEffect` when built with the iOS 26+ SDK (Xcode 26+), on a plain black background. Older SDKs use solid dark controls (see `TechFinder/Support/Glass.swift`).
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

## CI & TestFlight

`.github/workflows/ios.yml` runs on a macOS 26 runner with the latest stable Xcode.

- **Every push and pull request:** builds and runs the unit tests and the UI tests (which open the menu and sheets) on an iPhone Simulator. It then launches the app in four states (portrait, the Lenses sheet, and both landscape holds) and fails if the app is stuck at full CPU. Screenshots of each state are saved as the `screenshots` artifact.
- **TestFlight:** runs from *Actions › iOS › Run workflow*, or when you push a tag such as `v0.1.0`. It archives, signs, and uploads to TestFlight. The build number is the workflow run number.

- **Unsigned iPhone build:** every push to `main` also saves an unsigned build of the app, made with the latest Xcode.

### Installing the Liquid Glass build with a free Apple ID

Your Mac doesn't need Xcode 26 for this. With the iPhone connected and unlocked, run:

```bash
scripts/install-liquid-glass.sh
```

The script downloads the latest unsigned build from CI and signs it with your Personal Team. If there's no provisioning profile for the phone yet, it asks Xcode to make one. Then it installs the app with `devicectl`. Free-team installs stop opening after 7 days; run the script again to refresh.

Requirements:

- The `gh` command-line tool, signed in to GitHub.
- Your Apple ID added in Xcode › Settings › Accounts.
- The phone set up for development once: trusted, Developer Mode on, and seen by Xcode.

If your phone runs a newer iOS than your Xcode supports, Xcode can't use it for development until it has the matching iOS developer disk image. You can take the image from a newer Xcode's `XcodeSystemResources.pkg` and install it with `sudo xcrun devicectl manage ddis update --source-dir <dir>`.

### TestFlight

One-time setup for TestFlight (requires the paid Apple Developer Program):

1. In [App Store Connect](https://appstoreconnect.apple.com) › Apps, create a new iOS app with bundle ID `com.scif.TechFinder`. Register the ID first under Certificates, IDs & Profiles › Identifiers if it isn't listed. App Store names must be unique, so choose another name if "TechFinder" is taken; the name on the home screen stays TechFinder.
2. In App Store Connect › Users and Access › Integrations › App Store Connect API, create a **Team** key with the **Admin** role. Download the `.p8` file, which you can only download once. Note the Key ID and Issuer ID.
3. In the GitHub repo › Settings › Secrets and variables › Actions, add these secrets:
   - `APPLE_TEAM_ID`: from developer.apple.com › Membership
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: paste the entire `.p8` file, including the BEGIN/END lines
4. Run the workflow. When processing finishes, install the build from the TestFlight app on your iPhone.

## Later

A light meter in the top bar, rise/fall and shift simulation, image-circle limits, saved scouting photos, a pan-and-stitch mode for setups wider than the iPhone's ultra-wide, and per-device field-of-view calibration.
