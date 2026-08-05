# Firmament — Quality Analysis & Gaps

An honest QA audit as of 2026-08-05. Overall the codebase is healthy: **40 Swift
files, ~5,375 LOC, 0 build warnings, 0 `fatalError`/`try!`, 1 safe force-unwrap,
no third-party dependencies.** The gaps below are prioritized.

## Strengths

- Clean build, no warnings. Pure Swift + Apple frameworks.
- Two-engine architecture (NightSkyEngine, CameraEngine) with pure, testable cores.
- Honest data model (SGP4 numerically validated ~405–423 km / 7.66 km/s).
- Graceful degradation already in place: fallback observer (Greenwich) when
  location is denied, deterministic advisor when no LLM, static star fallback if
  `stars.bin` is missing, "unavailable" states for weather/telescope.

## High priority

1. **No background pause.** The 0.2 s sky-recompute timer and the camera session
   keep running when the app is backgrounded → battery drain. **Fix: observe
   `scenePhase` and stop sensors/camera/timer when not `.active`.** *(Fixed in
   this pass.)*
2. **Zero accessibility.** No `accessibilityLabel`/`Hint` anywhere; VoiceOver
   users can't operate the shutter, mode switch, or controls. **Fix: label the
   key controls (shutter, mode switch, telescope/settings/import buttons).**
   *(Basic labels added in this pass.)*
3. **No automated tests.** The pure engines (SkyMath, SGP4, SolarSystem,
   ImageProcessor, CapturePreset) are ideal unit-test targets and currently have
   none. **Add an XCTest target** — highest ROI is SGP4 + alt/az regression.

## Medium priority

4. **Location-permission-denied UX.** If the user denies location, the app
   silently uses Greenwich with a small "Locating…" chip. Add a clear one-time
   explainer + a deep link to Settings.
5. **Camera-unavailable state.** `CameraEngine.lastError` is set but never shown;
   surface "No camera available" instead of a black screen.
6. **iCloud photo import.** `loadTransferable(Data.self)` can return nil for a
   not-yet-downloaded iCloud asset; the error is now surfaced, but a progress/
   retry affordance would be better.
7. **Bundled TLEs age.** Satellite positions drift over weeks (epoch 2026-210).
   Labeled "from a stored orbit," but a live CelesTrak fetch is the real fix.
8. **Dynamic Type.** All font sizes are fixed points; they won't scale for users
   who need larger text. Consider `.dynamicTypeSize` clamped ranges.

## Low priority / future

9. **iPad layout.** Target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). iPad
   would need a landscape/regular-width layout pass.
10. **Localization.** All strings are hardcoded English; no `.strings` catalog.
11. **Landscape.** Portrait-locked — fine for a sky app, but astrophotographers
    on a tripod may want landscape.
12. **Star-field performance ceiling.** ~8,900-star Canvas at wide FOV is fine on
    A17/A19, but validate on the oldest supported device (iPhone with iOS 17).
13. **Haptics.** A capture/shutter haptic would feel more pro.

## What's genuinely missing (feature gaps)

- **Automated tests** (see #3) — the one true "missing essential."
- **Live TLE refresh** for satellites.
- **Time-travel** date scrubbing (the engine already supports any date).
- **A capture gallery** inside the app (currently saves to Photos only).
- **Onboarding for denied permissions** (recovery path).
- **Android app** (separate native port — tracked as planned).

## Verification done

- Build: 0 warnings, 0 errors (Debug, iOS Simulator + device).
- Static scan: no `TODO`/`FIXME`/`fatalError`/`try!`; 1 safe force-unwrap.
- Network surface: only `api.open-meteo.com` (optional weather) — matches the
  compliance claim.

© Ankur Sinha. Reviewed 2026-08-05.
