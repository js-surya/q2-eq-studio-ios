// SPDX-License-Identifier: GPL-3.0-only
// The EQ's curve, as EQ Studio's page draws it: 20 Hz to 20 kHz on a log scale, the dB range following
// the curve and the dots (12 to 30 dB, in steps of 6) but standing still through a drag. Drag a dot to
// move its band, double-tap to add a band there, touch and hold to read the curve.
import EQCore
import SwiftUI

struct GraphView: View {
    @Environment(Studio.self) private var studio
    var interactive = true

    @State private var dragging: Band.ID?
    @State private var frozenRange: Double?
    @State private var pull: Pull? // the band a pull on the curve took, and where it started

    private struct Pull {
        let id: Band.ID
        let freq, gain: Double
    }

    private static let gap = EdgeInsets(top: 10, leading: 34, bottom: 22, trailing: 10)
    private static let freqLines: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    private static let reach: CGFloat = 30
    private static var freqs: [Double] { Plot.freqs }
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

    /// The graph's reach follows the curve and the dots, but stands still through a drag. Under a
    /// measurement it's ±30 dB, near squig.link's 55 dB window, so an earphone looks as it does there.
    private func rangeFor(_ points: [(left: Double, right: Double)], measured: Bool) -> Double {
        if measured { return 30 }
        var most = 0.0
        for p in points { most = max(most, abs(p.left), abs(p.right)) }
        for b in studio.preset.bands where b.on { most = max(most, abs(b.gain)) }
        return min(max(ceil((most + 1) / 6) * 6, 12), 30)
    }

    /// For the picture of the graph: its title, a legend and its own background, nothing to touch.
    var still = false
    /// In a list's row (Presets, Response), whose background is the row's.
    var inRow = false
    @State private var hover: CGPoint?
    /// Touch and hold: the curve read while the finger stays down, where it is.
    @State private var holding: CGPoint?

