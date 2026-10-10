import Foundation

/// Stores the pairing in the App Group so the app, share extension and Shortcuts action share it.
enum PairingStore {
    private static let storageKey = "pairing.v1"

    /// The App Group identifier, injected into each target's Info.plist from the build settings.
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    private static var defaults: UserDefaults {
        groupID.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    static func load() -> Pairing? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    static func save(_ pairing: Pairing?) {
        if let pairing, let data = try? JSONEncoder().encode(pairing) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    static func require() throws -> Pairing {
        guard let pairing = load() else {
            throw ScreenMateError("Not paired yet. Open SendTo ScreenMate and scan your Receiver's QR code.")
        }
        return pairing
    }
}
