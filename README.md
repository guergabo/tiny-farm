# Tiny Farm

A tiny isometric world for iOS that takes care of itself. There is nothing to
beat and nothing you have to do: the sun rises and sets, weather rolls through,
crops grow and dry out, chickens wander, and a farmer walks the field planting,
watering and harvesting on his own. You can tap a bed to water it if you feel
like helping.

Built with SwiftUI, drawn entirely with `Canvas` geometry — no sprite assets.

## Layout

```
Sources/TinyFarmCore/   pure simulation: no SwiftUI, unit tested on macOS
App/                    SwiftUI renderer + app entry point
Tests/                  XCTest suite against the simulation
Scripts/build_app.sh    compiles a .app for the iOS Simulator (no Xcode project)
Scripts/smoke_test.sh   boots a simulator and asserts the world runs itself
```

The split matters: `FarmCore.swift` holds all state and time stepping and has
no UI dependency, so the game logic is testable without booting a simulator.
The renderer only reads from it.

## Running it

```bash
swift test              # simulation tests
./Scripts/build_app.sh  # build the .app
./Scripts/smoke_test.sh # boot a simulator, install, verify it animates
```

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on
`namespace-profile-mac-large`, a [Namespace](https://namespace.so) macOS runner:

1. **Simulation unit tests** — `swift test` over the crop, farmer, weather,
   day/night, camera and stability suites.
2. **Build + smoke test** — compiles the `.app`, boots a real simulator,
   installs and launches it, then takes two screenshots six seconds apart and
   fails if they are identical. That single assertion encodes the design goal:
   the world has to move without anyone touching it. Screenshots are uploaded
   as build artifacts.

## Notes

- Randomness goes through a seeded `SplitMix64`, so tests are reproducible.
- `camFit` scales and centers the island for any screen size. There is a
  regression test for it: an earlier hardcoded camera clipped the island's
  underside tip in landscape and its side corners in portrait.
- State is in memory only — the farm resets on a cold launch.
