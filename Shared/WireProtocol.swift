import CryptoKit
import Foundation

/// User-facing error with a readable message.
struct ScreenMateError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Connection details shared by the Receiver's QR code: `server|topic|base64Key`.
struct Pairing: Codable, Equatable, Sendable {
    var server: String
    var topic: String
    /// Base64-encoded 32-byte AES-256 key.
    var key: String

    init(server: String, topic: String, key: String) {
        self.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses the text encoded in the Receiver's pairing QR code.
    init(code: String) throws {
        let fields = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count == 3 else {
            throw ScreenMateError("That isn't a ScreenMate pairing code. It should look like server|topic|key.")
        }
        self.init(server: fields[0], topic: fields[1], key: fields[2])
        try validate()
    }

    /// The ntfy server as an https URL (http only for local testing).
    func serverURL() throws -> URL {
        var text = server
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              url.query == nil, url.user == nil, url.password == nil else {
            throw ScreenMateError("The server address isn't valid.")
        }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard url.scheme == "https" || (url.scheme == "http" && local) else {
            throw ScreenMateError("The server must use https.")
        }
        return url
    }

    func validate() throws {
        _ = try serverURL()
        guard topic.range(of: "^[-_A-Za-z0-9]{1,64}$", options: .regularExpression) != nil else {
            throw ScreenMateError("The topic in the pairing code isn't valid.")
        }
        _ = try WireCrypto.symmetricKey(key)
    }

    /// Short label for the UI, e.g. "ntfy.sh · sm-Abc…".
    var label: String {
        let host = (try? serverURL())?.host ?? server
        return "\(host) · \(topic.prefix(10))…"
    }
}

/// The JSON payload carried inside each encrypted message.
struct LinkPayload: Codable, Equatable, Sendable {
    var url: String
    var title: String
}

/// AES-256-GCM, encoded as Base64(12-byte nonce ‖ ciphertext ‖ 16-byte tag).
enum WireCrypto {
    static func symmetricKey(_ base64: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw ScreenMateError("The encryption key must be 32 bytes of Base64.")
        }
        return SymmetricKey(data: data)
    }

    static func seal(_ plaintext: Data, key: String) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: symmetricKey(key))
        guard let combined = box.combined else { throw ScreenMateError("Encryption failed.") }
        return combined.base64EncodedString()
    }

    static func open(_ body: String, key: String) throws -> Data {
        guard let combined = Data(base64Encoded: body.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ScreenMateError("The message isn't valid Base64.")
        }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: symmetricKey(key))
    }

    static func encode(_ payload: LinkPayload, key: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try seal(encoder.encode(payload), key: key)
    }

    static func decode(_ body: String, key: String) throws -> LinkPayload {
        try JSONDecoder().decode(LinkPayload.self, from: open(body, key: key))
    }
}
