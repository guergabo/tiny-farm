import SwiftUI

@main
struct FarmApp: App {
    var body: some Scene {
        WindowGroup {
            WorldView()
                .statusBarHidden(true)
        }
    }
}

// Rendering-only extensions on the simulation types.

extension RGB {
    var color: Color { Color(red: min(r, 1), green: min(g, 1), blue: min(b, 1)) }
}

extension Cam {
    /// Shade a colour for the time of day. `face` darkens side walls.
    func col(_ c: RGB, _ face: Double = 1.0) -> Color {
        let night = RGB(r: 0.20, g: 0.26, b: 0.50)
        let tinted = c.mix(night, (1 - light) * 0.60)
        let dim = 0.38 + 0.62 * light
        return tinted.mul(dim * face).color
    }
}

func poly(_ pts: [CGPoint]) -> Path {
    var p = Path()
    guard let f = pts.first else { return p }
    p.move(to: f)
    for q in pts.dropFirst() { p.addLine(to: q) }
    p.closeSubpath()
    return p
}

/// Anything drawn on the board, sorted back-to-front before rendering.
enum Sprite {
    case house(gx: Double, gy: Double)
    case tree(gx: Double, gy: Double, seed: Double)
    case crop(Int)
    case chicken(Int)
    case farmer
    case fence(gx: Double, gy: Double, side: Int)
}

// MARK: - View

struct WorldView: View {
    @State private var world = FarmWorld()
    @State private var ready = false

    private let dt = 1.0 / 30.0
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    // Read-only shorthands so the drawing code stays close to the simulation.
    private var plots: [Plot] { world.plots }
    private var chickens: [Chicken] { world.chickens }
    private var clouds: [Cloud] { world.clouds }
    private var drops: [Drop] { world.drops }
    private var stars: [Spark] { world.stars }
    private var fireflies: [Spark] { world.fireflies }
    private var farmer: Farmer { world.farmer }
    private var weather: Weather { world.weather }
    private var clock: Double { world.clock }
    private var light: Double { world.light }
    private var phase: Double { world.phase }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, csize in
                    var g = ctx
                    drawSky(&g, csize)
                    drawStars(&g, csize)
                    drawCelestial(&g, csize)
                    drawClouds(&g, csize)

                    // The island lives in its own scaled space so the whole
                    // scene fits any screen size or orientation.
                    let f = camFit(csize)
                    var gb = g
                    gb.translateBy(x: f.tx, y: f.ty)
                    gb.scaleBy(x: f.s, y: f.s)
                    let cam = Cam(origin: .zero, light: light, clock: clock)
                    drawIsland(&gb, cam)
                    drawTiles(&gb, cam)
                    drawSprites(&gb, cam)

