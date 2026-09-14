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
[Namespace](https://namespace.so) runners:

1. **Simulation unit tests** (`namespace-profile-mac-large`) — `swift test` over
   the crop, farmer, weather, day/night, camera and stability suites.
2. **Simulation on Linux** (`namespace-profile-default-arm64`) — the same tests
   compiled in a container from [`Dockerfile`](Dockerfile). The core only needs
   Foundation, so a non-Apple toolchain is a useful second opinion on the game
   logic.
3. **Build + smoke test** (`namespace-profile-mac-large`) — compiles the `.app`,
   boots a real simulator, installs and launches it, then takes two screenshots
   six seconds apart and fails if they are identical. That single assertion
   encodes the design goal: the world has to move without anyone touching it.
   Screenshots are uploaded as build artifacts.

Two Namespace features do the heavy lifting:

- **Cache volumes.** `nscloud-cache-action` with `swiftpm` and `xcode` keeps
  `.build`, the SwiftPM caches and Xcode's DerivedData on a volume attached to
  the runner, so nothing is uploaded or downloaded between runs. It has to run
  *after* `actions/checkout`, which wipes the workspace.
- **Remote builders.** The Docker job needs no `setup-buildx-action`, no QEMU
  and no `cache-from`/`cache-to`: the build is routed to a shared remote builder
  with persistent layer caching, and shows up with full logs in the Namespace
  dashboard. The `Dockerfile` also mounts `/src/.build` as a build cache so
  SwiftPM stays warm across builds.

Both jobs run with `VERBOSE=1` and `set -x`, so the logs carry the toolchain,
the hardware, cache sizes before and after, the full `swiftc` invocation, the
simulator inventory and the screenshot hashes.

## Notes

- Randomness goes through a seeded `SplitMix64`, so tests are reproducible.
- `camFit` scales and centers the island for any screen size. There is a
  regression test for it: an earlier hardcoded camera clipped the island's
  underside tip in landscape and its side corners in portrait.
- State is in memory only — the farm resets on a cold launch.
