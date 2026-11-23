// SPDX-License-Identifier: GPL-3.0-only
// The EQ's curve, as EQ Studio's page draws it: 20 Hz to 20 kHz on a log scale, the dB range following
// the curve and the dots (12 to 30 dB, in steps of 6) but standing still through a drag. Drag a dot to
// move its band, pinch for the picked band's Q, double-tap to add a band there.
import EQCore
import SwiftUI

struct GraphView: View {
    @Environment(Studio.self) private var studio
    var interactive = true

    @State private var dragging: Band.ID?
    @State private var frozenRange: Double?
    @State private var pinchQ: Double?

    private static let gap = EdgeInsets(top: 10, leading: 34, bottom: 22, trailing: 10)
    private static let freqLines: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    private static let reach: CGFloat = 30
    private static let freqs: [Double] = (0..<240).map { pow(10, logLow + logSpan * Double($0) / 239) }
    private static let logLow = log10(EQ.freqMin)
    private static let logSpan = log10(EQ.freqMax) - log10(EQ.freqMin)

    private struct Scale {
        let rect: CGRect
        let range: Double
        func x(_ f: Double) -> CGFloat { rect.minX + rect.width * CGFloat((log10(f) - GraphView.logLow) / GraphView.logSpan) }
        func y(_ db: Double) -> CGFloat { rect.midY - rect.height / 2 * CGFloat(db / range) }
        func freq(_ x: CGFloat) -> Double { pow(10, GraphView.logLow + Double((x - rect.minX) / rect.width) * GraphView.logSpan) }
        func db(_ y: CGFloat) -> Double { Double((rect.midY - y) / (rect.height / 2)) * range }
    }

    private func rangeFor(_ points: [(left: Double, right: Double)]) -> Double {
        var most = 0.0
        for p in points { most = max(most, abs(p.left), abs(p.right)) }
        for b in studio.preset.bands where b.on { most = max(most, abs(b.gain)) }
        return min(max(ceil((most + 1) / 6) * 6, 12), 30)
    }