                    drawRain(&g, csize)
                    drawFireflies(&g, csize)
                    drawNight(&g, csize)
                }
                .drawingGroup()

                hud(size: size)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { loc in world.waterNearest(at: loc, size: size) }
            .onReceive(timer) { _ in
                if !ready { world.setup(size: size); ready = true }
                world.step(dt: dt, size: size)
            }
        }
    }

    // MARK: - Sky

    private func drawSky(_ g: inout GraphicsContext, _ size: CGSize) {
        let nightTop = RGB(r: 0.05, g: 0.06, b: 0.18)
        let nightBot = RGB(r: 0.13, g: 0.16, b: 0.34)
        let dayTop   = RGB(r: 0.26, g: 0.58, b: 0.93)
        let dayBot   = RGB(r: 0.76, g: 0.90, b: 0.99)

        var top = nightTop.mix(dayTop, light)
        var bot = nightBot.mix(dayBot, light)
        let glow = max(0, 1 - abs(light - 0.16) / 0.30)
        top = top.mix(RGB(r: 0.80, g: 0.42, b: 0.40), glow * 0.45)
        bot = bot.mix(RGB(r: 1.00, g: 0.70, b: 0.42), glow * 0.70)

        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [top.color, bot.color]),
                                     startPoint: .zero,
                                     endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawStars(_ g: inout GraphicsContext, _ size: CGSize) {
        let a = clamp01((0.24 - light) / 0.24)
        guard a > 0.02 else { return }
        for s in stars {
            let tw = 0.45 + 0.55 * abs(sin(clock * 1.2 + s.phase))
            let r = 0.9 + 1.1 * tw
            g.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(a * tw)))
        }
    }

    private func drawCelestial(_ g: inout GraphicsContext, _ size: CGSize) {
        let isDay = phase < 0.5
        let t = isDay ? phase / 0.5 : (phase - 0.5) / 0.5
        let x = size.width * (0.10 + 0.80 * t)
        let y = size.height * 0.42 - sin(t * .pi) * size.height * 0.30
        let r: Double = isDay ? 26 : 19

        let core: Color = isDay ? Color(red: 1.0, green: 0.93, blue: 0.56)
                                : Color(red: 0.94, green: 0.95, blue: 1.0)
        for i in stride(from: 4, through: 1, by: -1) {
            let rr = r * (1 + Double(i) * 0.55)
            g.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)),
                   with: .color(core.opacity(0.07)))
        }
        g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
               with: .color(core))
        if !isDay {
            g.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 1.05,
                                          width: r * 1.7, height: r * 1.7)),
                   with: .color(Color(red: 0.08, green: 0.10, blue: 0.24)))
        }
    }

    private func drawClouds(_ g: inout GraphicsContext, _ size: CGSize) {
        for c in clouds {
            let base = RGB(r: 1, g: 1, b: 1).mix(RGB(r: 0.42, g: 0.46, b: 0.62),
                                                 (1 - light) * 0.55 + (weather == .rain ? 0.25 : 0))
            let s = c.scale
            let puffs: [(Double, Double, Double)] = [(-26, 4, 16), (-6, -6, 22), (16, 2, 18), (30, 8, 12)]
            for (dx, dy, rr) in puffs {
                let R = rr * s
                g.fill(Path(ellipseIn: CGRect(x: c.x + dx * s - R, y: c.y + dy * s - R,
                                              width: R * 2, height: R * 2)),
                       with: .color(base.color.opacity(0.92)))
            }
            g.fill(Path(roundedRect: CGRect(x: c.x - 34 * s, y: c.y + 2 * s,
                                            width: 68 * s, height: 14 * s),
                        cornerRadius: 7 * s),
                   with: .color(base.mul(0.94).color.opacity(0.92)))
        }
    }

    // MARK: - Island

    private func drawIsland(_ g: inout GraphicsContext, _ cam: Cam) {
        let n = Double(N)
        let A = cam.p(-0.5, -0.5)
        let B = cam.p(n - 0.5, -0.5)
        let C = cam.p(n - 0.5, n - 0.5)
        let D = cam.p(-0.5, n - 0.5)
        let slab = Island.rimDrop
        let Bd = CGPoint(x: B.x, y: B.y + slab)
        let Cd = CGPoint(x: C.x, y: C.y + slab)
        let Dd = CGPoint(x: D.x, y: D.y + slab)

        let shadowRect = CGRect(x: A.x - (B.x - D.x) / 2 * 0.85,
                                y: C.y + 46,
                                width: (B.x - D.x) * 0.85,
                                height: (C.y - A.y) * 0.42)
        g.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.16 * (0.3 + 0.7 * light))))

        let tip = CGPoint(x: (B.x + D.x) / 2, y: Cd.y + Island.tipDrop)   // == Island.bottom
        g.fill(poly([Bd, Cd, tip]), with: .color(cam.col(Pal.rock, 0.60)))
        g.fill(poly([Cd, Dd, tip]), with: .color(cam.col(Pal.rock, 0.76)))

        g.fill(poly([B, C, Cd, Bd]), with: .color(cam.col(Pal.dirt, 0.62)))
        g.fill(poly([C, D, Dd, Cd]), with: .color(cam.col(Pal.dirt, 0.80)))

        for i in 0..<7 {
            let t = Double(i) / 6
            let px = Cd.x + (Bd.x - Cd.x) * t
            let py = Cd.y + (Bd.y - Cd.y) * t + 10 + 6 * sin(Double(i) * 2.1)
            g.fill(Path(ellipseIn: CGRect(x: px - 3, y: py - 2, width: 6, height: 4)),
                   with: .color(cam.col(Pal.rock, 0.7)))
        }
    }

    private func drawTiles(_ g: inout GraphicsContext, _ cam: Cam) {
        for y in 0..<N {
            for x in 0..<N {
                let gx = Double(x), gy = Double(y)
                let c = cam.p(gx, gy)
                let hw = Cam.tw / 2, hh = Cam.th / 2
                let top = poly([CGPoint(x: c.x, y: c.y - hh),
                                CGPoint(x: c.x + hw, y: c.y),
                                CGPoint(x: c.x, y: c.y + hh),
                                CGPoint(x: c.x - hw, y: c.y)])

                switch world.tileType(x, y) {
                case .grass:
                    let base = (x + y) % 2 == 0 ? Pal.grassA : Pal.grassB
                    g.fill(top, with: .color(cam.col(base)))
                    if (x * 7 + y * 3) % 4 == 0 {
                        let tuft = cam.col(Pal.leafLo, 1.0)
                        for k in 0..<3 {
                            let ox = Double(k - 1) * 7
                            var p = Path()
                            p.move(to: CGPoint(x: c.x + ox, y: c.y + 3))
                            p.addLine(to: CGPoint(x: c.x + ox - 1.5, y: c.y - 3))
                            p.addLine(to: CGPoint(x: c.x + ox + 1.5, y: c.y - 2))
                            p.closeSubpath()
                            g.fill(p, with: .color(tuft.opacity(0.55)))
                        }
                    }

                case .path:
                    g.fill(top, with: .color(cam.col(Pal.path)))
                    for k in 0..<4 {
                        let a = Double(k) * 1.9
                        let px = c.x + cos(a) * 12, py = c.y + sin(a) * 6
                        g.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: py - 1.5, width: 5, height: 3)),
                               with: .color(cam.col(Pal.path.mul(0.86))))
                    }

                case .soil:
                    let i = world.plotIndex(x, y)
                    let m = i != nil ? plots[i!].moisture : 0.4
                    let soil = Pal.soilDry.mix(Pal.soilWet, m)
                    let lift = 0.10
                    let cTop = cam.p(gx, gy, lift)
                    let tp = poly([CGPoint(x: cTop.x, y: cTop.y - hh),
                                   CGPoint(x: cTop.x + hw, y: cTop.y),
                                   CGPoint(x: cTop.x, y: cTop.y + hh),
                                   CGPoint(x: cTop.x - hw, y: cTop.y)])
                    g.fill(poly([CGPoint(x: cTop.x + hw, y: cTop.y),
                                 CGPoint(x: cTop.x, y: cTop.y + hh),
                                 CGPoint(x: c.x, y: c.y + hh),
                                 CGPoint(x: c.x + hw, y: c.y)]),
                           with: .color(cam.col(soil, 0.62)))
                    g.fill(poly([CGPoint(x: cTop.x, y: cTop.y + hh),
                                 CGPoint(x: cTop.x - hw, y: cTop.y),
                                 CGPoint(x: c.x - hw, y: c.y),
                                 CGPoint(x: c.x, y: c.y + hh)]),
                           with: .color(cam.col(soil, 0.78)))
                    g.fill(tp, with: .color(cam.col(soil)))
                    for k in -1...1 {
                        var p = Path()
                        let off = Double(k) * 9
                        p.move(to: CGPoint(x: cTop.x - hw * 0.7 + off, y: cTop.y + hh * 0.35))
                        p.addLine(to: CGPoint(x: cTop.x + off + hw * 0.25, y: cTop.y - hh * 0.3))
                        g.stroke(p, with: .color(cam.col(soil.mul(0.82))), lineWidth: 2)
                    }

                case .water:
                    g.fill(top, with: .color(cam.col(Pal.water)))
                    for k in 0..<2 {
                        let ph = clock * 1.4 + Double(x + y) + Double(k) * 2
                        let ox = sin(ph) * 8
                        var p = Path()
                        p.move(to: CGPoint(x: c.x - 12 + ox, y: c.y + Double(k) * 6 - 3))
                        p.addQuadCurve(to: CGPoint(x: c.x + 12 + ox, y: c.y + Double(k) * 6 - 3),
                                       control: CGPoint(x: c.x + ox, y: c.y + Double(k) * 6 - 7))
                        g.stroke(p, with: .color(.white.opacity(0.35 * (0.3 + 0.7 * light))), lineWidth: 1.8)
                    }
                }
            }
        }
    }

    // MARK: - Sprites (depth sorted)

    private func drawSprites(_ g: inout GraphicsContext, _ cam: Cam) {
        var items: [(Double, Sprite)] = []
        items.append((FarmWorld.housePos.gx + FarmWorld.housePos.gy,
                      .house(gx: FarmWorld.housePos.gx, gy: FarmWorld.housePos.gy)))
        for t in FarmWorld.trees { items.append((t.0 + t.1, .tree(gx: t.0, gy: t.1, seed: t.2))) }
        for (i, p) in plots.enumerated() { items.append((p.gx + p.gy, .crop(i))) }
        for (i, c) in chickens.enumerated() { items.append((c.gx + c.gy, .chicken(i))) }
        items.append((farmer.gx + farmer.gy, .farmer))

        for i in 0..<N {
            items.append((Double(i) + -0.6, .fence(gx: Double(i), gy: -0.6, side: 0)))
            items.append((-0.6 + Double(i), .fence(gx: -0.6, gy: Double(i), side: 1)))
        }

        items.sort { $0.0 < $1.0 }
        for (_, s) in items {
            switch s {
            case .house(let gx, let gy):         drawHouse(&g, cam, gx, gy)
            case .tree(let gx, let gy, let sd):  drawTree(&g, cam, gx, gy, sd)
            case .crop(let i):                   drawCrop(&g, cam, plots[i])
            case .chicken(let i):                drawChicken(&g, cam, chickens[i])
            case .farmer:                        drawFarmer(&g, cam)
            case .fence(let gx, let gy, let sd): drawFence(&g, cam, gx, gy, sd)
            }
        }
    }

    private func shadow(_ g: inout GraphicsContext, _ cam: Cam, _ gx: Double, _ gy: Double,
                        _ w: Double, _ h: Double) {
        let c = cam.p(gx, gy)
        g.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)),
               with: .color(.black.opacity(0.20 * (0.35 + 0.65 * cam.light))))
    }

    private func drawHouse(_ g: inout GraphicsContext, _ cam: Cam, _ gx: Double, _ gy: Double) {
        let x0 = gx - 0.62, x1 = gx + 0.62
        let y0 = gy - 0.62, y1 = gy + 0.62
        let h = 1.05, rh = 0.62

        shadow(&g, cam, gx, gy + 0.2, Cam.tw * 1.5, Cam.th * 1.5)

        g.fill(poly([cam.p(x1, y0, 0), cam.p(x1, y1, 0), cam.p(x1, y1, h), cam.p(x1, y0, h)]),
               with: .color(cam.col(Pal.wall, 0.66)))
        g.fill(poly([cam.p(x0, y1, 0), cam.p(x1, y1, 0), cam.p(x1, y1, h), cam.p(x0, y1, h)]),
               with: .color(cam.col(Pal.wall, 0.86)))

        let dc = cam.p(gx - 0.18, y1, 0)
        g.fill(poly([CGPoint(x: dc.x - 7, y: dc.y - 2),
                     CGPoint(x: dc.x + 7, y: dc.y + 5),
                     CGPoint(x: dc.x + 7, y: dc.y - 20),
                     CGPoint(x: dc.x - 7, y: dc.y - 27)]),
               with: .color(cam.col(Pal.wood, 0.8)))
        let wc = cam.p(x1, gy - 0.1, 0.62)
        g.fill(poly([CGPoint(x: wc.x - 8, y: wc.y - 6),
                     CGPoint(x: wc.x, y: wc.y - 10),
                     CGPoint(x: wc.x, y: wc.y + 4),
                     CGPoint(x: wc.x - 8, y: wc.y + 8)]),
               with: .color(cam.light > 0.25
                            ? cam.col(RGB(r: 0.62, g: 0.82, b: 0.95), 0.7)
                            : Color(red: 1.0, green: 0.86, blue: 0.45)))

        let ox0 = x0 - 0.12, ox1 = x1 + 0.12, oy0 = y0 - 0.12, oy1 = y1 + 0.12
        let mid = (ox0 + ox1) / 2
        g.fill(poly([cam.p(ox1, oy0, h), cam.p(ox1, oy1, h),
                     cam.p(mid, oy1, h + rh), cam.p(mid, oy0, h + rh)]),
               with: .color(cam.col(Pal.roof, 0.72)))
        g.fill(poly([cam.p(ox0, oy0, h), cam.p(ox0, oy1, h),
                     cam.p(mid, oy1, h + rh), cam.p(mid, oy0, h + rh)]),
               with: .color(cam.col(Pal.roof, 1.0)))
        var ridge = Path()
        ridge.move(to: cam.p(mid, oy0, h + rh))
        ridge.addLine(to: cam.p(mid, oy1, h + rh))
        g.stroke(ridge, with: .color(cam.col(Pal.roof.mul(0.75))), lineWidth: 2)

        let ch = cam.p(x1 - 0.22, y0 + 0.22, h + rh * 0.55)
        g.fill(Path(CGRect(x: ch.x - 5, y: ch.y - 22, width: 10, height: 22)),
               with: .color(cam.col(Pal.roof.mul(0.8), 0.85)))
        for k in 0..<4 {
            let t = (clock * 0.5 + Double(k) * 0.25).truncatingRemainder(dividingBy: 1)
            let r = 3 + t * 9
            let sx = ch.x + sin(t * 4 + Double(k)) * 8
            let sy = ch.y - 24 - t * 42
            g.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(0.30 * (1 - t))))
        }
    }

    private func drawTree(_ g: inout GraphicsContext, _ cam: Cam, _ gx: Double, _ gy: Double, _ seed: Double) {
        shadow(&g, cam, gx, gy, Cam.tw * 0.62, Cam.th * 0.62)
        let sway = sin(clock * 0.9 + seed * 6) * 1.6

        let b = cam.p(gx, gy, 0)
        let t = cam.p(gx, gy, 0.55)
        g.fill(poly([CGPoint(x: b.x - 4, y: b.y),
                     CGPoint(x: b.x + 4, y: b.y),
                     CGPoint(x: t.x + 3 + sway * 0.4, y: t.y),
                     CGPoint(x: t.x - 3 + sway * 0.4, y: t.y)]),
               with: .color(cam.col(Pal.wood, 0.85)))

        let cpts: [(Double, Double, Double)] = [(-11, 4, 15), (10, 2, 14), (0, -10, 18)]
        for (dx, dy, r) in cpts {
            let cx = t.x + dx + sway, cy = t.y + dy - 10
            g.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r * 0.9, width: r * 2, height: r * 1.8)),
                   with: .color(cam.col(Pal.leafLo)))
            g.fill(Path(ellipseIn: CGRect(x: cx - r * 0.72, y: cy - r * 0.95,
                                          width: r * 1.35, height: r * 1.2)),
                   with: .color(cam.col(Pal.leafHi)))
        }
    }

    private func drawFence(_ g: inout GraphicsContext, _ cam: Cam, _ gx: Double, _ gy: Double, _ side: Int) {
        let h = 0.34
        let a = cam.p(gx, gy, 0), at = cam.p(gx, gy, h)
        g.fill(poly([CGPoint(x: a.x - 2.5, y: a.y), CGPoint(x: a.x + 2.5, y: a.y),
                     CGPoint(x: at.x + 2.5, y: at.y), CGPoint(x: at.x - 2.5, y: at.y)]),
               with: .color(cam.col(Pal.fence, 0.9)))
        let nx = side == 0 ? gx + 1 : gx
        let ny = side == 0 ? gy : gy + 1
        guard nx <= Double(N) - 0.4, ny <= Double(N) - 0.4 else { return }
        for lvl in [0.30, 0.16] {
            let p0 = cam.p(gx, gy, lvl), p1 = cam.p(nx, ny, lvl)
            g.fill(poly([CGPoint(x: p0.x, y: p0.y - 2), CGPoint(x: p1.x, y: p1.y - 2),
                         CGPoint(x: p1.x, y: p1.y + 2), CGPoint(x: p0.x, y: p0.y + 2)]),
                   with: .color(cam.col(Pal.fence, 0.78)))
        }
    }

    private func drawCrop(_ g: inout GraphicsContext, _ cam: Cam, _ p: Plot) {
        guard p.planted || p.pop > 0 else { return }
        let base = cam.p(p.gx, p.gy, 0.10)

        if p.pop > 0 && !p.planted {
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi
                let d = (1 - p.pop) * 20 + 6
                let r = 2.5 * p.pop
                g.fill(Path(ellipseIn: CGRect(x: base.x + cos(a) * d - r,
                                              y: base.y + sin(a) * d * 0.55 - 10 - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(Color(red: 1, green: 0.95, blue: 0.6).opacity(p.pop)))
            }
            return
        }

        let gr = min(p.growth, 1.0)
        let scale = 0.35 + 0.65 * gr
        let sway = sin(clock * 1.6 + p.gx * 2 + p.gy) * 1.2 * scale

        switch p.kind {
        case .wheat:
            for k in -2...2 {
                let ox = Double(k) * 4.4
                let hgt = (10 + 16 * gr) * (1 - abs(Double(k)) * 0.08)
                var st = Path()
                st.move(to: CGPoint(x: base.x + ox, y: base.y))
                st.addQuadCurve(to: CGPoint(x: base.x + ox + sway, y: base.y - hgt),
                                control: CGPoint(x: base.x + ox + sway * 0.4, y: base.y - hgt * 0.6))
                g.stroke(st, with: .color(cam.col(gr >= 1 ? Pal.wheat.mul(0.85) : Pal.leafHi)),
                         lineWidth: 1.8)
                if gr > 0.5 {
                    let tipY = base.y - hgt
                    g.fill(Path(ellipseIn: CGRect(x: base.x + ox + sway - 2.4, y: tipY - 5,
                                                  width: 4.8, height: 9)),
                           with: .color(cam.col(gr >= 1 ? Pal.wheat : Pal.leafHi.mix(Pal.wheat, 0.4))))
                }
            }

        case .carrot:
            if gr >= 1 {
                g.fill(Path(ellipseIn: CGRect(x: base.x - 5, y: base.y - 7, width: 10, height: 9)),
                       with: .color(cam.col(Pal.carrot)))
                g.fill(Path(ellipseIn: CGRect(x: base.x - 3, y: base.y - 6, width: 4, height: 5)),
                       with: .color(cam.col(Pal.carrot.mul(1.18))))
            }
            for k in -2...2 {
                let a = Double(k) * 0.34
                let L = (9 + 15 * gr)
                var lf = Path()
                lf.move(to: CGPoint(x: base.x, y: base.y - 4))
                lf.addQuadCurve(to: CGPoint(x: base.x + sin(a) * L + sway, y: base.y - 4 - cos(a) * L),
                                control: CGPoint(x: base.x + sin(a) * L * 0.3,
                                                 y: base.y - 4 - cos(a) * L * 0.75))
                g.stroke(lf, with: .color(cam.col(Pal.leafHi)), lineWidth: 2.4)
            }

        case .pumpkin:
            var vine = Path()
            vine.move(to: CGPoint(x: base.x - 13, y: base.y + 1))
            vine.addQuadCurve(to: CGPoint(x: base.x + 13, y: base.y + 1),
                              control: CGPoint(x: base.x, y: base.y - 9 - 4 * gr))
            g.stroke(vine, with: .color(cam.col(Pal.leafLo)), lineWidth: 2.2)
            for k in [-1.0, 1.0] {
                g.fill(Path(ellipseIn: CGRect(x: base.x + k * 11 - 5, y: base.y - 8, width: 10, height: 7)),
                       with: .color(cam.col(Pal.leafHi)))
            }
            let r = (3 + 8 * gr)
            g.fill(Path(ellipseIn: CGRect(x: base.x - r, y: base.y - r * 1.5,
                                          width: r * 2, height: r * 1.6)),
                   with: .color(cam.col(gr >= 1 ? Pal.pumpkin : Pal.leafHi.mix(Pal.pumpkin, gr))))
            if gr > 0.55 {
                for k in [-0.45, 0.0, 0.45] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: base.x + k * r * 1.3, y: base.y - r * 1.45))
                    rib.addQuadCurve(to: CGPoint(x: base.x + k * r * 1.3, y: base.y),
                                     control: CGPoint(x: base.x + k * r * 1.9, y: base.y - r * 0.7))
                    g.stroke(rib, with: .color(.black.opacity(0.12)), lineWidth: 1.2)
                }
                g.fill(Path(CGRect(x: base.x - 1.5, y: base.y - r * 1.5 - 5, width: 3, height: 6)),
                       with: .color(cam.col(Pal.leafLo)))
            }
        }

        if p.isRipe {
            let bob = sin(clock * 2.6 + p.gx) * 2
            let t = cam.p(p.gx, p.gy, 0.95)
            for k in 0..<4 {
                let a = Double(k) / 4 * 2 * .pi + clock
                let r = 1.8
                g.fill(Path(ellipseIn: CGRect(x: t.x + cos(a) * 8 - r, y: t.y + bob + sin(a) * 4 - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(Color(red: 1, green: 0.95, blue: 0.55).opacity(0.9)))
            }
        } else if p.isThirsty {
            let t = cam.p(p.gx, p.gy, 0.85)
            let bob = sin(clock * 3 + p.gy) * 2
            var d = Path()
            d.move(to: CGPoint(x: t.x, y: t.y + bob - 7))
            d.addQuadCurve(to: CGPoint(x: t.x + 4, y: t.y + bob + 1),
                           control: CGPoint(x: t.x + 4.5, y: t.y + bob - 3))
            d.addQuadCurve(to: CGPoint(x: t.x - 4, y: t.y + bob + 1),
                           control: CGPoint(x: t.x, y: t.y + bob + 5))
            d.addQuadCurve(to: CGPoint(x: t.x, y: t.y + bob - 7),
                           control: CGPoint(x: t.x - 4.5, y: t.y + bob - 3))
            g.fill(d, with: .color(Color(red: 0.45, green: 0.78, blue: 1.0).opacity(0.85)))
        }
    }

    private func drawChicken(_ g: inout GraphicsContext, _ cam: Cam, _ ch: Chicken) {
        let f: Double = ch.facingLeft ? -1 : 1
        let hop = ch.pause > 0 ? 0 : abs(sin(ch.bob)) * 2.5
        shadow(&g, cam, ch.gx, ch.gy, 18, 9)
        let b = cam.p(ch.gx, ch.gy, 0)
        let y = b.y - hop

        for k in [-2.5, 2.5] {
            var l = Path()
            l.move(to: CGPoint(x: b.x + k, y: y - 3))
            l.addLine(to: CGPoint(x: b.x + k, y: b.y))
            g.stroke(l, with: .color(cam.col(Pal.beak, 0.85)), lineWidth: 1.6)
        }
        g.fill(Path(ellipseIn: CGRect(x: b.x - 8, y: y - 14, width: 16, height: 12)),
               with: .color(cam.col(Pal.hen)))
        g.fill(Path(ellipseIn: CGRect(x: b.x - 4 * f - 4, y: y - 11, width: 8, height: 6)),
               with: .color(cam.col(Pal.hen.mul(0.90))))
        g.fill(poly([CGPoint(x: b.x - 7 * f, y: y - 13),
                     CGPoint(x: b.x - 13 * f, y: y - 18),
                     CGPoint(x: b.x - 7 * f, y: y - 8)]),
               with: .color(cam.col(Pal.hen.mul(0.93))))
        g.fill(Path(ellipseIn: CGRect(x: b.x + 3 * f - 4.5, y: y - 22, width: 9, height: 9)),
               with: .color(cam.col(Pal.hen)))
        g.fill(Path(ellipseIn: CGRect(x: b.x + 3 * f - 3, y: y - 25, width: 6, height: 4)),
               with: .color(cam.col(Pal.comb)))
        g.fill(poly([CGPoint(x: b.x + 7 * f, y: y - 18),
                     CGPoint(x: b.x + 12 * f, y: y - 17),
                     CGPoint(x: b.x + 7 * f, y: y - 15.5)]),
               with: .color(cam.col(Pal.beak)))
        g.fill(Path(ellipseIn: CGRect(x: b.x + 4.5 * f - 1, y: y - 20, width: 1.8, height: 1.8)),
               with: .color(.black.opacity(0.75)))
    }

    private func drawFarmer(_ g: inout GraphicsContext, _ cam: Cam) {
        let f: Double = farmer.facingLeft ? -1 : 1
        let walking = farmer.target != nil && farmer.work <= 0
        let bounce = walking ? abs(sin(farmer.step)) * 3 : 0
        let working = farmer.work > 0 ? sin(farmer.step * 1.6) * 6 : 0

        shadow(&g, cam, farmer.gx, farmer.gy, 20, 10)
        let b = cam.p(farmer.gx, farmer.gy, 0)
        let y = b.y - bounce

        let swing = walking ? sin(farmer.step) * 3 : 0
        for (i, k) in [-3.0, 3.0].enumerated() {
            let off = i == 0 ? swing : -swing
            g.fill(Path(roundedRect: CGRect(x: b.x + k - 2.5, y: y - 14, width: 5, height: 14 + off),
                        cornerRadius: 2),
                   with: .color(cam.col(Pal.jeans)))
        }
        g.fill(Path(roundedRect: CGRect(x: b.x - 7, y: y - 28, width: 14, height: 16),
                    cornerRadius: 5),
               with: .color(cam.col(Pal.shirt)))
        g.fill(Path(CGRect(x: b.x - 4, y: y - 24, width: 2, height: 12)),
               with: .color(cam.col(Pal.jeans, 1.05)))
        g.fill(Path(CGRect(x: b.x + 2, y: y - 24, width: 2, height: 12)),
               with: .color(cam.col(Pal.jeans, 1.05)))
        var arm = Path()
        arm.move(to: CGPoint(x: b.x + 6 * f, y: y - 25))
        arm.addLine(to: CGPoint(x: b.x + (11 + working * 0.5) * f, y: y - 17 + working))
        g.stroke(arm, with: .color(cam.col(Pal.shirt, 0.92)), lineWidth: 4)
        g.fill(Path(ellipseIn: CGRect(x: b.x + (11 + working * 0.5) * f - 2.2, y: y - 19 + working,
                                      width: 4.4, height: 4.4)),
               with: .color(cam.col(Pal.skin)))
        g.fill(Path(ellipseIn: CGRect(x: b.x - 6, y: y - 40, width: 12, height: 12)),
               with: .color(cam.col(Pal.skin)))
        g.fill(Path(ellipseIn: CGRect(x: b.x - 11, y: y - 36, width: 22, height: 7)),
               with: .color(cam.col(Pal.straw)))
        g.fill(Path(ellipseIn: CGRect(x: b.x - 6, y: y - 43, width: 12, height: 10)),
               with: .color(cam.col(Pal.straw.mul(1.04))))
        g.fill(Path(ellipseIn: CGRect(x: b.x + 2.2 * f - 0.9, y: y - 33, width: 1.8, height: 1.8)),
               with: .color(.black.opacity(0.7)))

        if farmer.work > 0 {
            var tool = Path()
            tool.move(to: CGPoint(x: b.x + 10 * f, y: y - 20 + working))
            tool.addLine(to: CGPoint(x: b.x + 16 * f, y: y - 4 + working))
            g.stroke(tool, with: .color(cam.col(Pal.wood)), lineWidth: 2.4)
        }

        if !farmer.say.isEmpty {
            let t = cam.p(farmer.gx, farmer.gy, 2.3)
            let r = CGRect(x: t.x - 15, y: t.y - 16, width: 30, height: 24)
            g.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(.white.opacity(0.92)))
            g.fill(poly([CGPoint(x: t.x - 4, y: t.y + 7),
                         CGPoint(x: t.x + 4, y: t.y + 7),
                         CGPoint(x: t.x, y: t.y + 14)]),
                   with: .color(.white.opacity(0.92)))
            g.draw(Text(farmer.say).font(.system(size: 15)), at: CGPoint(x: t.x, y: t.y - 4))
        }
    }

    // MARK: - Weather / night

    private func drawRain(_ g: inout GraphicsContext, _ size: CGSize) {
        guard !drops.isEmpty else { return }
        for d in drops {
            var p = Path()
            p.move(to: CGPoint(x: d.x, y: d.y))
            p.addLine(to: CGPoint(x: d.x - 2.5, y: d.y + 12))
            g.stroke(p, with: .color(Color(red: 0.75, green: 0.87, blue: 1.0).opacity(0.5)),
                     lineWidth: 1.5)
        }
    }

    private func drawFireflies(_ g: inout GraphicsContext, _ size: CGSize) {
        let a = clamp01((0.18 - light) / 0.18)
        guard a > 0.02 else { return }
        for f in fireflies {
            let pulse = 0.3 + 0.7 * abs(sin(clock * 2.2 + f.phase))
            for (r, o) in [(5.5, 0.16), (2.3, 0.95)] {
                g.fill(Path(ellipseIn: CGRect(x: f.x - r, y: f.y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(red: 1, green: 0.95, blue: 0.5).opacity(a * pulse * o)))
            }
        }
    }

    private func drawNight(_ g: inout GraphicsContext, _ size: CGSize) {
        let a = 0.34 * (1 - light)
        guard a > 0.01 else { return }
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .color(Color(red: 0.03, green: 0.05, blue: 0.18).opacity(a)))
    }

    // MARK: - HUD

    private func hud(size: CGSize) -> some View {
        VStack {
            HStack(spacing: 8) {
                pill("Day \(world.day)")
                pill("\(weather.icon) \(weather.label)")
                pill(world.timeString())
                Spacer()
                pill("🪙 \(world.coins)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 60)

            Spacer()

            HStack(spacing: 8) {
                pill("🌱 \(plots.filter { $0.planted && !$0.isRipe }.count) growing")
                pill("✨ \(plots.filter { $0.isRipe }.count) ripe")
                pill("🧺 \(world.harvested)")
            }
            .padding(.bottom, 34)
        }
        .allowsHitTesting(false)
    }

    private func pill(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}
