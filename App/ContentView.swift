import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var scanning = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                if let pairing = model.pairing {
                    Section("Send something") {
                        TextField("Link, address or place", text: $model.draft, axis: .vertical)
                            .lineLimit(2...6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            PasteButton(payloadType: String.self) { strings in
                                if let first = strings.first { model.draft = first }
                            }
                            .labelStyle(.titleAndIcon)
                            Spacer()
                            Button {
                                model.send()
                            } label: {
                                if model.sending { ProgressView() } else { Label("Send", systemImage: "paperplane.fill") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.sending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if !model.status.isEmpty {
                            Text(model.status).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        LabeledContent("Receiver", value: pairing.label)
                        pairingButtons(title: "Pair again")
                        Button("Unpair", role: .destructive, action: model.unpair)
                    } header: {
                        Text("Pairing")
                    } footer: {
                        Text("Send from any app with Share → SendTo ScreenMate, or use the “Send to ScreenMate” action in Shortcuts.")
                    }
                } else {
                    Section {
                        Text("Open ScreenMate Receiver on your car's screen and scan the QR code it shows.")
                        pairingButtons(title: "Scan QR code")
                        if !model.status.isEmpty {
                            Text(model.status).font(.callout).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Pair with your screen")
                    }
                }
            }
            .navigationTitle("SendTo ScreenMate")
            .sheet(isPresented: $scanning) {
                QRScannerView { code in
                    scanning = false
                    model.pair(with: code)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let code = QRImageReader.code(in: data) else {
                        model.status = "No QR code found in that image."
                        return
                    }
                    model.pair(with: code)
                }
            }
        }
    }

    @ViewBuilder
    private func pairingButtons(title: String) -> some View {
        if QRScannerView.isAvailable {
            Button(title) { scanning = true }
        }
        PhotosPicker("Choose QR from Photos", selection: $photo, matching: .images)
        Button("Paste pairing code") {
            if let text = UIPasteboard.general.string { model.pair(with: text) } else { model.status = "The clipboard is empty." }
        }
    }
}
