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

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                Image("StudioIcon")
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: .accentColor.opacity(0.35), radius: 18, y: 8)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("EQ Studio").font(.largeTitle.bold())
                    Text("Edit your Q2's EQ here, and hear it as you go.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Step(n: 1, text: "On the Q2, open **EQ Studio** in Library → Apps.")
                    Step(n: 2, text: "Keep this device on the same Wi-Fi as the Q2.")
                    Step(n: 3, text: "Scan the code it shows, or type the address and PIN under it.")
                }
                .padding(20)
                .frame(maxWidth: 440, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                VStack(spacing: 12) {
                    #if os(iOS)
                    if DataScannerViewController.isSupported {
                        Button { scanning = true } label: {
                            Label("Scan Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                    #endif
                    Button { typing = true } label: {
                        Label("Enter Address and PIN", systemImage: "keyboard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .frame(maxWidth: 440)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .background(backdrop)
        .sheet(isPresented: $typing) { SignInForm() }
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) { ScanView() }
        #endif
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.clear, Color.pink.opacity(0.10)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

private struct Step: View {
    let n: Int
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: .circle)
            Text(text)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text("192.168.1.20:8020 or 100.x.y.z:8020"))
                        .focused($field, equals: .address)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .submitLabel(.next)
                        .onSubmit { field = .pin }
                    SecureField("PIN", text: $pin, prompt: Text("6 digits"))
                        .focused($field, equals: .pin)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onSubmit(signIn)
                } footer: {
                    Text("Both are under the QR code on the Q2's screen. Away from the Q2's Wi-Fi, use its address in Tailscale's Settings → Apps Shared Now, with Tailscale on here. You can also paste the code's link.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sign In")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Sign In", action: signIn).disabled(address.isEmpty || (pin.count < 6 && Q2Link(scanned: address) == nil))
                    }
                }
            }
            .onAppear { field = .address }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private func signIn() {
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
