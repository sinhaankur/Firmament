# NightSky for Android — Planned

This directory is a placeholder for the native Android port of NightSky. It is
**not built yet** — this is an honest roadmap slot, not shipped code.

## Why a separate app

The sky math in [`../DESIGN.md`](../DESIGN.md) and the ephemeris/catalog logic are
platform-agnostic and will be reimplemented in Kotlin. The device-facing layers,
however, have no shared code with iOS:

| Concern            | iOS (this repo)              | Android (planned)                 |
| ------------------ | ---------------------------- | --------------------------------- |
| Location + heading | CoreLocation                 | FusedLocationProvider + Sensor    |
| Attitude / steady  | CoreMotion (true-north ref)  | Rotation-vector sensor            |
| Camera             | AVFoundation                 | CameraX / Camera2                 |
| Depth / foreground | ARKit + LiDAR scene depth    | ARCore Depth API (where present)  |
| Long exposure      | AVCaptureDevice custom exp.  | Camera2 manual sensor controls    |
| UI                 | SwiftUI                      | Jetpack Compose                   |

## Shared source of truth

Both apps implement the same behavior against [`../DESIGN.md`](../DESIGN.md). The
astronomy — Julian date, sidereal time, RA/Dec → alt/az, Sun/Moon/planet
ephemeris, the bright-star catalog — is a direct port of the Swift `SkyEngine`
module and must produce the same positions.

## Status

Planned. Tracked from the [install page](https://sinhaankur.github.io/NightSky/).
