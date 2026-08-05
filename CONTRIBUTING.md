# Contributing to Firmament

Firmament is open source (MIT) and contributions are welcome. It's a native iOS
app that identifies the real sky and captures it — please keep changes aligned
with the project's principles.

## Principles

- **All custom code, no third-party dependencies.** The only frameworks are
  Apple's own. Please don't add SPM/CocoaPods/Carthage packages; if you need a
  capability, implement it or discuss it in an issue first.
- **Truth over spectacle.** Every position comes from real data; where a value is
  approximate, the UI says so. Don't invent objects or events.
- **On-device and private.** No accounts, no analytics, no sending user data off
  the phone. The one network call (optional weather) sends only a coarse lat/lon.
- **The math decides; any LLM only phrases.** Deterministic engines produce the
  numbers; on-device models (Apple Intelligence) narrate — they never override
  the computed result.
- **Mobile-first.** Design and verify at the phone, in the dark, one-handed. Big
  touch targets, no hover-only affordances.

## Getting set up

```bash
brew install xcodegen
git clone https://github.com/sinhaankur/Firmament.git
cd Firmament
xcodegen generate
open NightSky.xcodeproj
```

Set your signing Team in **Signing & Capabilities**, then run on a device (the
camera/motion/location features don't work in the Simulator).

`project.yml` is the source of truth for the Xcode project — edit it, not the
generated `.xcodeproj` (which is gitignored).

## Making changes

- Match the surrounding code's style, naming, and comment density.
- Keep engines pure where they are pure (`NightSkyEngine` has no UIKit/network).
- Add new planets, stars, or constellations as single-file data edits.
- Run a device build before opening a PR:
  `xcodebuild -project NightSky.xcodeproj -scheme NightSky -destination 'generic/platform=iOS' build`

## Reporting issues

Field reports are especially valuable — tell us the device, the sky conditions,
and what you saw vs. expected. Screenshots of the overlay or a capture help a lot.

By contributing you agree your contributions are licensed under the MIT License.