    var body: some View {
        let preset = studio.preset
        let freqs = GraphView.freqs
        let points = responses(preset, at: freqs)
        let range = frozenRange ?? rangeFor(points)
        let split = points.contains { abs($0.left - $0.right) > 0.01 }

        GeometryReader { geo in
            let g = GraphView.gap
            let s = Scale(rect: CGRect(x: g.leading, y: g.top, width: max(geo.size.width - g.leading - g.trailing, 1),
                                       height: max(geo.size.height - g.top - g.bottom, 1)), range: range)
            ZStack {
                Canvas { ctx, size in
                    drawGrid(ctx, s)
                    if studio.showEachBand {
                        for (i, b) in preset.bands.enumerated() where b.on && b.gain != 0 {
                            var path = Path()
                            for (k, f) in freqs.enumerated() {
                                let pt = CGPoint(x: s.x(f), y: s.y(bandResponse(b, at: f)))
                                k == 0 ? path.move(to: pt) : path.addLine(to: pt)
                            }
                            ctx.stroke(path, with: .color(BandColor.of(i).opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    let curve = { (side: KeyPath<(left: Double, right: Double), Double>) -> Path in
                        var path = Path()
                        for (k, f) in freqs.enumerated() {
                            let pt = CGPoint(x: s.x(f), y: s.y(min(max(points[k][keyPath: side], -range), range)))
                            k == 0 ? path.move(to: pt) : path.addLine(to: pt)
                        }
                        return path
                    }
                    let left = curve(\.left)
                    var fill = left
                    fill.addLine(to: CGPoint(x: s.rect.maxX, y: s.y(0)))
                    fill.addLine(to: CGPoint(x: s.rect.minX, y: s.y(0)))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.04)]),
                                                         startPoint: CGPoint(x: 0, y: s.rect.minY), endPoint: CGPoint(x: 0, y: s.y(0))))
                    if split {
                        ctx.stroke(curve(\.right), with: .color(.pink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ctx.stroke(left, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    drawDots(ctx, s, preset)
                }
                if split {
                    HStack(spacing: 10) {
                        Label("Left", systemImage: "circle.fill").foregroundStyle(Color.accentColor)
                        Label("Right", systemImage: "circle.fill").foregroundStyle(.pink)
                    }
                    .font(.caption2.weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 14).padding(.trailing, 14)
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                // Each dot is a handle a finger can take (44 pt): only a drag that starts on one moves a
                // band, so a swipe anywhere else on the graph scrolls the page.
                if interactive {
                    ForEach(preset.bands) { b in
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .position(x: s.x(b.freq), y: s.y(min(max(b.gain, -s.range), s.range)))
                            .gesture(handleDrag(b.id, s))
                            .accessibilityHidden(true)
                    }
                }
            }
            .coordinateSpace(.named("graph"))
            .contentShape(Rectangle())
            .simultaneousGesture(interactive ? pinchGesture : nil)
            .simultaneousGesture(interactive ? doubleTap(s) : nil)
            .sensoryFeedback(.selection, trigger: studio.selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EQ curve")
            .accessibilityValue(accessibilitySummary(preset))
        }
    }

    private func accessibilitySummary(_ p: Preset) -> String {
        let active = p.bands.filter { $0.on && $0.gain != 0 }
        if active.isEmpty { return "Flat" }
        return active.map { "\(Format.hertz($0.freq)) \(Format.dB($0.gain))" }.joined(separator: ", ")
    }

    private func drawGrid(_ ctx: GraphicsContext, _ s: Scale) {
        let line = Color.secondary.opacity(0.18)
        for f in GraphView.freqLines {
            var p = Path()
            p.move(to: CGPoint(x: s.x(f), y: s.rect.minY))
            p.addLine(to: CGPoint(x: s.x(f), y: s.rect.maxY))
            ctx.stroke(p, with: .color(line), lineWidth: 0.5)
            ctx.draw(Text(Format.gridHertz(f)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary),
                     at: CGPoint(x: s.x(f), y: s.rect.maxY + 11))
        }
        var db = -s.range
        while db <= s.range + 0.01 {
            var p = Path()
            p.move(to: CGPoint(x: s.rect.minX, y: s.y(db)))
            p.addLine(to: CGPoint(x: s.rect.maxX, y: s.y(db)))
            ctx.stroke(p, with: .color(db == 0 ? Color.secondary.opacity(0.5) : line), lineWidth: db == 0 ? 1 : 0.5)
            let label = db == 0 ? "0" : (db > 0 ? "+\(Int(db))" : "−\(Int(-db))")
            ctx.draw(Text(label).font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary),
                     at: CGPoint(x: s.rect.minX - 6, y: s.y(db)), anchor: .trailing)
            db += 6
        }
    }

    private func drawDots(_ ctx: GraphicsContext, _ s: Scale, _ preset: Preset) {
        for (i, b) in preset.bands.enumerated() {
            let picked = b.id == studio.selected
            let c = CGPoint(x: s.x(b.freq), y: s.y(min(max(b.gain, -s.range), s.range)))
            let r: CGFloat = picked ? 9 : 6.5
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            let colour = BandColor.of(i)
            if picked {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(colour.opacity(0.22)))
            }
            ctx.fill(Path(ellipseIn: rect), with: .color(b.on ? colour : Color.secondary.opacity(0.5)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: picked ? 2 : 1.25)
            if picked {
                ctx.draw(Text("\(i + 1)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white), at: c)
            }
        }
    }

    private func nearest(_ p: CGPoint, _ s: Scale) -> Band.ID? {
        var best: (Band.ID, CGFloat)?
        for b in studio.preset.bands {
            let d = hypot(s.x(b.freq) - p.x, s.y(min(max(b.gain, -s.range), s.range)) - p.y)
            if d < GraphView.reach, d < (best?.1 ?? .infinity) { best = (b.id, d) }
        }
        return best?.0
    }

    /// A dot's own drag: its band follows the finger, the dB range held still until it lets go.
    private func handleDrag(_ id: Band.ID, _ s: Scale) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("graph"))
            .onChanged { v in
                if dragging == nil {
                    dragging = id
                    studio.selected = id
                    frozenRange = s.range
                }
                guard dragging == id, let i = studio.band(id), hypot(v.translation.width, v.translation.height) > 2 else { return }
                let knob = Knob.of(studio.preset.bands[i]) != nil
                let freq = min(max(s.freq(v.location.x), EQ.freqMin), EQ.freqMax)
                let gain = min(max(s.db(v.location.y), -EQ.gainMax), EQ.gainMax)
                studio.change("drag-\(id)") { p in
                    guard let k = p.bands.firstIndex(where: { $0.id == id }) else { return }
                    if !knob { p.bands[k].freq = (freq * 100).rounded() / 100 }
                    p.bands[k].gain = knob ? min(max((gain * 10).rounded() / 10, 0), Knob.maxGain) : (gain * 10).rounded() / 10
                }
            }
            .onEnded { _ in
                dragging = nil
                frozenRange = nil
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard let i = studio.band(studio.selected), Knob.of(studio.preset.bands[i]) == nil else { return }
                let id = studio.preset.bands[i].id
                if pinchQ == nil { pinchQ = studio.preset.bands[i].q }
                // Spread the fingers for a wider band (a lower Q), as a pinch zooms out.
                let q = min(max(pinchQ! / Double(v.magnification), EQ.qMin), EQ.qMax)
                studio.change("q-\(id)") { p in
                    if let k = p.bands.firstIndex(where: { $0.id == id }) { p.bands[k].q = (q * 100).rounded() / 100 }
                }
            }
            .onEnded { _ in pinchQ = nil }
    }

    private func doubleTap(_ s: Scale) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { v in
            guard nearest(v.location, s) == nil, s.rect.contains(v.location) else { return }
            studio.addBand(freq: (s.freq(v.location.x)).rounded(), gain: (s.db(v.location.y) * 10).rounded() / 10)
        }
    }
}
