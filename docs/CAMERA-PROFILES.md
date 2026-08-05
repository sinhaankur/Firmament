# Camera capability research — iPhone & Android

Field notes behind NightSky's capture strategy, gathered from Apple/Android docs,
developer forums, and open-source camera projects. The headline: **there is no
static "max exposure / max ISO per model" table** — limits live per capture
*format* and are wildly inconsistent, so NightSky **queries them at runtime** and
leans on **frame-stacking** as the one thing that works everywhere.

## iOS / AVFoundation

- Exposure & ISO ceilings live on **`AVCaptureDeviceFormat`**, not the model:
  read `activeFormat.maxExposureDuration`, `.maxISO`, `.minISO` at runtime.
  `device.activeMaxExposureDuration` is the AE-algorithm cap.
- ISO range **varies by format** on the same phone (e.g. different ranges for
  1080p vs full-res formats). Never assume one ceiling per model.
- Manual single exposure caps around **~1 s** on most iPhones via
  `setExposureModeCustom`. The **native Night Mode** reaches up to **30 s** on a
  tripod-stabilized Pro — but only at **12 MP** (Night Mode is disabled at
  48 MP), typically at **ISO 10,000–12,500**, saved as ProRAW.
- **Gotcha (documented):** you can't get **both** full 48 MP **and** exact
  honored custom ISO/exposure. `.speed` prioritization → 12 MP with honored
  manual values; `.balanced`/`.quality` → full res but manual ISO/exposure drift.
  → **NightSky reserves ProRAW/48 MP for the single hero frame, and uses fast
  processed frames for the stack** (where honored exposure matters more).
- When `exposureMode == .custom`, exposure duration and frame rate are coupled;
  a long duration lengthens `activeVideoMaxFrameDuration` automatically.

## Android / Camera2 & CameraX

- Per-device limits come from camera characteristics:
  `SENSOR_INFO_EXPOSURE_TIME_RANGE` (ns) and `SENSOR_INFO_SENSITIVITY_RANGE`.
  Require `REQUEST_AVAILABLE_CAPABILITIES` to include `MANUAL_SENSOR`.
- Manual controls via **Camera2Interop / Camera2CameraControl**: set
  `SENSOR_EXPOSURE_TIME`, `SENSOR_SENSITIVITY`, `LENS_FOCUS_DISTANCE`, with
  `CONTROL_AE_MODE = OFF` and AF off, or the values are ignored.
- **The values differ enormously per device and are often under-reported:**
  - **Samsung Galaxy:** stock app allows 15–30 s, but Camera2 exposes only
    **~0.1 s** to third-party apps (S10/S20 series). Requesting beyond the range
    sometimes works but is undefined (may clamp/stall the preview).
  - **Google Pixel/Nexus:** API returns ~1/5 s while the *real* full-res max is
    several × longer; Pixel's built-in astro mode sidesteps this by stacking
    (~16 × 15 s frames merged).
- **Conclusion:** single-exposure limits are unreliable on Android. The portable
  answer is **burst + stack** — exactly what Pixel astro mode and the best
  third-party apps (DeepSkyCamera, NightCap) do internally.

## Cross-platform strategy NightSky adopts

1. **Detect, don't assume.** Query the real per-format/per-device limits and
   build a `DeviceCaptureProfile` at launch (below). Show the user what their
   hardware actually allows.
2. **Stack first.** Averaging N frames drops read-noise ~√N and beats a single
   capped exposure on nearly every phone — and it's the only technique that ports
   to Samsung's 0.1 s wall.
3. **Best negative for the hero frame.** Where the platform allows it (iPhone
   ProRAW), grab one maximum-quality RAW frame alongside the stack.
4. **Honest ceilings.** If a device caps single exposure hard, say so and rely on
   the stack rather than silently producing a dark frame.

## Good baseline manual settings (starting point, tripod)

- Exposure: as long as the device honestly allows (≤1 s iPhone custom; up to
  15–30 s via native night pipelines / stacking).
- ISO: 1600–3200 as a clean starting point; higher (10k+) only with strong noise
  reduction / stacking.
- Focus: **locked at infinity**.
- White balance: **locked ~5200 K daylight** so the night sky isn't auto-warmed.
- Aperture: fixed on phones (use the widest native lens, typically f/1.6–f/2.2).

## Sources

- Apple — `AVCaptureDeviceFormat` / `activeMaxExposureDuration` docs; Apple
  Developer Forums (48 MP + custom ISO/exposure limitation).
- objc.io — *Camera Capture on iOS*.
- MacRumors — iPhone 14 Pro Night Mode astro examples (30 s, ISO 10k–12.5k, 12 MP).
- Open Camera forums / SourceForge — Camera2 long-exposure device limits.
- Samsung Developer Forums; AndroidPolice — Pixel astrophotography stacking.
- AstroBackyard / Skies & Scopes — smartphone astro settings.
