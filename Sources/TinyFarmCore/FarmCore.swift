import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // Apple platforms
#endif
#if canImport(Glibc)
import Glibc          // Linux: sin/cos/hypot; Foundation supplies CGPoint/CGSize
#endif

// MARK: - Deterministic randomness
//
// The world seeds itself from the system by default, but tests inject a fixed
// seed so every simulation run is reproducible.

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Colour

struct RGB {
    var r: Double, g: Double, b: Double

    func mul(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
}

func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

enum Pal {
    static let grassA   = RGB(r: 0.44, g: 0.74, b: 0.36)
    static let grassB   = RGB(r: 0.39, g: 0.69, b: 0.32)
    static let soilDry  = RGB(r: 0.55, g: 0.39, b: 0.25)
    static let soilWet  = RGB(r: 0.31, g: 0.21, b: 0.14)
    static let path     = RGB(r: 0.76, g: 0.66, b: 0.47)
    static let water    = RGB(r: 0.28, g: 0.62, b: 0.88)
    static let dirt     = RGB(r: 0.47, g: 0.33, b: 0.21)
    static let rock     = RGB(r: 0.36, g: 0.28, b: 0.22)
    static let wall     = RGB(r: 0.96, g: 0.91, b: 0.79)
    static let roof     = RGB(r: 0.82, g: 0.33, b: 0.28)
    static let wood     = RGB(r: 0.55, g: 0.38, b: 0.24)
    static let fence    = RGB(r: 0.85, g: 0.73, b: 0.53)
    static let leafHi   = RGB(r: 0.33, g: 0.66, b: 0.33)
    static let leafLo   = RGB(r: 0.20, g: 0.47, b: 0.26)
    static let skin     = RGB(r: 0.95, g: 0.79, b: 0.63)
    static let shirt    = RGB(r: 0.27, g: 0.49, b: 0.82)
    static let jeans    = RGB(r: 0.27, g: 0.31, b: 0.42)
    static let straw    = RGB(r: 0.93, g: 0.80, b: 0.44)
    static let hen      = RGB(r: 0.98, g: 0.97, b: 0.94)
    static let comb     = RGB(r: 0.87, g: 0.26, b: 0.22)
    static let beak     = RGB(r: 0.96, g: 0.67, b: 0.20)
    static let wheat    = RGB(r: 0.91, g: 0.76, b: 0.33)
    static let carrot   = RGB(r: 0.94, g: 0.52, b: 0.18)
    static let pumpkin  = RGB(r: 0.93, g: 0.50, b: 0.17)
}

// MARK: - Isometric camera

let N = 7   // the board is N x N tiles

struct Cam {
    static let tw: Double = 62      // tile width on screen
    static let th: Double = 32      // tile depth on screen
    static let tz: Double = 22      // one unit of height

    var origin: CGPoint
    var light: Double               // 0 = midnight, 1 = noon
    var clock: Double

    /// Grid (gx, gy, z) -> screen point.
    func p(_ gx: Double, _ gy: Double, _ z: Double = 0) -> CGPoint {
        CGPoint(x: origin.x + (gx - gy) * Cam.tw / 2,
                y: origin.y + (gx + gy) * Cam.th / 2 - z * Cam.tz)
    }
}

/// Geometry of the floating island in unscaled camera space (origin at .zero).
enum Island {
    static let rimDrop = 26.0      // thickness of the dirt rim
    static let tipDrop = 92.0      // how far the underside tapers below the rim
    static let topMargin = -86.0   // headroom for the roof ridge and treetops

    static var bottom: Double { Double(2 * N - 1) * Cam.th / 2 + rimDrop + tipDrop }
    static var width: Double { Double(N) * Cam.tw }

    /// The points that must stay on screen for the island to be fully visible.
    static var extremes: [CGPoint] {
        let cam = Cam(origin: .zero, light: 1, clock: 0)
        let n = Double(N)
        return [
            cam.p(-0.5, -0.5),                    // back corner
            cam.p(n - 0.5, -0.5),                 // right corner
            cam.p(n - 0.5, n - 0.5),              // front corner
            cam.p(-0.5, n - 0.5),                 // left corner
            CGPoint(x: 0, y: bottom),             // underside tip
            CGPoint(x: 0, y: topMargin),          // roof ridge / treetops
        ]
    }
}

/// Scale + offset that fits the whole island into `size`, in any orientation.
/// The renderer applies this as a context transform, so tile geometry and
/// hand-drawn sprite offsets scale together.
func camFit(_ size: CGSize) -> (s: Double, tx: Double, ty: Double) {
    let contentH = Island.bottom - Island.topMargin
    let s = min((size.width - 28) / Island.width,
                (size.height - 150) / contentH,
                1.3)
    return (s,
            size.width / 2,
            size.height * 0.46 - (Island.topMargin + Island.bottom) / 2 * s)
}

// MARK: - World model

enum Tile { case grass, soil, water, path }

enum CropKind: CaseIterable {
    case carrot, wheat, pumpkin

