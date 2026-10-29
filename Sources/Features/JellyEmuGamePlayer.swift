import SwiftUI
import WebKit

/// JellyEmu is a Jellyfin server plugin rather than an embeddable iOS emulator
/// framework. This view hosts its EmulatorJS player route inside the native app.
struct JellyEmuGamePlayer: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: JellyEmuGameConfiguration
    @State private var isClosing = false
    @State private var sessionEnded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            JellyEmuWebView(configuration: configuration, closeRequested: $isClosing, sessionEnded: $sessionEnded)
                .ignoresSafeArea()
            Button(action: closePlayer) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.68), in: Circle())
            }
            .accessibilityLabel("Close game")
            .padding(.top, 12)
            .padding(.trailing, 14)
            .disabled(isClosing)
        }
        .preferredColorScheme(.dark)
        .onChange(of: sessionEnded) { _, ended in
            if ended { dismiss() }
        }
    }

    private func closePlayer() {
        guard !isClosing else { return }
        isClosing = true
        // Ask JellyEmu to stop its session and flush playtime before dismissal.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !sessionEnded { dismiss() }
        }
    }
}

@MainActor
private struct JellyEmuWebView: UIViewRepresentable {
    let configuration: JellyEmuGameConfiguration
    @Binding var closeRequested: Bool
    @Binding var sessionEnded: Bool

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.onSessionEnded = { sessionEnded = true }
        let contentController = WKUserContentController()
        let tokenLiteral = (try? JSONSerialization.data(
            withJSONObject: [configuration.accessToken],
            options: [.fragmentsAllowed]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let tokenScript = "window.JellyEmu = window.JellyEmu || {}; window.JellyEmu.getAuthToken = function(){ return \(tokenLiteral)[0]; };"
        contentController.addUserScript(WKUserScript(
            source: tokenScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.add(context.coordinator, contentWorld: .page, name: "jellyEmuSessionEnded")
        contentController.addUserScript(WKUserScript(
            source: "window.addEventListener('message', function(event) { if (event.data && event.data.type === 'jellyemu-session-end' && window.webkit && window.webkit.messageHandlers.jellyEmuSessionEnded) { window.webkit.messageHandlers.jellyEmuSessionEnded.postMessage('ended'); } });",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = contentController
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.load(URLRequest(url: configuration.playURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard closeRequested, !context.coordinator.didRequestExit else { return }
        context.coordinator.didRequestExit = true
        uiView.evaluateJavaScript("document.getElementById('je-exit-btn')?.click();")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var didRequestExit = false

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "jellyEmuSessionEnded" else { return }
            didRequestExit = true
            // The representable's binding is updated through the owner callback.
            onSessionEnded?()
        }

        var onSessionEnded: (() -> Void)?
    }
}
