# TechFinder

A minimal iPhone viewfinder for technical-camera photographers. Choose a lens and a back or film format, then compose through the iPhone camera with a frame that matches that setup's field of view and aspect ratio.

**Flow:** open → tap a lens (or change format) → frame the shot.

## Features (MVP)

- **Live framing.** The phone camera zooms so the taking frame fills about 85% of the view, and the scene around it is darkened. Pinch to show more or less of the surroundings; a chip on the image shows the frame size (such as 1.3×) until you tap it to return to the standard size. The camera autofocuses at the centre. An optional rule-of-thirds grid sits inside the frame.
- **Lens library.** Add, edit and delete lenses (focal length plus optional name). Tap a lens to use it; its info button or a long press edits it. Deleting from the editor, and Settings' Reset to Defaults, ask first. Choosing a lens with a name shows the name over the image for a moment. The list is sorted wide to long, and the angles of view shown are for the current format.
- **Formats.** Digital backs are grouped by sensor size with their models listed (53.4 × 40, 53.7 × 40.4, 44 × 33, 45 × 30, 36 × 24). Film covers medium format (6×4.5 to 6×17) and large format (4×5, 5×7, 8×10). You can add custom formats.
- **Light meter.**
  - The meter row shows ISO, aperture and shutter. Tap an arrow or swipe along a value to change it. Right raises the value (higher ISO, higher f-number, faster shutter); left lowers it.
  - Steps are full stops by default, landing on the standard series (ISO 100, 200, 400…; f/5.6, 8, 11…; 1/125, 1/250…), or ⅓ stop in Settings. The limit pickers in Settings follow the same steps; switching to full stops moves each limit to its nearest whole stop (f/1.1 becomes f/1).
  - Tap ISO, aperture or shutter for a list of values within your limits (it holds still while open, even as the meter keeps reading): whole stops (1/30, 1/60, 1/125…; f/5.6, 8, 11…), or thirds with ⅓-stop steps. Picking the metered value sets it by hand.
  - ISO is always set by hand, and so is either the aperture or the shutter (lock icon). The meter gives the other (A). Pick the metered value from its list, or change it, to set it by hand instead.
- **Spot meter.**
  - The meter reads a 3° spot, drawn as a circle at the centre cross (the moved frame's centre with movements on). It converts the spot's brightness to EV at ISO 100 using the camera's exposure, so a mid-grey spot reads correct.
  - The ISO pill shows the live reading as EV at ISO 100. To calibrate, meter a grey card with a handheld spot meter and set any consistent difference in Settings › Calibration.
  - A metered value turns orange with a warning sign if most of the spot is clipped white; so does any value outside your limits.
  - The first time, a label names the spot circle.
- **Controls.**
  - All the controls sit below the camera image, within thumb reach, sharing out the space evenly. From the top down: the meter, the lens selector on its own (or the movement controls in its place, with Movements on), and a row of round buttons with labels.
  - The buttons, left to right: Settings, Frame (sensor or film format), Lenses (add, edit and choose lenses), Movements and Grid. Settings sets the ISO, aperture and shutter limits of your equipment; values outside them turn orange.
  - The controls never cover the camera image, which sits at the top and never moves or resizes. With Movements on, the movement controls take the lens selector's place (the Lenses button still opens the library), so nothing else shifts. On a short screen such as the iPhone SE, the image is a little smaller to leave the controls room.
  - Turning movements on or off, or choosing another lens or format, switches the camera straight to its new zoom (often another of the iPhone's cameras) under a brief blur, as the Camera app does when it changes lenses, instead of showing it zoom and hand over. Pinching still zooms smoothly.
  - The lens selector is the system segmented control. On iOS 26, pressing or dragging lifts a clear glass lens that magnifies the lenses beneath it, as in the Photos app. The numbers turn with the phone without the control changing size. Its labels drop "mm" when that is what it takes to fit (up to about eight lenses); with more lenses than fit, it becomes a sliding row like the Camera app's mode switcher.
- **Image circle and movements.**
  - Give each lens its manufacturer image circle at one or more apertures (whole stops from f/2.8 to f/64), such as 80 mm at f/4 and 90 mm at f/11.
  - Movements use the figure quoted at the aperture closest (in stops) to the meter's, so only your real data sheet figures are used. On a tie the wider aperture's smaller circle wins. The readout shows the figure in use, such as "IC 90 f/11".
  - Turn on Movements, choose Rise or Shift, and move only that axis: with the arrows, by swiping the value, or by dragging the image. Steps are 0.5 mm. Tap the value for a menu to reset it, or both axes, to zero. Double-tapping the image also resets the current axis, with a few seconds to undo.
  - The result view pans and zooms to the moved frame as the photo would look. The dashed-circle button shows the overview, which shows the whole image circle, the unmoved frame (dashed) and the moved frame.
  - With an ultra-wide lens, the image circle or a moved frame can reach past what the iPhone camera sees, even at its widest. That area is hatched, with the camera's edge dashed, and "Wider than the iPhone can see" shows at the top of the image. The overview zooms out to show the whole image circle.
  - Movements stop at the image circle and at the camera's mechanical limits (Settings). The readout shows the millimetres left to the circle's edge, turning orange when close and red if a later aperture change puts a corner outside.
- **Landscape.** Hold the phone sideways and the controls stay where they are, with their icons and text turned to read upright. The meter pills stand upright to you, shutter, aperture and ISO from the top, with up raising a value and just the lock or A badge above each value; their lists open turned too. The lens labels turn smoothly with the phone, the movement controls run along the viewer's bottom edge, and lists open as rotated glass cards; anything you type into (a new lens, a custom format) opens as a portrait sheet so the keyboard reads the right way up.
- **Too wide.** When the setup is wider than the iPhone's ultra-wide can see, the frame turns orange and "Wider than the iPhone can see" shows at the top of the image.
- **Orientation.** The frame's long side runs along the phone's long side: hold the phone in landscape for a landscape frame. The interface stays portrait like the Camera app. Icons and lens labels rotate, even with Rotation Lock on.
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

- **Every push and pull request:** builds and runs the unit tests and the UI tests (which toggle the grid, use the meter, open the sheets and check that no control covers the camera image and that the lens selector works with 0 to 10 lenses) on an iPhone Simulator. It then launches the app in six states (portrait, the Lenses sheet, both landscape holds, and the two movement views) and fails if the app is stuck at full CPU; screenshots of each state are saved as the `screenshots` artifact. A parallel job runs `scripts/device-matrix.sh`, which runs the layout tests and takes screenshots on an iPhone SE, 13 mini, 16 Pro and 16 Pro Max (the `device-screenshots` artifact). Run the script locally the same way.
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
