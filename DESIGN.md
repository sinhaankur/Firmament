# NightSky — Design & Spec

> Point your iPhone at the real sky and *understand* it. Then capture it.

NightSky is a native iOS app for iPhone 17 Pro (and other recent iPhones) that
fuses the phone's sensors — camera, LiDAR, GPS, compass, and motion — with real
astronomical data to do two things well:

1. **Understand the sky you're looking at** — a live AR overlay that identifies
   stars, planets, constellations, the Sun/Moon, and satellite/ISS passes,
   anchored to the true direction each object is in *right now* from *where you
   are standing*.
2. **Capture the night sky** — a tripod-aware capture mode that pushes the
   camera to its physical limit (long exposure + RAW frame-stacking + system
   night mode), with a clean one-shutter UX, and annotates each shot with what
   was in frame.

It is the mobile, real-sky companion to the web **Universe Engine** and
**Satellite Engine** (sinhaankur.com). Same north star: *restore access to the
sky, faithfully and understandably — reverence over spectacle, real over
invented.*

---

## 1. Principles (inherited from the Universe Engine)

- **Truth.** Every position is computed from real data (Apple's astronomy-capable
  frameworks + bundled catalogs). Where a value is inferred or approximate, it is
  labeled — never presented as fact.
- **On-device & private.** No account. No server round-trip for the core
  experience. Location and photos never leave the phone.
- **Seeing is believing.** Favor a clear *visual* read of the sky over stat
  tables. The overlay should feel like the sky is annotating itself.
- **Reverence over spectacle.** Calm, dark, legible UI. The sky is the subject;
  the chrome gets out of the way.
- **Mobile-first, one-handed.** Designed and verified at the phone in the dark,
  cold-fingered, at arm's length. Big touch targets. No hover affordances.

---

## 2. Feature set

### 2.1 Live AR sky identifier (core)
- Full-screen camera feed with a celestial overlay.
- Point the phone anywhere; labels for the Sun, Moon (with phase), the naked-eye
  planets, ~200 brightest stars, and the classic constellations appear anchored
  to their true **alt/az** direction.
- Tap a label → an info card (name, type, magnitude, alt/az, rise/set, distance,
  a one-line "what am I looking at").
- A "below horizon" dimming so you can tell what's actually up vs. under your feet.
- Compass calibration nudge when heading confidence is low.

### 2.2 LiDAR foreground anchor
- Use the LiDAR scanner to detect the **real horizon and near occluders** (trees,
  buildings, the person next to you) so labels for objects behind them can dim or
  hide — the sky is correctly *occluded* by the world in front of you.
- "What's above this exact spot" spatial capture: mesh the immediate surroundings
  and stamp the true sky over it.
- Note: LiDAR ranges to ~5 m and does **not** measure the sky itself — it anchors
  the *foreground*, while the sky comes from ephemeris + device attitude.

### 2.3 Satellite / ISS spotter
- Real-time AR arrows guiding you to the patch of sky where a visible pass is
  happening now (ISS first; extensible to bright satellites via TLE + SGP4).
- Countdown to the next visible pass from your location, with brightness and
  path direction.
- Consistent with the web Satellite Engine's model (SGP4 from TLEs); TLEs bundled
  and refreshable.

### 2.4 Astrophotography assist
- Overlay where the **Milky Way core**, planets, and the Moon *will* be — best
  shooting angle and time, from compass + ephemeris.
- Golden/blue-hour and astronomical-twilight timings for tonight.
- Framing guides + "point here" for a target object.

### 2.5 Night Capture mode (tripod)
- **Stability detection** via CoreMotion — when the phone is still (on a tripod
  or braced), Night Capture unlocks its long-exposure ladder.
- **Max-limit capture**, all of it:
  - **Long single exposure** — manual `AVCaptureDevice` exposure at max ISO and
    the longest supported `exposureDuration` (hardware-capped, typically ≤1 s).
  - **RAW frame-stacking** — capture many frames, align, and stack into one
    brighter, lower-noise image (the way to beat the hardware exposure cap).
  - **System Night Mode assist** — lean on the built-in long capture where the
    system offers it.
- **Snapchat-clean UX** — one big shutter, live preview, tap-and-hold for longer
  stacks, instant review, save/share. No settings maze; the app picks the ceiling.
- **Annotated captures** — each saved photo is tagged with the objects that were
  in frame (from the AR engine at capture time) + location + timestamp.

---

## 3. Architecture

Native **SwiftUI** app, Swift 6, targeting iOS 26 (Xcode 26). Modules:

