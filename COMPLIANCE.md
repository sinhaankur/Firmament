# Firmament — Compliance

An honest audit of privacy, licensing, and App Store readiness. Firmament's
posture is simple and strong: **on-device, no account, no analytics, no
tracking.** That is the compliance shield — the app never leaves the device
except for one optional, coarse weather lookup.

## Privacy

| Concern | Status |
| --- | --- |
| Accounts / sign-in | **None** |
| Analytics / tracking SDKs | **None** (no third-party SDKs at all) |
| Data sent off device | **Only** an optional weather lookup: coarse lat/lon → conditions (Open-Meteo, keyless). Nothing else. |
| Location | On-device for sky computation; sent to weather API only when in Capture mode. Not linked to identity, not tracked. |
| Photos | Read (import to edit) + add (save captures). Never uploaded anywhere. |
| Camera / motion / LiDAR | On-device only. |
| Privacy manifest | **`Resources/PrivacyInfo.xcprivacy` present** — declares no tracking, precise-location (app functionality, unlinked), and required-reason APIs (UserDefaults CA92.1, file timestamp C617.1, disk space E174.1). |

**Permission strings** (Info.plist) — all present with honest, specific copy:
`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`,
`NSMotionUsageDescription`, `NSPhotoLibraryUsageDescription` (import),
`NSPhotoLibraryAddUsageDescription` (save), `NSWorldSensingUsageDescription`
(LiDAR).

**App Privacy "nutrition label"** (App Store Connect) should declare:
- *Location (Precise)* → App Functionality → **not linked, not used for tracking**.
- No other data types collected.

## Licensing & attribution

Firmament's own code is **100% custom, MIT © Ankur Sinha**, with **no
third-party libraries**. Only *reference data / public specifications* are used,
each credited here and in-app (Settings → Data):

| Source | License | Use |
| --- | --- | --- |
| **HYG database** (astronexus / David Nash) | **CC BY-SA 4.0** | Bundled naked-eye star subset (`stars.bin`). Attribution given; the reformatted subset is redistributed under the same license. |
| Meeus, *Astronomical Algorithms* | Textbook (algorithms, not code) | Sun/Moon/planet math (reimplemented). |
| JPL approximate-positions elements | Public NASA data | Planet ephemeris. |
| SGP4 (Spacetrack Report #3 / Vallado) | Public algorithm | Satellite propagation (reimplemented from scratch). |
| Open-Meteo | Free, keyless, no attribution required | Optional weather. |
| Celestron NexStar protocol | Public spec | Telescope control (reimplemented). Celestron/NexStar/SkyPortal are their trademarks; Firmament is **independent and unaffiliated**. |

**Action:** because HYG is **ShareAlike**, if the app is ever closed-source the
star data must still be offered under CC BY-SA. Firmament is open-source (MIT app
code + CC BY-SA data), which satisfies this. Keep the attribution in Settings.

## App Store readiness checklist

- [x] Privacy manifest (`PrivacyInfo.xcprivacy`).
- [x] Honest, specific permission usage strings.
- [x] No private APIs; no third-party SDKs.
- [x] All data-source attribution shown in-app.
- [ ] App Privacy nutrition label filled in App Store Connect (declare precise
      location, app-functionality, unlinked/untracked).
- [ ] App icon at all required sizes (single 1024 present; Xcode 26 single-size
      asset is accepted).
- [ ] Export-compliance answer: uses only standard HTTPS (exempt encryption).
- [ ] Telescope/trademark note in the App Store description ("independent,
      unaffiliated with Celestron").
- [ ] Screenshots + description.

## Data-handling summary (for a privacy policy)

> Firmament processes everything on your device. It does not require an account
> and contains no analytics or tracking. Your photos and captures stay on your
> device. Your location is used on-device to compute the sky; when you use
> Capture, a coarse latitude/longitude may be sent to Open-Meteo to fetch local
> weather. No personal data is collected, linked to you, or used for tracking.

© Ankur Sinha. Reviewed 2026-08-05.
