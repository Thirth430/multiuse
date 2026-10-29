import AVFoundation
import Foundation

struct ImportedAudioMetadata: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkData: Data?
}

/// Selective adaptation of LocalMusic's AVFoundation metadata reader. It
/// preserves its tag-first title, artist, album, duration, and artwork behavior
/// while keeping the unified library's own catalog model and interface.
enum LocalMusicMetadataLoader {
    static func loadAudio(at url: URL) async -> ImportedAudioMetadata {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration = 0.0
        var artworkData: Data?

        if let time = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite, seconds >= 0 { duration = seconds }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        album = value
                    }
                case .commonKeyArtwork:
                    if let value = try? await item.load(.dataValue) {
                        artworkData = value
                    }
                default:
                    break
                }
            }
        }

        return ImportedAudioMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkData: artworkData
        )
    }
}

enum MediaArtworkStore {
    private static var directory: URL {
        MediaLibraryRecord.importDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }

    static func save(_ data: Data) async -> String? {
        let fileName = "\(UUID().uuidString).art"
        let directory = self.directory
        let destination = directory.appendingPathComponent(fileName)
        return await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                return fileName
            } catch {
                return nil
            }
        }.value
    }
}
