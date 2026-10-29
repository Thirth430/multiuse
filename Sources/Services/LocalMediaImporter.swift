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
        [.audio, .movie, UTType(filenameExtension: "epub") ?? .data, UTType(filenameExtension: "cbz") ?? .data]
    }

    /// Copies selected documents into the app container so imports remain
    /// available after the security-scoped picker URL expires.
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> LocalImportSummary {
        var summary = LocalImportSummary()
        let directory = MediaLibraryRecord.importDirectory

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

            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.copyItem(at: sourceURL, to: URL(fileURLWithPath: destinationPath))
                }.value

                var title = sourceURL.deletingPathExtension().lastPathComponent
                var creator = ""
                var collection = ""
                var duration = 0.0
                var artworkFileName: String?
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
                summary.importedCount += 1
            } catch {
                summary.failures.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        do {
            try context.save()
        } catch {
            summary.failures.append("Could not save the library: \(error.localizedDescription)")
        }
        return summary
    }

    private static func mediaKind(for pathExtension: String) -> MediaKind? {
        switch pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "opus": .music
        case "mp4", "m4v", "mov": .video
        case "epub", "cbz": .book
        default: nil
        }
    }
}
