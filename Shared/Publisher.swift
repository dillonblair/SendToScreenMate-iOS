import Foundation

struct DeliveryResult: Sendable {
    /// True once the Receiver has acknowledged the message.
    let confirmed: Bool

    var summary: String {
        confirmed ? "Opened on ScreenMate" : "Sent. ScreenMate will open it when it's back online."
    }
}

/// Publishes encrypted links to the paired ntfy topic and waits briefly for the Receiver's receipt.
enum Publisher {
    /// ntfy turns larger messages into attachments, which the Receiver ignores.
    static let maxBodyBytes = 4000
    static let receiptTimeout: TimeInterval = 8

    static func send(_ payload: LinkPayload, pairing: Pairing) async throws -> DeliveryResult {
        let base = try pairing.serverURL()
        let body = try WireCrypto.encode(payload, key: pairing.key)
        guard body.utf8.count <= maxBodyBytes else {
            throw ScreenMateError("That link is too long to send.")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: base.appendingPathComponent(pairing.topic))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try check(response)

        struct Published: Decodable { let id: String; let time: Int? }
        guard let published = try? JSONDecoder().decode(Published.self, from: data) else {
            return DeliveryResult(confirmed: false)
        }
        let confirmed = await waitForReceipt(
            id: published.id,
            since: (published.time ?? Int(Date().timeIntervalSince1970)) - 1,
            base: base, topic: pairing.topic, session: session
        )
        return DeliveryResult(confirmed: confirmed)
    }

    /// Polls `<topic>_ack` for a message whose body is our message id.
    private static func waitForReceipt(id: String, since: Int, base: URL, topic: String, session: URLSession) async -> Bool {
        var components = URLComponents(url: base.appendingPathComponent(topic + "_ack").appendingPathComponent("json"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "poll", value: "1"), URLQueryItem(name: "since", value: String(since))]
        guard let url = components?.url else { return false }

        struct Event: Decodable { let event: String?; let message: String? }
        let deadline = Date().addingTimeInterval(receiptTimeout)
        while Date() < deadline, !Task.isCancelled {
            if let (data, response) = try? await session.data(from: url), (try? check(response)) != nil {
                let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
                let acknowledged = lines.contains { line in
                    guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else { return false }
                    return event.event == "message" && event.message?.trimmingCharacters(in: .whitespacesAndNewlines) == id
                }
                if acknowledged { return true }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ScreenMateError("No response from the server.") }
        guard (200..<300).contains(http.statusCode) else {
            throw ScreenMateError("The server returned an error (HTTP \(http.statusCode)).")
        }
    }
}
