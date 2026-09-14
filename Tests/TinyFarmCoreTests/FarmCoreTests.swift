import XCTest
import CoreGraphics
@testable import TinyFarmCore

private let portrait = CGSize(width: 393, height: 852)   // iPhone 16
private let landscape = CGSize(width: 852, height: 393)

/// A world with a fixed seed, so every run behaves identically.
private func makeWorld(seed: UInt64 = 42, size: CGSize = portrait) -> FarmWorld {
    var w = FarmWorld(seed: seed)
    w.setup(size: size)
    return w
}

/// Advance `seconds` of simulated time at the app's 30 Hz tick rate.
private func advance(_ w: inout FarmWorld, seconds: Double, size: CGSize = portrait) {
    let dt = 1.0 / 30.0
    for _ in 0..<Int(seconds / dt) { w.step(dt: dt, size: size) }
}

// MARK: - Board setup

final class BoardTests: XCTestCase {

    func testSetupCreatesNinePlotsInTheFieldBlock() {
        let w = makeWorld()
        XCTAssertEqual(w.plots.count, 9)
        for p in w.plots {
            XCTAssertTrue((2...4).contains(Int(p.gx)), "plot gx \(p.gx) outside the field")
            XCTAssertTrue((2...4).contains(Int(p.gy)), "plot gy \(p.gy) outside the field")
        }
    }

    func testTileTypesMatchTheLayout() {
        let w = makeWorld()
        XCTAssertEqual(w.tileType(3, 3), .soil)     // middle of the field
        XCTAssertEqual(w.tileType(1, 3), .path)     // path beside the house
        XCTAssertEqual(w.tileType(5, 5), .water)    // pond
        XCTAssertEqual(w.tileType(0, 0), .grass)    // corner
    }

    func testPlotIndexRoundTripsWithBoardCoordinates() {
        let w = makeWorld()
        for y in 2...4 {
            for x in 2...4 {
                let i = try? XCTUnwrap(w.plotIndex(x, y))
                XCTAssertEqual(w.plots[i!].gx, Double(x))
                XCTAssertEqual(w.plots[i!].gy, Double(y))
            }
        }
        XCTAssertNil(w.plotIndex(0, 0))
    }

    func testSetupIsReproducibleForAGivenSeed() {
        let a = makeWorld(seed: 7), b = makeWorld(seed: 7)
        XCTAssertEqual(a.plots.map(\.growth), b.plots.map(\.growth))
        XCTAssertEqual(a.chickens.map(\.gx), b.chickens.map(\.gx))
    }
}

// MARK: - Crops

final class CropTests: XCTestCase {

    func testWateredCropsGrow() {
        var w = makeWorld()
        w.plots[0].planted = true
        w.plots[0].growth = 0
        w.plots[0].moisture = 1.0
        w.clock = w.dayLength * 0.25          // high noon, fastest growth

        let before = w.plots[0].growth
        advance(&w, seconds: 3)
        XCTAssertGreaterThan(w.plots[0].growth, before)
    }

    func testDrySoilStopsGrowth() {
        var w = makeWorld()
        w.plots[0].planted = true
        w.plots[0].growth = 0.4
        w.plots[0].moisture = 0.0             // below the 0.15 threshold
        w.weather = .clear

        let before = w.plots[0].growth
        advance(&w, seconds: 3)
        XCTAssertEqual(w.plots[0].growth, before, accuracy: 1e-9,
                       "a crop with no water must not grow")
    }

    func testSoilDriesOutOverTime() {
        var w = makeWorld()
        w.plots[0].planted = true
        w.plots[0].moisture = 1.0
        w.weather = .clear
        w.clock = w.dayLength * 0.25

        advance(&w, seconds: 5)
        XCTAssertLessThan(w.plots[0].moisture, 1.0)
    }

    func testRainWatersTheSoil() {
        var w = makeWorld()
        w.plots[0].planted = true
        w.plots[0].moisture = 0.2
        w.weather = .rain
        w.weatherLeft = 100                   // hold the weather steady

        advance(&w, seconds: 4)
        XCTAssertGreaterThan(w.plots[0].moisture, 0.2,
                             "rain should add moisture faster than the sun removes it")
    }

    func testMoistureAndGrowthStayInRange() {
        var w = makeWorld()
        advance(&w, seconds: 240)
        for p in w.plots {
            XCTAssertTrue((0...1).contains(p.moisture), "moisture out of range: \(p.moisture)")
            XCTAssertTrue((0...1).contains(p.growth), "growth out of range: \(p.growth)")
        }
    }

    func testCropsRipenButNeverOvershoot() {
        var w = makeWorld()
        for i in w.plots.indices {
            w.plots[i].planted = true
            w.plots[i].growth = 0.99
            w.plots[i].moisture = 1.0
        }
        advance(&w, seconds: 1)
        for p in w.plots where p.planted {
            XCTAssertLessThanOrEqual(p.growth, 1.0)
        }
    }
}

// MARK: - Farmer

final class FarmerTests: XCTestCase {

