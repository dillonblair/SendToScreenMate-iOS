import SwiftUI

@main
struct SendToScreenMateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var pairing: Pairing? = PairingStore.load()
    @Published var draft = ""
    @Published var status = ""
    @Published var sending = false

    func pair(with code: String) {
        do {
            let pairing = try Pairing(code: code)
            PairingStore.save(pairing)
            self.pairing = pairing
            status = "Paired with \(pairing.label)"
        } catch {
            status = error.localizedDescription
        }
    }

    func unpair() {
        PairingStore.save(nil)
        pairing = nil
        status = "Unpaired"
    }

    func send() {
        guard let pairing, !sending else { return }
        guard let payload = LinkParser.payload(from: draft) else {
            status = "Enter a link, address or place first."
            return
        }
        sending = true
        status = "Sending…"
        Task {
            defer { sending = false }
            do {
                status = try await Publisher.send(payload, pairing: pairing).summary
            } catch {
                status = "Couldn't send: \(error.localizedDescription)"
            }
        }
    }
}
