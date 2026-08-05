<div align="center">

# NightSky

**Point your iPhone at the real sky and understand it. Then capture it.**

A native iOS app that fuses the phone's camera, LiDAR, GPS, compass, and motion
sensors with real astronomical data — a live AR sky identifier and a tripod-aware
night-sky camera in one. The field companion to the web
[Universe Engine](https://www.sinhaankur.com/lab/celestial).

</div>

---

## What it does

- **Explore** — hold the phone up and stars, planets, the Sun/Moon (with phase),
  and constellations get labeled in real time, anchored to their true direction
  in *your* sky, from *your* location, *right now*. Tap any label for the facts.
- **Spot** *(roadmap)* — arrows guide you to where the ISS and bright satellites
  are passing overhead, with a live countdown to the next visible pass.
- **Capture** — set the phone on a tripod and NightSky detects it's steady, then
  pushes the camera to its limit: long exposure **+** RAW frame-stacking **+**
  system night-mode assist, behind one clean shutter. Each shot is annotated with
  what was in frame.

Everything runs **on-device and offline**. No account. Your location and photos
never leave the phone.

## How the sky is computed

Positions ride on Apple's built-in frameworks for the observer frame
(**CoreLocation** for place + true heading, **CoreMotion** for where the phone
points and whether it's steady) plus standard Meeus / JPL-approximate math for the
bodies:

- Sun — Meeus ch. 25 apparent geocentric position.
- Moon — abridged ELP series + illuminated-fraction phase.
- Planets — Keplerian elements with linear rates (JPL "approximate positions",
  valid 1800–2050), solved through Kepler's equation.
- Stars — a bundled bright-star catalog (J2000 RA/Dec + magnitude).

Accuracy is *naked-eye pointing* grade — the right tool for a phone in a field.
Where a value is inferred or approximate, the UI says so; nothing is presented as
more exact than it is. Same fidelity philosophy as the web engine: **real over
invented, reverence over spectacle.**

## Requirements

- **iPhone 17 Pro** is the reference device (LiDAR foreground occlusion + Pro
  cameras). Runs on any iPhone on iOS 17+; without LiDAR, foreground occlusion
  degrades gracefully to a horizon line.
- Xcode 26+, Swift 5+ (builds clean under the Swift 6 toolchain).

## Build & run on your own device

The Xcode project is generated from [`project.yml`](./project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so it stays diff-friendly.

```bash
brew install xcodegen        # one-time
git clone https://github.com/sinhaankur/NightSky.git
cd NightSky
xcodegen generate            # creates NightSky.xcodeproj
open NightSky.xcodeproj
```

Then in Xcode:

1. Select the **NightSky** target → **Signing & Capabilities**.
2. Pick your **Team** (a free Apple ID works for on-device testing).
3. Plug in your iPhone, select it as the run destination, and press **⌘R**.

The first launch will ask for camera, location, and motion permission — all three
are needed for the sky to line up and for capture to work.

## Install (no Mac needed)

Apple does not allow public `.ipa` downloads, so beta distribution is via
**TestFlight** and general availability via the **App Store**. The install page
holds the links:

➡️ **[Install page](https://sinhaankur.github.io/NightSky/)** — TestFlight (iOS,
coming) · Android (planned).

## Android & cross-platform

Android is a *separate* native app (ARCore + CameraX + platform depth), sharing
this repo's [`DESIGN.md`](./DESIGN.md) as the spec. It lives under
[`android/`](./android/) and is marked **planned** — we don't pretend one binary
ships both platforms. Cross-platform is a roadmap commitment, tracked honestly.

## Project layout

```
DESIGN.md            Full concept + architecture + roadmap
project.yml          XcodeGen project definition (source of truth)
Sources/
  App/               App entry + root view
  Sensors/           CoreLocation + CoreMotion services
  SkyEngine/         Pure astronomy: math, ephemeris, catalogs (no UI, offline)
  AR/                Camera preview + sky→screen projection
  Capture/           Night Capture pipeline (long exposure + stacking)
  UI/                SwiftUI screens (Explore / Spot / Capture, InfoCard)
Resources/           Info.plist, asset catalog
docs/                Install landing page (GitHub Pages)
android/             Planned native port (shares DESIGN.md)
```

## Status

Phase 0 (this milestone): the app builds and runs on-device — live camera sky,
real Sun/Moon/planet/star labels from your location and time, tap-to-inspect, and
a tripod-gated Night Capture path. Explore/Spot/Capture roadmap is in
[`DESIGN.md`](./DESIGN.md).

## License

MIT © Ankur Sinha. See [`LICENSE`](./LICENSE).

Astronomical algorithms after Jean Meeus, *Astronomical Algorithms*; planetary
elements from JPL's approximate-positions tables; bright-star positions from the
Yale Bright Star Catalogue / Hipparcos. NightSky's own code is © Ankur Sinha;
third-party data sources are credited here and in-code.