    func testChorePriorityIsRipeThenThirstyThenEmpty() {
        var w = makeWorld()
        for i in w.plots.indices {                 // start from a clean slate
            w.plots[i] = Plot(gx: w.plots[i].gx, gy: w.plots[i].gy)
        }

        // only empty soil -> plant
        XCTAssertEqual(w.jobFor(w.plots[w.chooseChore()!]), .plant)

        // a thirsty crop outranks empty soil
        w.plots[5].planted = true
        w.plots[5].moisture = 0.1
        XCTAssertEqual(w.chooseChore(), 5)
        XCTAssertEqual(w.jobFor(w.plots[5]), .water)

        // a ripe crop outranks everything
        w.plots[8].planted = true
        w.plots[8].growth = 1.0
        w.plots[8].moisture = 0.9
        XCTAssertEqual(w.chooseChore(), 8)
        XCTAssertEqual(w.jobFor(w.plots[8]), .harvest)
    }

    func testHarvestingClearsThePlotAndPaysOut() {
        var w = makeWorld()
        w.plots[3].planted = true
        w.plots[3].kind = .pumpkin
        w.plots[3].growth = 1.0
        w.farmer.target = 3
        w.farmer.job = .harvest

        let coins = w.coins
        w.applyJob(at: 3)

        XCTAssertEqual(w.coins, coins + CropKind.pumpkin.value)
        XCTAssertEqual(w.harvested, 1)
        XCTAssertFalse(w.plots[3].planted)
        XCTAssertEqual(w.plots[3].growth, 0)
    }

    func testWateringFillsThePlot() {
        var w = makeWorld()
        w.plots[2].planted = true
        w.plots[2].moisture = 0.05
        w.farmer.job = .water
        w.applyJob(at: 2)
        XCTAssertEqual(w.plots[2].moisture, 1.0, accuracy: 1e-9)
    }

    func testFarmerWalksToItsTargetAndWorksTheField() {
        var w = makeWorld()
        w.plots[8].planted = true
        w.plots[8].growth = 1.0               // a ripe crop to walk to
        let start = CGPoint(x: w.farmer.gx, y: w.farmer.gy)

        advance(&w, seconds: 12)

        let moved = hypot(w.farmer.gx - start.x, w.farmer.gy - start.y)
        XCTAssertGreaterThan(moved, 0.5, "the farmer should have walked somewhere")
        XCTAssertGreaterThan(w.harvested, 0, "the farmer should have harvested the ripe crop")
    }

    /// The whole point of the game: it plays itself.
    func testWorldMakesProgressWithNoInput() {
        var w = makeWorld()
        advance(&w, seconds: 120)
        XCTAssertGreaterThan(w.harvested, 0, "nothing was harvested in two minutes")
        XCTAssertGreaterThan(w.coins, 0, "no coins earned in two minutes")
    }

    func testFarmerStaysOnTheBoard() {
        var w = makeWorld()
        advance(&w, seconds: 300)
        XCTAssertTrue((-1.0...Double(N)).contains(w.farmer.gx), "farmer gx \(w.farmer.gx)")
        XCTAssertTrue((-1.0...Double(N)).contains(w.farmer.gy), "farmer gy \(w.farmer.gy)")
    }
}

// MARK: - Chickens

final class ChickenTests: XCTestCase {

    func testChickensWanderButStayOnTheIsland() {
        var w = makeWorld()
        let start = w.chickens.map { CGPoint(x: $0.gx, y: $0.gy) }

        advance(&w, seconds: 90)

        let moved = zip(start, w.chickens).contains { hypot($1.gx - $0.x, $1.gy - $0.y) > 0.3 }
        XCTAssertTrue(moved, "no chicken moved in 90 seconds")

        for c in w.chickens {
            XCTAssertTrue((-1.0...Double(N)).contains(c.gx), "chicken gx \(c.gx)")
            XCTAssertTrue((-1.0...Double(N)).contains(c.gy), "chicken gy \(c.gy)")
        }
    }
}

// MARK: - Day / night and weather

final class SkyTests: XCTestCase {

    func testDayRollsOverAfterExactlyOneDayLength() {
        var w = makeWorld()
        XCTAssertEqual(w.day, 1)
        advance(&w, seconds: w.dayLength + 1)
        XCTAssertEqual(w.day, 2)
    }

    func testLightPeaksAtMiddayAndIsZeroAtNight() {
        var w = makeWorld()
        w.clock = w.dayLength * 0.25
        XCTAssertEqual(w.light, 1.0, accuracy: 0.01, "should be full daylight at midday")

        w.clock = w.dayLength * 0.75
        XCTAssertEqual(w.light, 0.0, accuracy: 1e-9, "should be fully dark at midnight")
    }

    func testClockStringStartsAtSunrise() {
        var w = makeWorld()
        w.clock = 0
        XCTAssertEqual(w.timeString(), "06:00")
        w.clock = w.dayLength * 0.5
        XCTAssertEqual(w.timeString(), "18:00")
    }

    func testWeatherCyclesAndNeverGetsStuck() {
        var w = makeWorld()
        var seen = Set<String>()
        for _ in 0..<40 {
            advance(&w, seconds: 5)
            seen.insert(w.weather.label)
        }
        XCTAssertGreaterThan(seen.count, 1, "weather never changed: \(seen)")
    }