```
NightSkyApp            App entry, root navigation, mode switch (Explore | Spot | Capture)
Sensors/
  LocationService     CoreLocation — coordinate + true heading
  MotionService       CoreMotion — device attitude (roll/pitch/yaw), stability
SkyEngine/
  SkyMath             Julian date, sidereal time, RA/Dec → alt/az, refraction
  SolarSystem         Sun/Moon/planets low-precision ephemeris (VSOP-lite / Meeus)
  StarCatalog         Bundled bright-star table (name, RA/Dec, mag)
  Constellations      Star-index line lists
  Satellites          TLE store + SGP4 → look angle (ISS first)
AR/
  SkyOverlayView      Camera feed + projected celestial labels (attitude-driven)
  LiDARForeground     ARKit scene depth / mesh → foreground occlusion mask
Capture/
  StabilityDetector   Tripod/steady detection from MotionService
  NightCapture        AVFoundation: long exposure + RAW stacking + night-mode assist
  FrameStacker        Align + accumulate frames (Accelerate/Metal)
  CaptureAnnotator    Tag saved photo with in-frame objects + geo/time
UI/
  ExploreScreen, SpotScreen, CaptureScreen, InfoCard, CalibrationNudge
```

### Data flow (Explore mode)
```
GPS + clock ──► SkyMath (LST) ─┐
                               ├─► object alt/az ──► project through device
ephemeris/catalog ─────────────┘                     attitude ──► screen label
                                                       ▲
CoreMotion attitude ───────────────────────────────────┘
LiDAR depth ──► occlusion mask ──► hide labels behind foreground
```

### Data flow (Capture mode)
```
MotionService ─► StabilityDetector ─► "steady" ─► NightCapture unlocks ladder
shutter ─► [long exposure] + [N RAW frames] ─► FrameStacker ─► image
        ─► CaptureAnnotator (in-frame objects, geo, time) ─► Photos
```

### Why "Apple's built-in frameworks" for data
The core positions ride on CoreLocation + CoreMotion for the observer frame, and
standard Meeus/VSOP-lite math (small, exact enough for naked-eye pointing) for the
bodies — no external data service needed for the core loop. Star/constellation/TLE
tables are bundled static assets, refreshable. This keeps the app fully **offline
and on-device**, matching the web engine's fidelity approach without shipping its
133 MB satrec heap.

---

## 4. Screen IA

Three modes on a single bottom control, sky-first (chrome minimal, dark):

- **Explore** — live AR identify. Tap object → InfoCard. This is the default.
- **Spot** — satellite/ISS pass finder + guiding arrows + next-pass countdown.
- **Capture** — Night Capture. Big shutter; stability chip; press-hold = longer
  stack; review sheet with annotation.

Global: a small calibration nudge, a location/time chip (tap to time-travel like
the web engine's timeline), and a settings sheet (units, catalog refresh, privacy).

---

## 5. Device support & honesty

- **iPhone 17 Pro** is the reference device — LiDAR + Pro cameras + latest ISP.
- Non-Pro / older iPhones: everything works **except** LiDAR foreground occlusion,
  which degrades gracefully to a simple horizon line from device pitch.
- **Android** is a *separate* native app (ARCore + Camera2/CameraX + platform
  depth). This repo holds the shared spec and an `android/` slot marked
  **planned** — we don't pretend one binary ships both. Cross-platform is a
  roadmap commitment, not a shipped claim.

---

## 6. Distribution

- **iOS (others):** Apple does not allow raw `.ipa` sideload links for the public.
  Distribution is **TestFlight** (beta) → **App Store** (GA). The install page
  exposes a TestFlight CTA (placeholder until the build is uploaded).
- **This repo:** open source; anyone with a Mac + Xcode + free Apple ID can build
  and run it on their own device.
- **Landing/install page:** `docs/` served via GitHub Pages — iOS TestFlight CTA,
  Android "planned" slot, feature tour, screenshots, privacy statement.

---

## 7. Roadmap (phased)

**Phase 0 — Skeleton (this session):** buildable Xcode app; camera preview;
LocationService + MotionService live; SkyMath + Sun/Moon/planets computing real
alt/az; a working overlay label for at least the Sun/Moon/one planet; Capture mode
stub with stability detection + a basic long-exposure/stack path; repo + README +
install page.

**Phase 1 — Explore complete:** full bright-star + constellation overlay, InfoCards,
LiDAR foreground occlusion, calibration UX, time-travel chip.

**Phase 2 — Spot:** ISS + bright-satellite passes, guiding arrows, countdowns.

**Phase 3 — Capture pro:** robust frame alignment/stacking on Metal, star-trails
mode, RAW pipeline, annotated capture gallery.

**Phase 4 — Distribution:** TestFlight, App Store, portfolio cross-link; begin
Android port against the shared spec.

---

## 8. Relationship to the web engines

NightSky is the *field instrument*; the web Universe/Satellite Engine is the
*planetarium/observatory*. Same data philosophy, same reverence, same voice. A
capture taken in NightSky (with its in-frame annotation) is exactly the kind of
"real sky, understood" artifact the whole project exists to produce.
