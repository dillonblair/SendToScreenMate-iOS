import AppIntents
import Foundation
import UniformTypeIdentifiers
import Vision

/// Shortcuts action "Send to ScreenMate". Runs in the background, so it works from
/// NFC automations, Back Tap, the Action button and Siri.
///
/// Typical shortcut: Get On-Screen URLs + Get On-Screen Postal Addresses → Text → Send to ScreenMate.
struct SendToScreenMateIntent: AppIntent {
    static var title: LocalizedStringResource = "Send to ScreenMate"
    static var description = IntentDescription(
        "Sends a link, web page, place or address to your paired ScreenMate. An optional screenshot is scanned for a link or address when Content has none."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Content", inputConnectionBehavior: .connectToPreviousIntentResult)
    var content: String?

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile?

    @Parameter(title: "Title")
    var linkTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$content) to ScreenMate") {
            \.$screenshot
            \.$linkTitle
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let pairing = try PairingStore.require()
        let text = content ?? ""
        // With a screenshot as backup, Content only counts if it holds a link or place.
        var payload = LinkParser.payload(from: text, title: linkTitle, requireTarget: screenshot != nil)
        if payload == nil, let screenshot {
            let screenText = try ScreenReader.text(in: screenshot.data)
            payload = LinkParser.payload(from: screenText, title: linkTitle, requireTarget: true)
        }
        guard let payload else {
            throw ScreenMateError(text.isEmpty && screenshot == nil
                ? "Nothing to send."
                : "No link or address found. Use Share → SendTo ScreenMate in this app instead.")
        }
        let result = try await Publisher.send(payload, pairing: pairing)
        return .result(value: payload.url, dialog: "\(payload.title): \(result.summary)")
    }
}

/// On-device text recognition for screenshots.
enum ScreenReader {
    static func text(in imageData: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: imageData, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

struct ScreenMateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendToScreenMateIntent(),
            phrases: ["Send to \(.applicationName)"],
            shortTitle: "Send to ScreenMate",
            systemImageName: "rectangle.on.rectangle"
        )
    }
}