    func testRaindropsAreCleanedUpWhenTheRainStops() {
        var w = makeWorld()
        w.weather = .rain
        w.weatherLeft = 100
        advance(&w, seconds: 2)
        XCTAssertFalse(w.drops.isEmpty, "rain should spawn drops")

        w.weather = .clear
        w.weatherLeft = 100
        advance(&w, seconds: 6)
        XCTAssertTrue(w.drops.isEmpty, "drops should drain away once the rain stops")
    }
}

// MARK: - Camera

final class CameraTests: XCTestCase {

    /// Regression test. The camera origin used to be hardcoded, which clipped
    /// the island's underside tip in landscape and its side corners in
    /// portrait. Every extreme point must stay on screen in both orientations.
    func testWholeIslandStaysOnScreenInBothOrientations() {
        for size in [portrait, landscape, CGSize(width: 320, height: 568)] {
            let f = camFit(size)
            for p in Island.extremes {
                let sx = p.x * f.s + f.tx
                let sy = p.y * f.s + f.ty
                XCTAssertTrue((0...size.width).contains(sx),
                              "x \(sx) off screen at \(size)")
                XCTAssertTrue((0...size.height).contains(sy),
                              "y \(sy) off screen at \(size)")
            }
        }
    }

    func testCamFitNeverUpscalesPastTheCap() {
        let f = camFit(CGSize(width: 4000, height: 4000))
        XCTAssertLessThanOrEqual(f.s, 1.3)
        XCTAssertGreaterThan(f.s, 0)
    }

    func testProjectionIsIsometric() {
        let cam = Cam(origin: .zero, light: 1, clock: 0)
        // +gx goes right and down, +gy goes left and down, by equal amounts
        let ox = cam.p(1, 0), oy = cam.p(0, 1)
        XCTAssertEqual(ox.x, Cam.tw / 2, accuracy: 1e-9)
        XCTAssertEqual(oy.x, -Cam.tw / 2, accuracy: 1e-9)
        XCTAssertEqual(ox.y, oy.y, accuracy: 1e-9)
        // height lifts straight up the screen
        XCTAssertEqual(cam.p(0, 0, 1).y, -Cam.tz, accuracy: 1e-9)
    }
}

// MARK: - Interaction

final class InteractionTests: XCTestCase {

    func testTapWatersThePlotUnderTheFinger() {
        var w = makeWorld()
        for i in w.plots.indices { w.plots[i].moisture = 0.1 }

        // Project the middle bed to screen space, then tap exactly there.
        let f = camFit(portrait)
        let cam = Cam(origin: .zero, light: 1, clock: 0)
        let target = w.plotIndex(3, 3)!
        let world = cam.p(w.plots[target].gx, w.plots[target].gy)
        let tap = CGPoint(x: world.x * f.s + f.tx, y: world.y * f.s + f.ty)

        w.waterNearest(at: tap, size: portrait)

        XCTAssertEqual(w.plots[target].moisture, 1.0, accuracy: 1e-9)
        for (i, p) in w.plots.enumerated() where i != target {
            XCTAssertEqual(p.moisture, 0.1, accuracy: 1e-9, "tap watered the wrong plot")
        }
    }

    func testTapsFarOffBoardAreHarmless() {
        var w = makeWorld()
        for p in [CGPoint(x: -500, y: -500), CGPoint(x: 5000, y: 5000), .zero] {
            w.waterNearest(at: p, size: portrait)
        }
        XCTAssertEqual(w.plots.count, 9)
        XCTAssertTrue(w.plots.allSatisfy { (0...1).contains($0.moisture) })
    }
}

// MARK: - Stability

final class StabilityTests: XCTestCase {

    /// Long soak: nothing should drift to NaN, explode, or leak unboundedly.
    func testLongRunStaysFinite() {
        var w = makeWorld()
        advance(&w, seconds: 600)   // ten minutes, eight in-game days

        XCTAssertTrue(w.clock.isFinite)
        XCTAssertGreaterThan(w.day, 1)
        XCTAssertLessThanOrEqual(w.drops.count, 80, "raindrops should be recycled, not accumulated")

        for p in w.plots {
            XCTAssertTrue(p.growth.isFinite && p.moisture.isFinite)
        }
        XCTAssertTrue(w.farmer.gx.isFinite && w.farmer.gy.isFinite)
        for c in w.chickens { XCTAssertTrue(c.gx.isFinite && c.gy.isFinite) }
    }

    func testStepIsStableAtIrregularFrameTimes() {
        var w = makeWorld()
        // Simulate janky frames: 8ms up to 250ms.
        for dt in stride(from: 0.008, through: 0.25, by: 0.004) {
            for _ in 0..<20 { w.step(dt: dt, size: portrait) }
        }
        XCTAssertTrue(w.clock.isFinite)
        for p in w.plots {
            XCTAssertTrue((0...1).contains(p.moisture))
            XCTAssertTrue((0...1).contains(p.growth))
        }
    }
}
