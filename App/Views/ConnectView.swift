// SPDX-License-Identifier: GPL-3.0-only
// Signing in to EQ Studio on the Q2: scan its QR code, or type the address and PIN under it.
import SwiftUI
#if os(iOS)
import VisionKit
#endif

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
                        .fill(Color.accentColor.opacity(0.35))
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
                    #if os(iOS)
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
                    #endif
                    Button { typing = true } label: {
                        Label("Enter Address and PIN", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
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
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) { ScanView() }
        #endif
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["EQS_SIGNIN"] != nil { typing = true } }
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
    let icon: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 10))
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
                            .shadow(color: .accentColor.opacity(0.4), radius: 12, y: 6)
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
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                #endif
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
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    #endif
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
                            .strokeBorder(next ? Color.accentColor : .clear, lineWidth: 2)
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

#if os(iOS)
/// The camera, reading EQ Studio's QR code.
private struct ScanView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .bottom) {
            QRScanner { text in
                guard !busy else { return }
                guard let link = Q2Link(scanned: text) else {
                    error = "That isn't EQ Studio's code."
                    return
                }
                busy = true
                Task {
                    do {
                        _ = try await Q2Client(link: link).state()
                        studio.connect(link)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                        busy = false
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 14) {
                if busy {
                    ProgressView("Signing in…")
                } else {
                    Text(error ?? "Point the camera at the code on the Q2.")
                        .multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .frame(maxWidth: 420)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(20)
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
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
#endif
