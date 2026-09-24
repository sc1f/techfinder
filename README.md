# TechFinder

A minimal iPhone viewfinder for technical-camera photographers. Choose a lens and a back or film format, then compose through the iPhone camera with a frame that matches that setup's field of view and aspect ratio.

**Flow:** open → tap a lens (or change format) → frame the shot.

## Features (MVP)

- **Live framing.** The phone camera zooms so the taking frame fills about 85% of the view, and the scene around it is darkened. Pinch to show more or less of the surroundings. Tap the image to focus and meter there. An optional rule-of-thirds grid sits inside the frame.
- **Lens library.** Add, edit and delete lenses (focal length plus optional name). The list is sorted wide to long, and the angles of view shown are for the current format.
- **Formats.** Digital backs are grouped by sensor size with their models listed (53.4 × 40, 53.7 × 40.4, 44 × 33, 45 × 30, 36 × 24). Film covers medium format (6×4.5 to 6×17) and large format (4×5, 5×7, 8×10). You can add custom formats.
- **Light meter.**
  - The top bar shows ISO, aperture and shutter. Tap an arrow or swipe along a value to change it. Right raises the value (higher ISO, higher f-number, faster shutter); left lowers it. Steps are full stops by default, or ⅓ stop (Settings).
  - ISO is always set by hand, and so is either the aperture or the shutter (lock icon). The meter gives the other (A). Tap the metered value, or change it, to set it by hand instead.
- **Spot meter.**
  - The meter reads a 3° spot, drawn as a circle, from the camera's video. It converts the spot's brightness to EV at ISO 100, so a mid-grey spot reads correct.
  - The spot sits at the centre cross (the moved frame's centre with movements on). Tap to move it, and tap it again to return to the centre.
  - Dragging up or down after a tap adds exposure compensation to both the preview and the recommendation.
  - A metered value turns orange if most of the spot is clipped white.
- **Controls.**
  - Under the meter are the tools: Grid, Reset Frame Size and Settings. Settings sets the ISO, aperture and shutter limits of your equipment; values outside them turn orange.
  - At the bottom, the lens and format pills sit above the lens selector. Tap either to change it.
  - The lens selector is a glass pill that hugs your lenses. Tap a lens, or drag across it: a clear glass lens lifts, follows your finger, magnifies the numbers beneath it and selects as it passes. The numbers turn in place with the phone without the pill changing size. With more lenses than fit, it becomes a sliding row like the Camera app's mode switcher.
  - Tap the image to focus and meter at that point, then drag up or down to brighten or darken. Tap elsewhere to move the point, or tap the square to return to automatic. The square hides after 3 seconds.
- **Image circle and movements.**
  - Give each lens its manufacturer image circle: one or two figures, such as 90 mm at f/11. The circle at the metered aperture is interpolated in stops, or estimated conservatively (marked *) when wider than any figure.
  - Turn on Movements, choose Rise or Shift, and move only that axis: with the arrows, by swiping the value, or by dragging the image. Steps are 0.5 mm.
  - The result view pans and zooms to the moved frame as the photo would look. Overview shows the whole image circle, the unmoved frame (dashed) and the moved frame.
  - Movements stop at the image circle and at the camera's mechanical limits (Settings). The readout shows the millimetres left to the circle's edge, turning orange when close and red if a later aperture change puts a corner outside.
- **Landscape.** Hold the phone sideways and the meter and tools move to the viewer's top edge, and the lens and format pills to the bottom edge. The lens labels turn, and sheets open as rotated glass cards.
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

- **Every push and pull request:** builds and runs the unit tests and the UI tests (which toggle the grid, use the meter and open the sheets) on an iPhone Simulator. It then launches the app in four states (portrait, the Lenses sheet, and both landscape holds) and fails if the app is stuck at full CPU. Screenshots of each state are saved as the `screenshots` artifact.
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

Tilt and swing, saved scouting photos, a pan-and-stitch mode for setups wider than the iPhone's ultra-wide, and per-device field-of-view calibration.
