import Foundation
import SwiftUI
import WebKit

/// JellyEmu is a Jellyfin server plugin rather than an embeddable iOS emulator
/// framework. This view hosts its EmulatorJS player route inside the native app.
struct JellyEmuGamePlayer: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: JellyEmuGameConfiguration
    @State private var isClosing = false
    @State private var sessionEnded = false
    @State private var showingForceClose = false
    @State private var closeTimeoutTask: Task<Void, Never>?

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
            if isClosing {
                VStack(spacing: 9) {
                    ProgressView().tint(.white)
                    Text("Closing game and ending server session…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if showingForceClose {
                        Text("The server has not confirmed that this game session is closed.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        Button("Close anyway", role: .destructive) {
                            closeTimeoutTask?.cancel()
                            dismiss()
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
                .padding(16)
                .frame(maxWidth: 300)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 38)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: sessionEnded) { _, ended in
            if ended {
                closeTimeoutTask?.cancel()
                dismiss()
            }
        }
        .onDisappear { closeTimeoutTask?.cancel() }
    }

    private func closePlayer() {
        guard !isClosing else { return }
        isClosing = true
        // Ask JellyEmu to stop its session and flush playtime before dismissal.
        closeTimeoutTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            guard !sessionEnded else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showingForceClose = true }
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
        context.coordinator.allowedOrigin = jellyEmuOrigin(configuration.playURL)
        let contentController = WKUserContentController()
        let tokenLiteral = (try? JSONSerialization.data(
            withJSONObject: [configuration.accessToken, context.coordinator.allowedOrigin ?? ""],
            options: [.fragmentsAllowed]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\",\"\"]"
        let tokenScript = "(function(){const values = \(tokenLiteral); if (window.location.origin !== values[1]) { return; } window.JellyEmu = window.JellyEmu || {}; window.JellyEmu.getAuthToken = function(){ return values[0]; };})();"
        contentController.addUserScript(WKUserScript(
            source: tokenScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
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
        var allowedOrigin: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let allowedOrigin,
                  message.name == "jellyEmuSessionEnded",
                  message.frameInfo.isMainFrame,
                  jellyEmuOrigin(message.frameInfo.request.url) == allowedOrigin else { return }
            didRequestExit = true
            // The representable's binding is updated through the owner callback.
            onSessionEnded?()
        }

        var onSessionEnded: (() -> Void)?
    }
}

private func jellyEmuOrigin(_ url: URL?) -> String? {
    guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme), components.host != nil else { return nil }
    components.scheme = scheme
    components.host = components.host?.lowercased()
    let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
    if components.port == defaultPort { components.port = nil }
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}