    var body: some View {
        let preset = studio.preset
        let rate = studio.rate
        let freqs = GraphView.freqs
        let points = still ? responses(preset, at: freqs, rate: rate) : studio.curve
        let shown = still ? nil : studio.response.shown
        let aim = still ? nil : studio.response.shownTarget
        let measured = shown == nil ? nil : studio.response.measuredLine
        let targetLine = aim == nil ? nil : studio.response.targetLine
        let range = frozenRange ?? rangeFor(points, measured: shown != nil)
        let split = points.contains { abs($0.left - $0.right) > 0.01 }
        let faded = !still && studio.live.on && studio.live.mode != "peq" // the Q2 isn't playing it
        let picked = still ? nil : studio.band(studio.selected)
        let edits = interactive && studio.graphEdit // drags and double-taps: only with the pencil on

        GeometryReader { geo in
            let g = still ? EdgeInsets(top: 46, leading: 40, bottom: 30, trailing: 24) : GraphView.gap
            let s = Scale(rect: CGRect(x: g.leading, y: g.top, width: max(geo.size.width - g.leading - g.trailing, 1),
                                       height: max(geo.size.height - g.top - g.bottom, 1)), range: range)
            // What the drawing needs, taken here: it's drawn off the main thread, so it reads none of the
            // studio or the view's state itself.
            let eachBand = studio.showEachBand
            let crossing = dragging != nil
            let pointer = holding
            let dots = Dots(picked: picked, hovered: still || dragging != nil ? nil : hover.flatMap { nearest($0, s) }, background: dotBackground)
            ZStack {
                // Drawn off the main thread on screen: beside the band inspector a drag otherwise waited on
                // it. The picture is drawn at once, for the image made of it.
                Canvas(rendersAsynchronously: !still) { ctx, size in
                    drawGrid(ctx, s)
                    let line = { (values: [Double]) -> Path in
                        var path = Path()
                        for (k, f) in freqs.enumerated() {
                            let pt = CGPoint(x: s.x(f), y: s.y(min(max(values[k], -range), range)))
                            k == 0 ? path.move(to: pt) : path.addLine(to: pt)
                        }
                        return path
                    }
                    // The measurement as measured, faint, and its target dashed.
                    if let measured {
                        ctx.stroke(line(measured), with: .color(.secondary.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        if let targetLine {
                            ctx.stroke(line(targetLine), with: .color(.secondary.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [7, 5]))
                        }
                    }
                    var eqCtx = ctx
                    if faded { eqCtx.opacity = 0.4 }
                    if eachBand {
                        for (i, b) in preset.bands.enumerated() where b.on && b.gain != 0 && i != picked {
                            eqCtx.stroke(line(freqs.map { bandResponse(b, at: $0, rate: rate) }), with: .color(BandColor.of(b).opacity(0.55)),
                                         style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
                        }
                    }
                    // The picked band's own curve, dashed over a faint fill.
                    if let picked, preset.bands[picked].on, preset.bands[picked].gain != 0 {
                        let own = line(freqs.map { bandResponse(preset.bands[picked], at: $0, rate: rate) })
                        var fill = own
                        fill.addLine(to: CGPoint(x: s.rect.maxX, y: s.y(0)))
                        fill.addLine(to: CGPoint(x: s.rect.minX, y: s.y(0)))
                        fill.closeSubpath()
                        eqCtx.fill(fill, with: .color(.secondary.opacity(0.18)))
                        eqCtx.stroke(own, with: .color(BandColor.faint), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    let left = line(points.map(\.left))
                    if !split {
                        // The area between the curve and 0 dB, evenly, as the page shades it.
                        var fill = left
                        fill.addLine(to: CGPoint(x: s.x(EQ.freqMax), y: s.y(0)))
                        fill.addLine(to: CGPoint(x: s.x(EQ.freqMin), y: s.y(0)))
                        fill.closeSubpath()
                        eqCtx.fill(fill, with: .color(BandColor.accent.opacity(measured == nil ? 0.14 : 0.1)))
                    } else {
                        eqCtx.stroke(line(points.map(\.right)), with: .color(BandColor.right), style: StrokeStyle(lineWidth: measured == nil ? 2.5 : 2, lineCap: .round, lineJoin: .round))
                    }
                    eqCtx.stroke(left, with: .color(BandColor.accent), style: StrokeStyle(lineWidth: measured == nil ? 2.5 : 2, lineCap: .round, lineJoin: .round))
                    // The measurement with the EQ, bold: what you'd hear.
                    if let measured {
                        eqCtx.stroke(line(zip(measured, points).map { $0 + $1.left }), with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        if split {
                            eqCtx.stroke(line(zip(measured, points).map { $0 + $1.right }), with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round, dash: [6, 4]))
                        }
                    }
                    if let picked, crossing {
                        let b = preset.bands[picked]
                        let c = CGPoint(x: s.x(b.freq), y: s.y(min(max(b.gain, -range), range)))
                        var cross = Path()
                        cross.move(to: CGPoint(x: c.x, y: s.rect.minY)); cross.addLine(to: CGPoint(x: c.x, y: s.rect.maxY))
                        cross.move(to: CGPoint(x: s.rect.minX, y: c.y)); cross.addLine(to: CGPoint(x: s.rect.maxX, y: c.y))
                        ctx.stroke(cross, with: .color(BandColor.of(b).opacity(0.35)), lineWidth: 1)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)), with: .color(BandColor.of(b).opacity(0.18)))
                    }
                    drawDots(ctx, s, preset, dots)
                    // Touch and hold: a line where the finger is, and a dot on each side's curve there.
                    if let h = pointer, s.rect.contains(h) {
                        var v = Path()
                        v.move(to: CGPoint(x: h.x, y: s.rect.minY)); v.addLine(to: CGPoint(x: h.x, y: s.rect.maxY))
                        ctx.stroke(v, with: .color(.primary.opacity(0.5)), lineWidth: 1)
                        let r = response(preset, at: s.freq(h.x), rate: rate)
                        for (gain, colour) in split ? [(r.left, BandColor.accent), (r.right, BandColor.right)] : [(r.left, BandColor.accent)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: h.x - 4, y: s.y(min(max(gain, -range), range)) - 4, width: 8, height: 8)), with: .color(colour))
                        }
                    }
                    if still {
                        ctx.draw(Text(preset.name.isEmpty ? EQ.fallbackName : preset.name).font(.system(size: 17, weight: .semibold)),
                                 at: CGPoint(x: s.rect.minX, y: 22), anchor: .leading)
                        let n = preset.bands.count
                        let words = "\(n) \(n == 1 ? "band" : "bands") · drawn at \(Format.hertz(rate))"
                        ctx.draw(Text(split ? "\(words) · left blue, right orange" : words).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary),
                                 at: CGPoint(x: size.width - g.trailing, y: 22), anchor: .trailing)
                    }
                }
                if split {
                    HStack(spacing: 10) {
                        Label("Left", systemImage: "circle.fill").foregroundStyle(BandColor.accent)
                        Label("Right", systemImage: "circle.fill").foregroundStyle(BandColor.right)
                    }
                    .font(.caption2.weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.thinMaterial, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, still ? 48 : 14).padding(.trailing, 28)
                    .allowsHitTesting(false)
                }
                if let h = holding, s.rect.contains(h), !still {
                    let f = s.freq(h.x)
                    let r = response(preset, at: f, rate: rate)
                    let m = shown.map { Squig.at($0.points, f) }
                    let text = "\(Format.hertz(f))   \(split ? "L \(Format.dB(r.left)) · R \(Format.dB(r.right))" : Format.dB(r.left))"
                        + (m.map { "   Measured + EQ \(Format.dB($0 + r.left))" } ?? "")
                    Text(text)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
            .background { if still { Color(white: 0.98) } }
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = p } else { hover = nil }
            }
            .overlay {
                // The curve itself can be taken: a band of touch along the line (36 pt) pulls the band
                // that shapes it most there. Off the line the page scrolls.
                if edits {
                    let band = CurveBand(points: stride(from: 0, to: freqs.count, by: 4).map { k in
                        CGPoint(x: s.x(freqs[k]), y: s.y(min(max(points[k].left, -range), range)))
                    })
                    Color.clear
                    .contentShape(band)
                    .gesture(curveDrag(s))
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                // Each dot is a handle a finger can take (44 pt): only a drag that starts on one moves a
                // band, so a swipe anywhere else on the graph scrolls the page.
                if edits {
                    ForEach(preset.bands) { b in
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .position(x: s.x(b.freq), y: s.y(min(max(b.gain, -s.range), s.range)))
                            .gesture(handleDrag(b.id, s))
                            .accessibilityHidden(true)
                    }
                } else if interactive {
                    // Locked, a tap on a dot still picks its band, for the card: picking changes nothing.
                    ForEach(preset.bands) { b in
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .position(x: s.x(b.freq), y: s.y(min(max(b.gain, -s.range), s.range)))
                            .onTapGesture { studio.selected = b.id }
                            .accessibilityHidden(true)
                    }
                }
            }
            .coordinateSpace(.named("graph"))
            .contentShape(Rectangle())
            .simultaneousGesture(edits ? doubleTap(s) : nil)
            .gesture(interactive ? holdToInspect(s) : nil) // reading the curve works locked too
            .sensoryFeedback(trigger: studio.selected) { _, new in new == nil ? nil : .impact(weight: .light, intensity: 0.6) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EQ curve")
            .accessibilityValue(accessibilitySummary(preset))
            // After the curve's own element, so the pencil is a button of its own to VoiceOver, not hidden in it
            .overlay(alignment: .topTrailing) { if interactive { EditToggle(on: studio.graphEdit) { studio.toggleGraphEdit() } } }
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
            db += s.range <= 6 ? 2 : 6
        }
    }

