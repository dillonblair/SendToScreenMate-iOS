import Foundation

/// Turns whatever the user shares (a URL, a web page, a Maps place, an address, or
/// text read off the screen) into the link the Receiver should open.
enum LinkParser {
    /// - Parameters:
    ///   - text: Shared text, URL string, or OCR output.
    ///   - title: Optional title from the source app.
    ///   - requireTarget: When true, returns nil unless a web link or a place was found
    ///     (used for screen text, where sending arbitrary words makes no sense).
    static func payload(from text: String, title: String? = nil, requireTarget: Bool = false) -> LinkPayload? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let givenTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if input.lowercased().hasPrefix("geo:") {
            return LinkPayload(url: input, title: givenTitle.isEmpty ? place(fromGeo: input) ?? "Location" : givenTitle)
        }
        if let url = firstWebURL(in: input) {
            if let geo = geoURL(fromAppleMaps: url) {
                return LinkPayload(url: geo.url, title: givenTitle.isEmpty ? geo.place : givenTitle)
            }
            return LinkPayload(url: url.absoluteString, title: givenTitle.isEmpty ? defaultTitle(for: url, in: input) : givenTitle)
        }
        if let address = firstAddress(in: input) {
            return LinkPayload(url: "geo:0,0?q=" + encodeQuery(address), title: givenTitle.isEmpty ? address : givenTitle)
        }
        if requireTarget { return nil }
        // Plain text: the Receiver treats it as a navigation search.
        return LinkPayload(url: input, title: givenTitle.isEmpty ? "Destination" : givenTitle)
    }

    static func firstWebURL(in text: String) -> URL? {
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    static func firstAddress(in text: String) -> String? {
        let types = NSTextCheckingResult.CheckingType.address.rawValue
        guard let detector = try? NSDataDetector(types: types),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return text[range]
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Apple Maps links mean nothing on Android, so they become `geo:` destinations.
    static func geoURL(fromAppleMaps url: URL) -> (url: String, place: String)? {
        guard let host = url.host?.lowercased(), host == "maps.apple.com" || host == "maps.apple",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let destination = value("daddr") ?? value("address") ?? value("q") ?? value("ll") else { return nil }
        let place = value("q") ?? value("name") ?? destination
        return ("geo:0,0?q=" + encodeQuery(destination), place)
    }

    static func place(fromGeo geo: String) -> String? {
        guard let range = geo.range(of: "q=") else { return nil }
        let raw = geo[range.upperBound...].split(separator: "&").first.map(String.init) ?? ""
        let decoded = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
        return decoded.isEmpty ? nil : decoded
    }

    private static func defaultTitle(for url: URL, in text: String) -> String {
        // Text shared alongside a link ("Video title https://…") is usually its title.
        let leading = text.components(separatedBy: url.absoluteString).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !leading.isEmpty, leading.count <= 120, !leading.contains("\n") { return leading }
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" || host.hasSuffix("youtube.com") { return "YouTube video" }
        return host.isEmpty ? "Link" : host.replacingOccurrences(of: "www.", with: "")
    }

    private static func encodeQuery(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
