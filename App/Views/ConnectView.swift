// SPDX-License-Identifier: GPL-3.0-only
// Signing in to EQ Studio on the Q2: scan its QR code, or type the address and PIN under it.
import SwiftUI
import AVFoundation
import VisionKit

struct ConnectView: View {
    @Environment(Studio.self) private var studio
    @State private var scanning = false
    @State private var typing = false
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 36)
                ZStack {
                    Circle()
                        .fill(studio.accent.opacity(0.35))
                        .frame(width: 170, height: 170)
                        .blur(radius: 40)
                    Image("StudioIcon")
                        .resizable()
                        .frame(width: 118, height: 118)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
                }
                .scaleEffect(shown ? 1 : 0.85)
                .opacity(shown ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("EQ Studio").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Shape your Q2's sound,\nand hear it as you go.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(shown ? 1 : 0)

                VStack(alignment: .leading, spacing: 18) {
                    Step(icon: "app.badge", text: "On the Q2, open **EQ Studio** in Library → Apps.")
                    Step(icon: "wifi", text: "Keep this device on the **same Wi-Fi** as the Q2.")
                    Step(icon: "qrcode", text: "**Scan the code** it shows, or type the address and PIN under it.")
                }
                .padding(22)
                .frame(maxWidth: 440, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .offset(y: shown ? 0 : 16)
                .opacity(shown ? 1 : 0)

                VStack(spacing: 12) {
                    if DataScannerViewController.isSupported {
                        Button { scanning = true } label: {
                            Label("Scan Code", systemImage: "qrcode.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.extraLarge)
                    }
                    Button { typing = true } label: {
                        Label("Enter Address and PIN", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    Button("Try Without a Q2") { studio.tryWithoutQ2() }
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 2)
                    Label("Away from home? Use the Q2's Tailscale address.", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 440)
                .opacity(shown ? 1 : 0)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { Backdrop() }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.25)) { shown = true } }
        .sheet(isPresented: $typing) { SignInForm() }
        .fullScreenCover(isPresented: $scanning) {
            ScanView(typeInstead: { Task { try? await Task.sleep(for: .milliseconds(450)); typing = true } })
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["EQS_SIGNIN"] != nil { typing = true }
            if ProcessInfo.processInfo.environment["EQS_SCAN"] != nil { scanning = true }
        }
        #endif
    }
}

/// The welcome's background: EQ Studio's blues, drifting slowly, a faint EQ curve across them.
private struct Backdrop: View {
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            let dark = scheme == .dark
            let a = Color(red: 0.13, green: 0.38, blue: 0.88), b = Color(red: 0.43, green: 0.64, blue: 1.0)
            let base = dark ? Color(white: 0.05) : Color(white: 0.97)
            let mid = Float(0.5 + 0.12 * sin(t / 3))
            ZStack {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [mid, Float(0.45 + 0.08 * cos(t / 4))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    a.opacity(dark ? 0.55 : 0.35), base, b.opacity(dark ? 0.35 : 0.25),
                    base, a.opacity(dark ? 0.25 : 0.15), base,
                    b.opacity(dark ? 0.30 : 0.20), base, a.opacity(dark ? 0.45 : 0.30),
                ])
                Canvas { ctx, size in
                    var path = Path()
                    for i in 0...120 {
                        let x = size.width * CGFloat(i) / 120
                        let p = Double(i) / 120 * .pi * 2
                        let y = size.height * 0.72 + CGFloat(sin(p * 1.5 + t / 2) * 26 + sin(p * 3.7 - t / 3) * 12)
                        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.stroke(path, with: .color(b.opacity(dark ? 0.35 : 0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct Step: View {
    @Environment(Studio.self) private var studio
    let icon: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(studio.accent.gradient, in: .rect(cornerRadius: 10))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SignInForm: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var pin = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var field: Field?
    enum Field { case address, pin }

    private var ready: Bool { !address.isEmpty && (pin.count == 6 || Q2Link(scanned: address) != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 8) {
                        Image("StudioIcon").resizable().frame(width: 64, height: 64)
                            .shadow(color: studio.accent.opacity(0.4), radius: 12, y: 6)
                        Text("Sign In").font(.system(.title, design: .rounded, weight: .bold))
                        Text("Both are under the QR code on the Q2's screen.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Address").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        HStack(spacing: 10) {
                            Image(systemName: "network").foregroundStyle(.tint)
                            TextField("192.168.1.20:8020", text: $address)
                                .focused($field, equals: .address)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .submitLabel(.next)
                                .onSubmit { field = .pin }
                        }
                        .padding(14)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                        Text("Away from the Q2's Wi-Fi: its Tailscale address, from Tailscale's Settings → Apps Shared Now. Or paste the code's link.")
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PIN").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        PinBoxes(pin: $pin, focused: field == .pin) { field = .pin }
                            .overlay {
                                // The real field, invisible over the boxes: the keyboard, paste and the code autofill.
                                TextField("", text: Binding(get: { pin }, set: { pin = String($0.filter(\.isNumber).prefix(6)); if pin.count == 6 { signIn() } }))
                                    .focused($field, equals: .pin)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .foregroundStyle(.clear)
                                    .tint(.clear)
                                    .opacity(0.02)
                            }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.red.opacity(0.1), in: .rect(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button(action: signIn) {
                        Group {
                            if busy { ProgressView().tint(.white) } else { Text("Sign In").font(.headline) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!ready || busy)
                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .animation(.default, value: error)
            }
            .background { Backdrop().opacity(0.6) }
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() } }
            }
            .onAppear { field = .address }
        }
        .frame(minWidth: 400, minHeight: 520)
    }

    private func signIn() {
        guard !busy else { return }
        if let link = Q2Link(scanned: address) { // the QR code's link, pasted
            Task { await check(link) }
            return
        }
        guard let base = Q2Link.base(typed: address) else {
            error = "That isn't an address. It looks like 192.168.1.20:8020."
            return
        }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                await check(try await Q2Client.signIn(base: base, pin: pin.trimmingCharacters(in: .whitespaces)))
            } catch {
                self.error = error.localizedDescription
                pin = ""
            }
        }
    }

    private func check(_ link: Q2Link) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Q2Client(link: link).state()
            studio.connect(link)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The PIN as six boxes, as a verification code is entered: the next one to fill ringed.
private struct PinBoxes: View {
    @Environment(Studio.self) private var studio
    @Binding var pin: String
    let focused: Bool
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                let digit = i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : ""
                let next = focused && i == min(pin.count, 5)
                Text(digit.isEmpty ? " " : "•")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(next ? studio.accent : .clear, lineWidth: 2)
                    }
                    .animation(.snappy(duration: 0.15), value: pin)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityElement()
        .accessibilityLabel("PIN, \(pin.count) of 6 digits")
    }
}

/// The camera, reading EQ Studio's QR code.
private struct ScanView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var typeInstead: () -> Void = {}
    @State private var error: String?
    @State private var busy = false
    @State private var done = false
    @State private var shake = 0
    @State private var torch = false

    private static let size: CGFloat = 260

    var body: some View {
        ZStack {
            #if DEBUG
            if ProcessInfo.processInfo.environment["EQS_SCAN"] != nil {
                // The simulator has no camera: a stand-in, for a look at the screen.
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            } else {
                camera
            }
            #else
            camera
            #endif
            Viewfinder(size: Self.size, state: done ? .done : error != nil ? .wrong : busy ? .busy : .looking,
                       moving: !reduceMotion && !busy && !done, shake: shake)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(.horizontal, 20)
                VStack(spacing: 6) {
                    Text("Scan the Q2's Code").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("On the Q2: Library → Apps → EQ Studio").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.top, 8)
                Spacer()
                card
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .sensoryFeedback(.error, trigger: shake)
        .onDisappear { setTorch(false) }
    }

    private var camera: some View {
        QRScanner { text in
            guard !busy, !done, error == nil else { return }
            guard let link = Q2Link(scanned: text) else {
                wrong("That isn't EQ Studio's code. Look for it on the Q2's screen, in EQ Studio.")
                return
            }
            busy = true
            Task {
                do {
                    _ = try await Q2Client(link: link).state()
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) { done = true }
                    try? await Task.sleep(for: .milliseconds(700))
                    studio.connect(link)
                    dismiss()
                } catch {
                    busy = false
                    wrong(error.localizedDescription)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(spacing: 14) {
            Group {
                if done {
                    Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if busy {
                    HStack(spacing: 10) { ProgressView(); Text("Signing in…") }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Text("Hold the camera over the code on the Q2. It signs in as soon as it sees it.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 40)
            HStack(spacing: 10) {
                // Only where there's a light to turn on: most iPads have none.
                if Self.torchDevice != nil {
                    Button { setTorch(!torch) } label: {
                        Label(torch ? "Light On" : "Light", systemImage: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                Button {
                    dismiss()
                    typeInstead()
                } label: {
                    Label("Type PIN", systemImage: "keyboard").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .animation(.default, value: error)
        .animation(.default, value: busy)
    }

    /// The wrong code, or the Q2 not answering: said, the brackets shaken, scanning again shortly.
    private func wrong(_ text: String) {
        withAnimation(.default) { error = text }
        shake += 1
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.default) { error = nil }
        }
    }

    /// The back camera with a light: the scanner runs a Pro iPhone's combined camera, so that one first, then
    /// the single ones; the default video camera isn't always the one with the light. None on most iPads.
    static var torchDevice: AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                                                       .builtInWideAngleCamera],
                                         mediaType: .video, position: .back).devices.first { $0.hasTorch }
    }

    private func setTorch(_ on: Bool) {
        guard let d = Self.torchDevice, d.isTorchAvailable || !on, (try? d.lockForConfiguration()) != nil else {
            if on { studio.say("The light isn't available right now.") }
            return
        }
        if on { try? d.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { d.torchMode = .off }
        d.unlockForConfiguration()
        torch = on
    }
}

/// The dimmed camera with a rounded window, its corners bracketed: white while looking, a line sweeping
/// across; green with a check once signed in; red, shaken, for the wrong code.
private struct Viewfinder: View {
    @Environment(Studio.self) private var studio
    enum State { case looking, busy, done, wrong }
    let size: CGFloat
    let state: State
    let moving: Bool
    let shake: Int

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: (geo.size.width - size) / 2, y: (geo.size.height - size) / 2 - 20, width: size, height: size)
            let colour: Color = state == .done ? .green : state == .wrong ? .red : .white
            ZStack {
                // The dimming, with the window cut out.
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRoundedRect(in: rect, cornerSize: CGSize(width: 32, height: 32))
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                Brackets(rect: rect)
                    .stroke(colour, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .shadow(color: colour.opacity(0.7), radius: 8)
                    .modifier(Shake(times: CGFloat(shake)))

                if moving {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let y = rect.minY + 24 + (rect.height - 48) * (0.5 + 0.5 * sin(t * 1.6))
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, studio.accent, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: rect.width - 40, height: 3)
                            .shadow(color: studio.accent, radius: 6)
                            .position(x: rect.midX, y: y)
                    }
                }
                if state == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(.white, .green)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: state == .done)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The viewfinder's four corners.
private struct Brackets: Shape {
    let rect: CGRect
    func path(in _: CGRect) -> Path {
        let r: CGFloat = 32, l: CGFloat = 46
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * r))
            p.addQuadCurve(to: CGPoint(x: corner.x + dx * r, y: corner.y), control: corner)
            p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
        }
        return p
    }
}

/// A side-to-side shake, once for each count.
private struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(times * .pi * 4), y: 0))
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: false)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in items {
                if let s = code.payloadStringValue { found(s); return }
            }
        }
    }
}
