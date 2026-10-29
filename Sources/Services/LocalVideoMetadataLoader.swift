import AVFoundation
import Foundation
import UIKit

struct ImportedVideoMetadata: Sendable {
    let title: String
    let creator: String
    let duration: Double
    let artworkData: Data?
}

/// Reads common container tags and, when no poster art is embedded, creates a
/// small poster frame using AVFoundation's asynchronous image generator.
enum LocalVideoMetadataLoader {
    static func loadVideo(at url: URL, fallbackTitle: String) async -> ImportedVideoMetadata {
        var title = fallbackTitle
        var creator = ""
        var duration = 0.0
        var artworkData: Data?

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize >= 16 else {
            return ImportedVideoMetadata(title: title, creator: creator, duration: duration, artworkData: nil)
        }

        let asset = AVURLAsset(url: url)
        if let time = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite, seconds >= 0 { duration = seconds }
        }
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
                case .commonKeyArtist, .commonKeyAuthor:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { creator = value }
                case .commonKeyArtwork:
                    if let value = try? await item.load(.dataValue) { artworkData = value }
                default:
                    break
                }
            }
        }

        if artworkData == nil {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let sampleTime = duration > 0 ? min(1, duration / 3) : 0
            if let frame = try? await generator.image(at: CMTime(seconds: sampleTime, preferredTimescale: 600)).image {
                artworkData = UIImage(cgImage: frame).jpegData(compressionQuality: 0.82)
            }
        }

        return ImportedVideoMetadata(title: title, creator: creator, duration: duration, artworkData: artworkData)
    }
}
