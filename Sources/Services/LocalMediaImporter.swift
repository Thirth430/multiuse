import Foundation
import SwiftData
import UniformTypeIdentifiers

struct LocalImportSummary: Sendable {
    var importedCount = 0
    var failures: [String] = []
}

@MainActor
enum LocalMediaImporter {
    static var allowedContentTypes: [UTType] {
        let gameTypes = ["nes", "gb", "gbc", "gba", "sfc", "smc", "n64", "z64", "nds", "gen", "md", "sms", "gg", "pce"]
            .compactMap { UTType(filenameExtension: $0) }
        return [.audio, .movie, UTType(filenameExtension: "epub") ?? .data, UTType(filenameExtension: "cbz") ?? .data] + gameTypes
    }

    /// Copies selected documents into the app container so imports remain
    /// available after the security-scoped picker URL expires.
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> LocalImportSummary {
        var summary = LocalImportSummary()
        let directory = MediaLibraryRecord.importDirectory
        var importedRecords: [MediaLibraryRecord] = []

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            summary.failures.append("Could not create the media library: \(error.localizedDescription)")
            return summary
        }

        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }

            guard let kind = mediaKind(for: sourceURL.pathExtension) else {
                summary.failures.append("Unsupported file: \(sourceURL.lastPathComponent)")
                continue
            }

            let extensionName = sourceURL.pathExtension.lowercased()
            let destinationName = "\(UUID().uuidString).\(extensionName)"
            let destinationPath = directory.appendingPathComponent(destinationName).path
            var artworkFileName: String?

            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.copyItem(at: sourceURL, to: URL(fileURLWithPath: destinationPath))
                }.value

                var title = sourceURL.deletingPathExtension().lastPathComponent
                var creator = ""
                var collection = ""
                var duration = 0.0
                if kind == .music {
                    let metadata = await LocalMusicMetadataLoader.loadAudio(
                        at: URL(fileURLWithPath: destinationPath),
                        fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent
                    )
                    title = metadata.title
                    creator = metadata.artist
                    collection = metadata.album
                    duration = metadata.duration
                    if let artworkData = metadata.artworkData {
                        artworkFileName = await MediaArtworkStore.save(artworkData)
                    }
                } else if kind == .video {
                    let metadata = await LocalVideoMetadataLoader.loadVideo(
                        at: URL(fileURLWithPath: destinationPath),
                        fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent
                    )
                    title = metadata.title
                    creator = metadata.creator
                    duration = metadata.duration
                    if let artworkData = metadata.artworkData {
                        artworkFileName = await MediaArtworkStore.save(artworkData)
                    }
                } else if kind == .game, let system = gameSystem(for: extensionName) {
                    creator = system
                    collection = system
                }

                let record = MediaLibraryRecord(
                    kind: kind,
                    title: title,
                    creator: creator,
                    collection: collection,
                    fileName: destinationName,
                    fileExtension: extensionName,
                    artworkFileName: artworkFileName
                )
                record.durationSeconds = duration
                context.insert(record)
                importedRecords.append(record)
                summary.importedCount += 1
            } catch {
                try? FileManager.default.removeItem(atPath: destinationPath)
                if let artworkFileName {
                    let artworkURL = directory.appendingPathComponent("Artwork", isDirectory: true).appendingPathComponent(artworkFileName)
                    try? FileManager.default.removeItem(at: artworkURL)
                }
                summary.failures.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        do {
            try context.save()
        } catch {
            for record in importedRecords {
                context.delete(record)
                try? FileManager.default.removeItem(at: record.localURL)
                if let artworkURL = record.artworkURL {
                    try? FileManager.default.removeItem(at: artworkURL)
                }
            }
            summary.importedCount = 0
            summary.failures.append("Could not save the library: \(error.localizedDescription)")
        }
        return summary
    }

    private static func mediaKind(for pathExtension: String) -> MediaKind? {
        switch pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "opus": .music
        case "mp4", "m4v", "mov": .video
        case "epub", "cbz": .book
        case "nes", "gb", "gbc", "gba", "sfc", "smc", "n64", "z64", "nds", "gen", "md", "sms", "gg", "pce": .game
        default: nil
        }
    }

    private static func gameSystem(for fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "nes": "NES"
        case "gb": "Game Boy"
        case "gbc": "Game Boy Color"
        case "gba": "Game Boy Advance"
        case "sfc", "smc": "Super Nintendo"
        case "n64", "z64": "Nintendo 64"
        case "nds": "Nintendo DS"
        case "gen", "md": "Sega Genesis / Mega Drive"
        case "sms": "Sega Master System"
        case "gg": "Game Gear"
        case "pce": "TurboGrafx-16"
        default: nil
        }
    }
}