    /// What the dots need besides the bands: the picked one, the one under the pointer, the ground.
    private struct Dots {
        let picked: Int?
        let hovered: Band.ID?
        let background: Color
    }

    /// The dots, as the page draws them: each a ring in its band's colour with its number, dashed when
    /// off; the picked one filled, on top; the one under the pointer ringed.
    private func drawDots(_ ctx: GraphicsContext, _ s: Scale, _ preset: Preset, _ dots: Dots) {
        let pickedIndex = dots.picked, hovered = dots.hovered, dotBackground = dots.background
        var order = preset.bands.indices.filter { $0 != pickedIndex }
        if let pickedIndex { order.append(pickedIndex) }
        for i in order {
            let b = preset.bands[i]
            let picked = i == pickedIndex
            let c = CGPoint(x: s.x(b.freq), y: s.y(min(max(b.gain, -s.range), s.range)))
            let r: CGFloat = picked ? 12 : 9
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            let colour = BandColor.of(b)
            if b.id == hovered {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(colour.opacity(0.22)))
            }
            if picked {
                ctx.fill(Path(ellipseIn: rect), with: .color(BandColor.picked(b)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(dotBackground), lineWidth: 2)
                ctx.draw(Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white), at: c)
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(dotBackground))
                ctx.stroke(Path(ellipseIn: rect), with: .color(colour), style: StrokeStyle(lineWidth: 2, dash: b.on ? [] : [3, 3]))
                ctx.draw(Text("\(i + 1)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(colour), at: c)
            }
        }
    }