    var value: Int {
        switch self {
        case .carrot: return 3
        case .wheat: return 2
        case .pumpkin: return 6
        }
    }
    var color: RGB {
        switch self {
        case .carrot: return Pal.carrot
        case .wheat: return Pal.wheat
        case .pumpkin: return Pal.pumpkin
        }
    }
}

struct Plot {
    var gx: Double
    var gy: Double
    var planted = false
    var kind: CropKind = .carrot
    var growth: Double = 0
    var moisture: Double = 0.5
    var pop: Double = 0

    var isRipe: Bool { planted && growth >= 1.0 }
    var isThirsty: Bool { planted && moisture < 0.3 }
}

struct Chicken {
    var gx: Double, gy: Double
    var tx: Double, ty: Double
    var speed: Double
    var bob: Double
    var facingLeft = false
    var pause: Double = 0
}

struct Cloud {
    var x: Double, y: Double, scale: Double, speed: Double
}

struct Drop { var x: Double, y: Double, v: Double }
struct Spark { var x: Double, y: Double, phase: Double }

enum Weather {
    case clear, cloudy, rain

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        }
    }
    var icon: String {
        switch self {
        case .clear: return "☀️"
        case .cloudy: return "⛅️"
        case .rain: return "🌧️"
        }
    }
}

enum Job { case idle, plant, water, harvest }

struct Farmer {
    var gx: Double = 1, gy: Double = 5
    var target: Int? = nil
    var job: Job = .idle
    var work: Double = 0
    var facingLeft = false
    var step: Double = 0
    var say: String = ""
    var sayTimer: Double = 0
}

// MARK: - Simulation
//
// Everything here is pure state + time stepping: no SwiftUI, no rendering.
// The app drives it from a timer; the tests drive it directly.

struct FarmWorld {
    let dayLength: Double = 75

    var clock: Double = 0
    var day = 1
    var coins = 0
    var harvested = 0

    var plots: [Plot] = []
    var chickens: [Chicken] = []
    var clouds: [Cloud] = []
    var drops: [Drop] = []
    var stars: [Spark] = []
    var fireflies: [Spark] = []
    var farmer = Farmer()

    var weather: Weather = .clear
    var weatherLeft: Double = 12
    var butterfly: Double = 0

    var rng: SplitMix64

    init(seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        rng = SplitMix64(seed: seed)
    }

    // Static scenery
    static let trees: [(Double, Double, Double)] = [(6, 0, 0.3), (0, 4, 0.8), (3, 6, 0.55), (6, 3, 0.1)]
    static let housePos = (gx: 0.9, gy: 1.0)
    static let waterTiles: [(Int, Int)] = [(5, 5), (6, 5), (5, 6), (6, 6)]

    /// 0 at sunrise, 0.5 at sunset, wrapping once per day.
    var phase: Double { (clock / dayLength).truncatingRemainder(dividingBy: 1) }
    /// Daylight strength; 0 through the whole night.
    var light: Double { max(0, sin(phase * 2 * .pi)) }

    // MARK: Board queries

    func tileType(_ x: Int, _ y: Int) -> Tile {
        if FarmWorld.waterTiles.contains(where: { $0.0 == x && $0.1 == y }) { return .water }
        if x >= 2 && x <= 4 && y >= 2 && y <= 4 { return .soil }
        if x == 1 && y >= 1 && y <= 5 { return .path }
        return .grass
    }

    func plotIndex(_ x: Int, _ y: Int) -> Int? {
        guard x >= 2, x <= 4, y >= 2, y <= 4 else { return nil }
        let i = (y - 2) * 3 + (x - 2)
        return i < plots.count ? i : nil
    }

    // MARK: Setup

