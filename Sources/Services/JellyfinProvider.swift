import Foundation
import JellyfinAPI
import Observation
import Security
import UIKit

struct JellyfinLibraryEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let creator: String
    let kind: MediaKind
    let gameSystem: String?
    let overview: String
    let durationSeconds: Double
    let resumeSeconds: Double
    let isPlayable: Bool
    let imageURL: URL?
}

struct JellyEmuGameConfiguration: Sendable {
    let itemID: String
    let userID: String
    let accessToken: String
    let playURL: URL
}

struct JellyfinPlaybackSession: Sendable {
    let itemID: String
    let mediaSourceID: String?
    let playSessionID: String?
    let streamURL: URL
}

@MainActor
@Observable
final class JellyfinProvider {
    var serverAddress = ""
    var username = ""
    var password = ""
    private(set) var entries: [JellyfinLibraryEntry] = []
    private(set) var connectedServerName: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var client: JellyfinClient?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private let credentialStore = JellyfinCredentialStore()

    var isConnected: Bool { client != nil }

    func restoreConnection() async {
        guard !isConnected else { return }
        guard let credentials = credentialStore.load() else { return }
        serverAddress = credentials.serverURL
        username = credentials.username
        userID = credentials.userID
        accessToken = credentials.accessToken
        client = makeClient(urlString: credentials.serverURL, token: credentials.accessToken)
        connectedServerName = URL(string: credentials.serverURL)?.host
        await refreshLibrary()
    }

    func connect() async {
        errorMessage = nil
        guard let url = normalizedServerURL(serverAddress) else {
            errorMessage = "Enter a valid Jellyfin server URL, including http:// or https://."
            return
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            errorMessage = "Enter your Jellyfin username and password."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let client = makeClient(url: url, token: nil)
            let authentication = try await client.signIn(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            guard let token = authentication.accessToken,
                  let userID = authentication.user?.id else {
                throw JellyfinProviderError.incompleteAuthentication
            }

            let credentials = JellyfinCredentials(
                serverURL: url.absoluteString,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                userID: userID,
                accessToken: token
            )
            try credentialStore.save(credentials)
            self.client = client
            self.userID = userID
            self.accessToken = token
            self.connectedServerName = authentication.user?.serverName ?? url.host
            self.password = ""
            await refreshLibrary()
        } catch {
            errorMessage = "Could not connect to Jellyfin: \(error.localizedDescription)"
        }
    }

    func refreshLibrary() async {
        guard let client, let userID else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let parameters = Paths.GetItemsParameters(
                userID: userID,
                limit: 200,
                isRecursive: true,
                fields: [.tags],
                includeItemTypes: [.audio, .audioBook, .book, .episode, .movie, .musicAlbum, .video],
                enableUserData: true,
                imageTypeLimit: 1,
                enableImageTypes: [.primary],
                enableImages: true
            )
            let response = try await client.send(Paths.getItems(parameters: parameters))
            entries = (response.value.items ?? []).compactMap { item in
                guard let id = item.id, let title = item.name, let kind = mediaKind(for: item) else { return nil }
                let creator = item.albumArtist
                    ?? item.artists?.joined(separator: ", ")
                    ?? item.seriesName
                    ?? item.album
                    ?? ""
                let gameSystem = kind == .game
                    ? item.tags?.first { $0.caseInsensitiveCompare("JellyEmu") != .orderedSame }
                    : nil
                return JellyfinLibraryEntry(
                    id: id,
                    title: title,
                    creator: creator,
                    kind: kind,
                    gameSystem: gameSystem,
                    overview: item.overview ?? "",
                    durationSeconds: Double(item.runTimeTicks ?? 0) / 10_000_000,
                    resumeSeconds: Double(item.userData?.playbackPositionTicks ?? 0) / 10_000_000,
                    isPlayable: kind == .game || (item.type.map {
                        [BaseItemKind.audio, .episode, .movie, .musicVideo, .video].contains($0)
                    } ?? false),
                    imageURL: imageURL(for: item, serverURL: client.configuration.url)
                )
            }
        } catch {
            errorMessage = "Could not load items from Jellyfin: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        if let client {
            try? await client.signOut()
        }
        client = nil
        userID = nil
        accessToken = nil
        connectedServerName = nil
        entries = []
        errorMessage = nil
        credentialStore.remove()
    }