    /// The graph's own background, which a ring's middle shows.
    private var dotBackground: Color { still ? Color(white: 0.98) : inRow ? Color.rowBackground : Color.groupedBackground }

    private func nearest(_ p: CGPoint, _ s: Scale) -> Band.ID? {
        var best: (Band.ID, CGFloat)?
        for b in studio.preset.bands {
            let d = hypot(s.x(b.freq) - p.x, s.y(min(max(b.gain, -s.range), s.range)) - p.y)
            if d < GraphView.reach, d < (best?.1 ?? .infinity) { best = (b.id, d) }
        }
        return best?.0
    }

    /// Which band a touch on the curve at f belongs to: the one whose own curve is loudest there, or,
    /// where none changes the sound much, the nearest by frequency.
    private func bandAt(_ f: Double) -> Band.ID? {
        let bands = studio.preset.bands.filter(\.on)
        if let loud = bands.max(by: { abs(bandResponse($0, at: f)) < abs(bandResponse($1, at: f)) }),
           abs(bandResponse(loud, at: f)) > 0.5 {
            return loud.id
        }
        return studio.preset.bands.min(by: { abs(log10($0.freq / f)) < abs(log10($1.freq / f)) })?.id
    }

    /// A pull on the curve: the band under it moves by as much as the finger, up and down its gain,
    /// along its frequency (a Bass or Treble knob only up and down).
    private func curveDrag(_ s: Scale) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("graph"))
            .onChanged { v in
                if pull == nil {
                    guard let id = bandAt(s.freq(v.startLocation.x)), let i = studio.band(id) else { return }
                    let b = studio.preset.bands[i]
                    pull = Pull(id: id, freq: b.freq, gain: b.gain)
                    studio.buzz(.light)
                    dragging = id
                    studio.selected = id
                    frozenRange = s.range
                }
                guard let p = pull, let i = studio.band(p.id), hypot(v.translation.width, v.translation.height) > 2 else { return }
                let knob = Knob.of(studio.preset.bands[i]) != nil
                let dGain = s.db(v.location.y) - s.db(v.startLocation.y)
                let ratio = s.freq(v.location.x) / s.freq(v.startLocation.x)
                let gain = min(max(p.gain + dGain, knob ? 0 : -EQ.gainMax), knob ? Knob.maxGain : EQ.gainMax)
                let freq = min(max(p.freq * ratio, EQ.freqMin), EQ.freqMax)
                let before = studio.preset.bands[i]
                studio.change("drag-\(p.id)") { preset in
                    guard let k = preset.bands.firstIndex(where: { $0.id == p.id }) else { return }
                    if !knob { preset.bands[k].freq = (freq * 100).rounded() / 100 }
                    preset.bands[k].gain = (gain * 10).rounded() / 10
                }
                if let j = studio.band(p.id) { detents(before, studio.preset.bands[j], knob: knob) }
            }
            .onEnded { _ in
                pull = nil
                dragging = nil
                frozenRange = nil
            }
    }


    /// The detents a move passes: a tick each whole dB and each grid frequency, a bump at 0 dB, a buzz at
    /// the ends. old and new are the band before and after.
    private func detents(_ old: Band, _ new: Band, knob: Bool) {
        let top = knob ? Knob.maxGain : EQ.gainMax, bottom = knob ? 0 : -EQ.gainMax
        if (new.gain >= top && old.gain < top) || (new.gain <= bottom && old.gain > bottom)
            || (new.freq >= EQ.freqMax && old.freq < EQ.freqMax) || (new.freq <= EQ.freqMin && old.freq > EQ.freqMin) {
            studio.buzz(.limit)
        } else if (old.gain < 0) != (new.gain < 0) || (old.gain != 0 && new.gain == 0) {
            studio.buzz(.bump)
        } else if Int(old.gain.rounded(.towardZero)) != Int(new.gain.rounded(.towardZero))
                    || GraphView.freqLines.contains(where: { ($0 > old.freq) != ($0 > new.freq) }) {
            studio.buzz(.tick)
        }
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
                let before = studio.preset.bands[i]
                studio.change("drag-\(id)") { p in
                    guard let k = p.bands.firstIndex(where: { $0.id == id }) else { return }
                    if !knob { p.bands[k].freq = (freq * 100).rounded() / 100 }
                    p.bands[k].gain = knob ? min(max((gain * 10).rounded() / 10, 0), Knob.maxGain) : (gain * 10).rounded() / 10
                }
                if let j = studio.band(id) { detents(before, studio.preset.bands[j], knob: knob) }
            }
            .onEnded { _ in
                dragging = nil
                frozenRange = nil
            }
    }


    /// Touch and hold on the graph, then slide: a line under the finger and the gain there, ticking at each
    /// grid frequency; let go and it's gone.
    private func holdToInspect(_ s: Scale) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("graph")))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    let p = CGPoint(x: min(max(drag.location.x, s.rect.minX), s.rect.maxX), y: drag.location.y)
                    if let was = holding {
                        let (a, b) = (s.freq(was.x), s.freq(p.x))
                        if GraphView.freqLines.contains(where: { ($0 > a) != ($0 > b) }) { studio.buzz(.tick) }
                    } else {
                        studio.buzz(.light)
                    }
                    holding = p
                case .second(true, nil):
                    if holding == nil { studio.buzz(.light) }
                default: break
                }
            }
            .onEnded { _ in holding = nil }
    }

    private func doubleTap(_ s: Scale) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { v in
            guard nearest(v.location, s) == nil, s.rect.contains(v.location) else { return }
            studio.addBand(freq: (s.freq(v.location.x)).rounded(), gain: (s.db(v.location.y) * 10).rounded() / 10)
        }
    }
}

