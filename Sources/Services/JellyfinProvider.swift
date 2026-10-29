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
    let overview: String
    let durationSeconds: Double
    let imageURL: URL?
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
                includeItemTypes: [.audio, .audioBook, .book, .episode, .movie, .musicAlbum, .video],
                enableUserData: true,
                imageTypeLimit: 1,
                enableImageTypes: [.primary],
                enableImages: true
            )
            let response = try await client.send(Paths.getItems(parameters: parameters))
            entries = (response.value.items ?? []).compactMap { item in
                guard let id = item.id, let title = item.name, let kind = mediaKind(for: item.type) else { return nil }
                let creator = item.albumArtist
                    ?? item.artists?.joined(separator: ", ")
                    ?? item.seriesName
                    ?? item.album
                    ?? ""
                return JellyfinLibraryEntry(
                    id: id,
                    title: title,
                    creator: creator,
                    kind: kind,
                    overview: item.overview ?? "",
                    durationSeconds: Double(item.runTimeTicks ?? 0) / 10_000_000,
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
        case .audio, .musicAlbum: .music
        case .audioBook, .book: .book
        case .episode, .movie, .musicVideo, .video: .video
        default: nil
        }
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

    var errorDescription: String? {
        switch self {
        case .incompleteAuthentication:
            "The server signed in without returning a usable user session."
        case let .secureStorage(status):
            "iOS could not securely save the server session (Keychain status \(status))."
        }
    }
}