    func preparePlayback(for item: JellyfinLibraryEntry) async throws -> JellyfinPlaybackSession {
        guard item.isPlayable, let client, let userID else {
            throw JellyfinProviderError.playbackUnavailable
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let playbackInfo = try await client.send(Paths.getPlaybackInfo(itemID: item.id, userID: userID)).value
        guard let mediaSource = playbackInfo.mediaSources?.first else {
            throw JellyfinProviderError.noMediaSource
        }

        let streamURL: URL?
        if item.kind == .video {
            streamURL = client.url(
                with: Paths.getVideoStream(
                    itemID: item.id,
                    parameters: .init(
                        playSessionID: playbackInfo.playSessionID,
                        mediaSourceID: mediaSource.id,
                        deviceID: client.configuration.deviceID
                    )
                ),
                queryAPIKey: true
            )
        } else {
            streamURL = client.url(
                with: Paths.getAudioStream(
                    itemID: item.id,
                    parameters: .init(
                        playSessionID: playbackInfo.playSessionID,
                        mediaSourceID: mediaSource.id,
                        deviceID: client.configuration.deviceID
                    )
                ),
                queryAPIKey: true
            )
        }
        guard let streamURL else {
            throw JellyfinProviderError.invalidStreamURL
        }
        return JellyfinPlaybackSession(
            itemID: item.id,
            mediaSourceID: mediaSource.id,
            playSessionID: playbackInfo.playSessionID,
            streamURL: streamURL
        )
    }

    func gamePlayerConfiguration(for item: JellyfinLibraryEntry) -> JellyEmuGameConfiguration? {
        guard item.kind == .game,
              let userID,
              let accessToken,
              let serverURL = normalizedServerURL(serverAddress),
              var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else { return nil }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "jellyemu", "play", item.id].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "userId", value: userID)]
        guard let playURL = components.url else { return nil }
        return JellyEmuGameConfiguration(itemID: item.id, userID: userID, accessToken: accessToken, playURL: playURL)
    }

    func reportPlaybackStarted(_ session: JellyfinPlaybackSession, positionSeconds: Double) async {
        guard let client else { return }
        let body = playbackState(session, positionSeconds: positionSeconds, isPaused: false)
        try? await client.send(Paths.reportPlaybackStart(body))
    }

    func reportPlaybackProgress(_ session: JellyfinPlaybackSession, positionSeconds: Double, isPaused: Bool) async {
        guard let client else { return }
        let body = playbackState(session, positionSeconds: positionSeconds, isPaused: isPaused)
        try? await client.send(Paths.reportPlaybackProgress(body))
    }

    func reportPlaybackStopped(_ session: JellyfinPlaybackSession, positionSeconds: Double) async {
        guard let client else { return }
        let body = PlaybackStopInfo(
            itemID: session.itemID,
            mediaSourceID: session.mediaSourceID,
            playSessionID: session.playSessionID,
            positionTicks: positionTicks(positionSeconds)
        )
        try? await client.send(Paths.reportPlaybackStopped(body))
    }

    func handlePlaybackFailure(_ error: Error) {
        errorMessage = "Could not start server playback: \(error.localizedDescription)"
    }

    private func playbackState(
        _ session: JellyfinPlaybackSession,
        positionSeconds: Double,
        isPaused: Bool
    ) -> PlaybackStateInfo {
        PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: session.itemID,
            mediaSourceID: session.mediaSourceID,
            playSessionID: session.playSessionID,
            positionTicks: positionTicks(positionSeconds)
        )
    }

    private func positionTicks(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 86_400 * 365) * 10_000_000)
    }

    private func makeClient(urlString: String, token: String?) -> JellyfinClient? {
        guard let url = normalizedServerURL(urlString) else { return nil }
        return makeClient(url: url, token: token)
    }

    private func makeClient(url: URL, token: String?) -> JellyfinClient {
        let deviceIDKey = "jellyfin.deviceID"
        let deviceID = UserDefaults.standard.string(forKey: deviceIDKey) ?? {
            let value = UUID().uuidString
            UserDefaults.standard.set(value, forKey: deviceIDKey)
            return value
        }()
        let configuration = JellyfinClient.Configuration(
            url: url,
            accessToken: token,
            client: "Unified Media",
            deviceName: UIDevice.current.name,
            deviceID: deviceID,
            version: "1.0"
        )
        return JellyfinClient(configuration: configuration)
    }

    private func normalizedServerURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "" : "/\(basePath)"
        return components.url
    }

    private func mediaKind(for itemType: BaseItemKind?) -> MediaKind? {
        guard let itemType else { return nil }
        switch itemType {
        case .audio, .musicAlbum:
            return MediaKind.music
        case .audioBook, .book:
            return MediaKind.book
        case .episode, .movie, .musicVideo, .video:
            return MediaKind.video
        default:
            return nil
        }
    }

    private func mediaKind(for item: BaseItemDto) -> MediaKind? {
        if item.type == .book,
           item.tags?.contains(where: { $0.caseInsensitiveCompare("JellyEmu") == .orderedSame }) == true {
            return .game
        }
        return mediaKind(for: item.type)
    }

    private func imageURL(for item: BaseItemDto, serverURL: URL) -> URL? {
        guard let id = item.id, item.imageTags?["Primary"] != nil else { return nil }
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = "/" + [basePath, "Items", id, "Images", "Primary"].filter { !$0.isEmpty }.joined(separator: "/")
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "480"),
            URLQueryItem(name: "quality", value: "82"),
            URLQueryItem(name: "tag", value: item.imageTags?["Primary"]),
            URLQueryItem(name: "api_key", value: accessToken),
        ]
        return components?.url
    }
}

private struct JellyfinCredentials: Codable {
    let serverURL: String
    let username: String
    let userID: String
    let accessToken: String
}

private struct JellyfinCredentialStore {
    private let service = Bundle.main.bundleIdentifier ?? "app.unifiedmedia.ios"
    private let account = "jellyfin-session"

    func load() -> JellyfinCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(JellyfinCredentials.self, from: data)
    }

    func save(_ credentials: JellyfinCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = identity
            updates.forEach { insert[$0.key] = $0.value }
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw JellyfinProviderError.secureStorage(status) }
        } else if updateStatus != errSecSuccess {
            throw JellyfinProviderError.secureStorage(updateStatus)
        }
    }

    func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum JellyfinProviderError: LocalizedError {
    case incompleteAuthentication
    case secureStorage(OSStatus)
    case playbackUnavailable
    case noMediaSource
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .incompleteAuthentication:
            "The server signed in without returning a usable user session."
        case let .secureStorage(status):
            "iOS could not securely save the server session (Keychain status \(status))."
        case .playbackUnavailable:
            "This server item is not playable here. Music and video tracks can be played; books and albums are browse-only."
        case .noMediaSource:
            "The Jellyfin server did not provide a playable media source for this item."
        case .invalidStreamURL:
            "The Jellyfin server returned an invalid stream address."
        }
    }
}