    mutating func setup(size: CGSize) {
        plots = (0..<3).flatMap { r in
            (0..<3).map { c in Plot(gx: Double(c + 2), gy: Double(r + 2)) }
        }
        for i in [0, 4, 7] where i < plots.count {
            plots[i].planted = true
            plots[i].kind = CropKind.allCases.randomElement(using: &rng)!
            plots[i].growth = Double.random(in: 0.2...0.6, using: &rng)
            plots[i].moisture = Double.random(in: 0.45...0.9, using: &rng)
        }

        chickens = (0..<3).map { _ in
            let t = randomGrassTile()
            return Chicken(gx: t.0, gy: t.1, tx: t.0, ty: t.1,
                           speed: Double.random(in: 0.25...0.5, using: &rng),
                           bob: Double.random(in: 0...6.28, using: &rng))
        }

        clouds = (0..<4).map { _ in
            Cloud(x: Double.random(in: 0...size.width, using: &rng),
                  y: Double.random(in: 50...size.height * 0.22, using: &rng),
                  scale: Double.random(in: 0.65...1.15, using: &rng),
                  speed: Double.random(in: 4...12, using: &rng))
        }
        stars = (0..<46).map { _ in
            Spark(x: Double.random(in: 0...size.width, using: &rng),
                  y: Double.random(in: 8...size.height * 0.55, using: &rng),
                  phase: Double.random(in: 0...6.28, using: &rng))
        }
        fireflies = (0..<16).map { _ in
            Spark(x: Double.random(in: 24...size.width - 24, using: &rng),
                  y: Double.random(in: size.height * 0.42...size.height * 0.85, using: &rng),
                  phase: Double.random(in: 0...6.28, using: &rng))
        }
    }

    mutating func randomGrassTile() -> (Double, Double) {
        var candidates: [(Double, Double)] = []
        for y in 0..<N {
            for x in 0..<N {
                let t = tileType(x, y)
                if t == .grass || t == .path {
                    if x <= 1 && y <= 1 { continue }   // keep clear of the farmhouse
                    candidates.append((Double(x), Double(y)))
                }
            }
        }
        return candidates.randomElement(using: &rng) ?? (0, 6)
    }

    // MARK: Stepping

    mutating func step(dt: Double, size: CGSize) {
        let before = phase
        clock += dt
        if phase < before { day += 1 }
        butterfly += dt

        stepWeather(dt: dt, size: size)
        stepClouds(dt: dt, size: size)
        stepCrops(dt: dt)
        stepFarmer(dt: dt)
        stepChickens(dt: dt)
        stepFireflies(dt: dt, size: size)
    }

    mutating func stepWeather(dt: Double, size: CGSize) {
        weatherLeft -= dt
        if weatherLeft <= 0 {
            switch weather {
            case .clear:
                weather = .cloudy
                weatherLeft = Double.random(in: 8...14, using: &rng)
            case .cloudy:
                weather = Bool.random(using: &rng) ? .rain : .clear
                weatherLeft = Double.random(in: 9...15, using: &rng)
            case .rain:
                weather = .clear
                weatherLeft = Double.random(in: 12...20, using: &rng)
            }
        }

        if weather == .rain {
            while drops.count < 80 {
                drops.append(Drop(x: Double.random(in: -20...size.width + 20, using: &rng),
                                  y: Double.random(in: -60...size.height, using: &rng),
                                  v: Double.random(in: 460...720, using: &rng)))
            }
        }
        for i in drops.indices {
            drops[i].y += drops[i].v * dt
            drops[i].x -= 38 * dt
        }
        if weather == .rain {
            for i in drops.indices where drops[i].y > size.height {
                drops[i].y = Double.random(in: -70 ... -10, using: &rng)
                drops[i].x = Double.random(in: -20...size.width + 20, using: &rng)
            }
        } else {
            drops.removeAll { $0.y > size.height }
        }
    }

    mutating func stepClouds(dt: Double, size: CGSize) {
        for i in clouds.indices {
            clouds[i].x += clouds[i].speed * dt
            if clouds[i].x - 60 > size.width {
                clouds[i].x = -60
                clouds[i].y = Double.random(in: 50...size.height * 0.22, using: &rng)
                clouds[i].scale = Double.random(in: 0.65...1.15, using: &rng)
            }
        }
    }

    mutating func stepCrops(dt: Double) {
        for i in plots.indices {
            if plots[i].pop > 0 { plots[i].pop = max(0, plots[i].pop - dt * 1.6) }
            guard plots[i].planted else { continue }

            // Soil dries out, faster under a strong sun; rain soaks it.
            plots[i].moisture -= dt * (0.012 + 0.030 * light)
            if weather == .rain { plots[i].moisture += dt * 0.22 }
            plots[i].moisture = clamp01(plots[i].moisture)

            // Crops only grow with water, and grow best in daylight.
            if plots[i].moisture > 0.15 && plots[i].growth < 1.0 {
                plots[i].growth = min(1.0, plots[i].growth + dt * (0.030 + 0.055 * light))
            }
        }
    }

