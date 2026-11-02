import SwiftUI
import UIKit

enum MediaPalette {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.102, blue: 0.145)
    static let muted = Color(red: 0.62, green: 0.66, blue: 0.75)
    static let accent = Color(red: 0.49, green: 0.75, blue: 0.98)
}

struct MediaArtwork: View {
    let kind: MediaKind
    let size: CGFloat
    var artworkURL: URL? = nil
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(MediaPalette.accent.opacity(0.15))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: kind.symbol).font(.system(size: size * 0.34, weight: .medium)).foregroundStyle(MediaPalette.accent)
                }
            }
            .frame(width: size, height: size)
            .task(id: artworkURL) {
                guard let artworkURL else { image = nil; return }
                let data = await ArtworkDataCache.shared.data(for: artworkURL)
                guard !Task.isCancelled else { return }
                image = data.flatMap(UIImage.init(data:))
            }
    }
}
