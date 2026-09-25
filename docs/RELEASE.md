# Releasing TechFinder

## Before the first release (once)

1. **Join the Apple Developer Program** ($99 a year). The free Personal Team used by
   `scripts/install-liquid-glass.sh` can install on your own iPhone but can't publish to TestFlight or the
   App Store.
2. **Create the app in App Store Connect** (Apps › + › New App): platform iOS, name *TechFinder* (or
   another if taken), primary language English, bundle ID `com.scif.TechFinder` (register it under
   Certificates, Identifiers & Profiles first if it isn't listed), SKU `techfinder`.
3. **Add the repository secrets** that the TestFlight job in `.github/workflows/ios.yml` needs:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (an App Store Connect API key with the Admin
   role).

## Each release

1. Set `MARKETING_VERSION` in `project.yml` (1.0.0 for the first), run `xcodegen generate`, and commit.
2. Tag and push: `git tag v1.0.0 && git push origin v1.0.0`. CI tests, then uploads a build to TestFlight
   with the run number as the build number.
3. Try the build from TestFlight on your iPhone.
4. In App Store Connect, pick the build for the version, fill in the listing below (first time only), and
   submit for review.

## App Store listing

**Name:** TechFinder

**Subtitle** (30 characters max): Viewfinder for tech cameras

**Category:** Photo & Video (secondary: Utilities)

**Age rating:** 4+ (no objectionable content)

**Price:** your choice

**Promotional text:**
Frame, meter and plan movements for your technical camera, with the iPhone as your viewfinder.

**Description:**

TechFinder turns your iPhone into a viewfinder for technical and view cameras.

Choose your digital back or film format, add the lenses you carry, and see exactly what each lens will
frame, live through the iPhone camera.

FRAME
• An accurate frame for your lens and format, from wide digital backs to 8×10 film
• Custom formats for any back, holder or crop
• A rule-of-thirds grid, and pinch to see more or less around the frame

METER
• Average metering over the frame, or a 3° spot meter
• ISO, aperture and shutter in whole or third stops, with shutter or aperture priority
• Your equipment's limits, with an over- or underexposure warning when the light needs more

MOVEMENTS
• Plan rise, fall and shift within each lens's image circle, from the manufacturer's figures
• See the result, or the whole image circle with the unmoved frame
• Millimetres to the edge of the circle as you move

Works upright and sideways, with Liquid Glass controls. No account, no ads, no tracking: the camera image
never leaves your iPhone.

**Keywords** (100 characters max):
view camera,technical camera,large format,medium format,viewfinder,shift,rise,light meter,lens,film

**Support URL:** https://github.com/sc1f/techfinder/issues

**Privacy policy URL:** https://github.com/sc1f/techfinder/blob/main/PRIVACY.md

## App Privacy (App Store Connect › App Privacy)

Answer **Data Not Collected**. TechFinder has no accounts, analytics, advertising or network access; the
camera is used only for the live viewfinder and metering. The build's privacy manifest
(`TechFinder/Resources/PrivacyInfo.xcprivacy`) declares no tracking and no collected data, and gives the
reason for its one required-reason API (UserDefaults, for its own settings: CA92.1).

**Export compliance:** the app uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` is `NO` in
Info.plist), so no documentation is needed.

## Notes for App Review

> TechFinder is a viewfinder for technical cameras: it shows, through the iPhone camera, the frame a
> chosen lens and film or sensor format will capture. It needs the camera; no account or sign-in.
>
> To try it: allow camera access, then tap a lens (23, 32, 50, 70 mm) in the selector to change the
> frame. Frame chooses the format. Movements (the switch at the bottom right) shows rise and shift within
> the lens's image circle; the starter lenses have no image circle, so add one under Settings › Lenses ›
> (info) › Add Image Circle, for example 90 mm at f/11.

## Screenshots

App Store Connect needs iPhone screenshots at 6.9" (1320 × 2868, iPhone 16 Pro Max class); it scales them
for smaller iPhones. Take them on an iPhone, pointing at a real scene, or in the Simulator (which shows a
test scene) with the launch arguments in `.github/workflows/ios.yml`. Five that tell the story:

1. The viewfinder with a lens selected (frame and meter)
2. The lens selector with several lenses
3. Movements with a rise, showing millimetres to the edge
4. The image circle overview
5. Held sideways

## Checklist

- [x] App icon (1024 × 1024, no transparency)
- [x] Camera usage description
- [x] Privacy manifest
- [x] Privacy policy and support links (also in Settings › About)
- [x] Export compliance flag
- [x] iPhone only, portrait interface that turns its controls
- [x] First-launch welcome before the camera permission prompt
- [x] Handles camera access denied (a card links to Settings)
- [ ] Apple Developer Program membership
- [ ] App record in App Store Connect and CI secrets
- [ ] Screenshots
- [ ] Submit for review