    mutating func stepFarmer(dt: Double) {
        farmer.sayTimer = max(0, farmer.sayTimer - dt)
        if farmer.sayTimer == 0 { farmer.say = "" }

        if farmer.work > 0 {
            farmer.work -= dt
            farmer.step += dt * 10
            if farmer.work <= 0, let idx = farmer.target {
                applyJob(at: idx)
                farmer.target = nil
                farmer.job = .idle
            }
            return
        }

        if farmer.target == nil {
            farmer.target = chooseChore()
            if let idx = farmer.target { farmer.job = jobFor(plots[idx]) }
        }
        guard let idx = farmer.target else { return }

        // stand just in front of the bed
        let tx = plots[idx].gx, ty = plots[idx].gy + 0.62
        let dx = tx - farmer.gx, dy = ty - farmer.gy
        let dist = max(0.0001, (dx * dx + dy * dy).squareRoot())

        if dist < 0.06 {
            farmer.work = farmer.job == .harvest ? 0.8 : 1.0
            farmer.say = farmer.job == .harvest ? "🧺" : (farmer.job == .water ? "💧" : "🌰")
            farmer.sayTimer = 1.6
        } else {
            let speed = 1.15   // tiles / second
            farmer.gx += dx / dist * speed * dt
            farmer.gy += dy / dist * speed * dt
            // screen-space facing: +gx goes right, +gy goes left
            farmer.facingLeft = (dx - dy) < 0
            farmer.step += dt * 9
        }
    }

    func jobFor(_ p: Plot) -> Job {
        if p.isRipe { return .harvest }
        if !p.planted { return .plant }
        return .water
    }

    /// Ripe crops first, then thirsty ones, then empty soil, then top up the
    /// driest bed so the farmer is never idle.
    func chooseChore() -> Int? {
        if let i = plots.firstIndex(where: { $0.isRipe }) { return i }
        if let i = plots.firstIndex(where: { $0.isThirsty }) { return i }
        if let i = plots.firstIndex(where: { !$0.planted }) { return i }
        return plots.indices.min(by: { plots[$0].moisture < plots[$1].moisture })
    }

    mutating func applyJob(at idx: Int) {
        switch farmer.job {
        case .harvest:
            coins += plots[idx].kind.value
            harvested += 1
            plots[idx].planted = false
            plots[idx].growth = 0
            plots[idx].pop = 1
        case .plant:
            plots[idx].planted = true
            plots[idx].kind = CropKind.allCases.randomElement(using: &rng)!
            plots[idx].growth = 0
            plots[idx].moisture = max(plots[idx].moisture, 0.55)
        case .water, .idle:
            plots[idx].moisture = 1.0
        }
    }

    mutating func stepChickens(dt: Double) {
        for i in chickens.indices {
            chickens[i].bob += dt * 7
            if chickens[i].pause > 0 { chickens[i].pause -= dt; continue }

            let dx = chickens[i].tx - chickens[i].gx
            let dy = chickens[i].ty - chickens[i].gy
            let dist = max(0.0001, (dx * dx + dy * dy).squareRoot())

            if dist < 0.08 {
                chickens[i].pause = Double.random(in: 0.7...2.4, using: &rng)
                let t = randomGrassTile()
                chickens[i].tx = t.0 + Double.random(in: -0.25...0.25, using: &rng)
                chickens[i].ty = t.1 + Double.random(in: -0.25...0.25, using: &rng)
                chickens[i].speed = Double.random(in: 0.25...0.55, using: &rng)
            } else {
                chickens[i].gx += dx / dist * chickens[i].speed * dt
                chickens[i].gy += dy / dist * chickens[i].speed * dt
                chickens[i].facingLeft = (dx - dy) < 0
            }
        }
    }

    mutating func stepFireflies(dt: Double, size: CGSize) {
        for i in fireflies.indices {
            fireflies[i].x += sin(clock * 0.8 + fireflies[i].phase) * 10 * dt
            fireflies[i].y += cos(clock * 0.6 + fireflies[i].phase) * 8 * dt
            fireflies[i].x = min(max(fireflies[i].x, 12), size.width - 12)
            fireflies[i].y = min(max(fireflies[i].y, size.height * 0.36), size.height - 24)
        }
    }

    // MARK: Interaction

    /// Tap-to-water. `point` is in screen space; it is mapped back through the
    /// board transform so it selects the same plot the player sees.
    mutating func waterNearest(at point: CGPoint, size: CGSize) {
        let f = camFit(size)
        let hit = CGPoint(x: (point.x - f.tx) / f.s, y: (point.y - f.ty) / f.s)
        let cam = Cam(origin: .zero, light: light, clock: clock)
        guard let idx = plots.indices.min(by: {
            let a = cam.p(plots[$0].gx, plots[$0].gy)
            let b = cam.p(plots[$1].gx, plots[$1].gy)
            return hypot(a.x - hit.x, a.y - hit.y) < hypot(b.x - hit.x, b.y - hit.y)
        }) else { return }
        plots[idx].moisture = 1.0
        plots[idx].pop = 0.5
    }

    /// Clock face for the HUD; the day starts at sunrise (06:00).
    func timeString() -> String {
        let hours = (phase * 24 + 6).truncatingRemainder(dividingBy: 24)
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%02d:%02d", h, m)
    }
}
