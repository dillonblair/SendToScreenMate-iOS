import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet entry point. Sends immediately (one tap from YouTube, Safari, Maps…),
/// closes on success, and stays open to show the error otherwise.
final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharePanel(state: state) { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await run() }
    }

    @MainActor
    private func run() async {
        do {
            let pairing = try PairingStore.require()
            let (text, title) = await sharedContent()
            guard let payload = LinkParser.payload(from: text, title: title) else {
                throw ScreenMateError("There's no link or text to send.")
            }
            state.title = payload.title
            state.phase = .sending
            let result = try await Publisher.send(payload, pairing: pairing)
            state.phase = .done(result.summary)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            finish()
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Prefers a URL attachment, then plain text, then the item's text.
    private func sharedContent() async -> (String, String?) {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let itemText = items.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty }
        let itemTitle = items.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty }

        for type in [UTType.url, UTType.plainText] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let value = await load(provider, type: type), !value.isEmpty {
                    // Apps often put the page title in the item text when sharing a URL.
                    let title = type == .url ? (itemTitle ?? itemText) : itemTitle
                    return (value, title)
                }
            }
        }
        return (itemText ?? "", itemTitle)
    }

    private func load(_ provider: NSItemProvider, type: UTType) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let text as String: continuation.resume(returning: text)
                case let data as Data: continuation.resume(returning: String(data: data, encoding: .utf8))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }
}

@MainActor
final class ShareState: ObservableObject {
    enum Phase: Equatable {
        case loading, sending, done(String), failed(String)
    }
    @Published var phase: Phase = .loading
    @Published var title = ""
}

struct SharePanel: View {
    @ObservedObject var state: ShareState
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            icon.font(.system(size: 44))
            if !state.title.isEmpty {
                Text(state.title).font(.headline).multilineTextAlignment(.center).lineLimit(3)
            }
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button(isFailed ? "Close" : "Done", action: close).buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var isFailed: Bool {
        if case .failed = state.phase { return true }
        return false
    }

    private var message: String {
        switch state.phase {
        case .loading: return "Preparing…"
        case .sending: return "Sending to ScreenMate…"
        case .done(let summary): return summary
        case .failed(let error): return error
        }
    }

    @ViewBuilder private var icon: some View {
        switch state.phase {
        case .loading, .sending: ProgressView().controlSize(.large)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
