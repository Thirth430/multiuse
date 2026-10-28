import Foundation
import SwiftData

/// The shared catalog identity used by all media providers.
enum MediaKind: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case music, video, book, game

    var id: Self { self }
    var title: String {
        switch self {
        case .music: "Music"
        case .video: "Video"
        case .book: "Books"
        case .game: "Games"
        }
    }
    var symbol: String {
        switch self {
        case .music: "waveform"
        case .video: "play.rectangle"
        case .book: "book.closed"
        case .game: "gamecontroller"
        }
    }
}

/// Normalized media record. Provider identity is retained for future adapters.
@Model
final class MediaLibraryRecord {
    @Attribute(.unique) var id: String
    var providerID: String
    var origin: String
    var kindValue: String
    var title: String
    var creator: String
    var collection: String
    var fileName: String
    var fileExtension: String
    var addedAt: Date
    var lastOpenedAt: Date?
    var progressSeconds: Double
    var durationSeconds: Double
    var isFavorite: Bool

    init(
        id: String = "local:\(UUID().uuidString)",
        providerID: String? = nil,
        origin: String = "local",
        kind: MediaKind,
        title: String,
        creator: String = "",
        collection: String = "",
        fileName: String,
        fileExtension: String,
        addedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID ?? id
        self.origin = origin
        self.kindValue = kind.rawValue
        self.title = title
        self.creator = creator
        self.collection = collection
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.addedAt = addedAt
        self.progressSeconds = 0
        self.durationSeconds = 0
        self.isFavorite = false
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindValue) ?? .video }
        set { kindValue = newValue.rawValue }
    }

    var localURL: URL { Self.importDirectory.appendingPathComponent(fileName) }

    static var importDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UnifiedMedia/Imports", isDirectory: true)
    }
}