/// The curve as a band of touch: its line widened to 36 pt, so a finger on or near it takes it.
private struct CurveBand: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var line = Path()
        for (k, p) in points.enumerated() { k == 0 ? line.move(to: p) : line.addLine(to: p) }
        return line.strokedPath(StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
    }
}


/// The graph's frequencies, 240 on a log scale: the curve, the measurement and the target are worked
/// out at these.
enum Plot {
    static let freqs: [Double] = (0..<240).map { pow(10, log10(EQ.freqMin) + (log10(EQ.freqMax) - log10(EQ.freqMin)) * Double($0) / 239) }
}

/// The graph's pencil, top right: on (the accent, filled) the graph edits; off it's locked.
private struct EditToggle: View {
    @Environment(Studio.self) private var studio
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil.and.outline")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(studio.accent).interactive() : .regular.interactive(), in: .circle)
        .padding(6)
        .accessibilityLabel("Edit on the graph")
        .accessibilityValue(on ? "On" : "Off, locked")
        .accessibilityAddTraits(on ? .isSelected : [])
        .help("Edit on the graph, or lock it")
    }
}

extension View {
    /// A graph held over a list where there's room (an iPad, an unfolded iPhone Duo): the list scrolls under
    /// it, as the EQ tab's graph stays. Elsewhere the list keeps it as its first row.
    /// Stacked above the list as the EQ tab's is (a top inset lost the page's large title).
    func pinnedGraph<G: View>(_ on: Bool, @ViewBuilder _ graph: () -> G) -> some View {
        VStack(spacing: 0) {
            if on {
                graph()
                    .padding(4)
                    .background(Color.rowBackground, in: .rect(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.groupedBackground)
            }
            self
        }
    }
}
