import SwiftData
import SwiftUI

struct MediaRow: View {
    let item: MediaLibraryRecord
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MediaArtwork(kind: item.kind, size: 48, artworkURL: item.artworkURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text([item.creator, item.kind.title, item.origin].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                }
                Spacer()
                if item.isFavorite { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.pink) }
                if !FileManager.default.fileExists(atPath: item.localURL.path) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Imported file missing")
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
            }
            .padding(9).background(MediaPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}


struct MediaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackCoordinator.self) private var playback
    @Query(sort: \MusicPlaylist.updatedAt, order: .reverse) private var playlists: [MusicPlaylist]
    @State private var showingRemovalConfirmation = false
    @State private var removalError: String?
    @State private var removalDidCommit = false
    @State private var favoriteError: String?
    @State private var showingReader = false
    let item: MediaLibraryRecord
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(MediaPalette.muted).padding(10).background(MediaPalette.surface, in: Circle()) } }
            MediaArtwork(kind: item.kind, size: 92, artworkURL: item.artworkURL).frame(maxWidth: .infinity)
            Text(item.title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("\(item.kind.title) · \(item.fileExtension.uppercased()) · \(item.creator.isEmpty ? item.origin : item.creator)")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            if !fileIsAvailable {
                Label("This imported file is missing. Remove it and import it again to use this item.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.kind == .music || item.kind == .video {
                Button(action: play) {
                    Label(fileIsAvailable ? "Play" : "File unavailable", systemImage: fileIsAvailable ? "play.fill" : "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(MediaPalette.background).frame(maxWidth: .infinity).padding(14).background(MediaPalette.accent, in: Capsule())
                }
                .disabled(!fileIsAvailable)
            } else if item.kind == .game {
                VStack(alignment: .leading, spacing: 8) {
                    Label(fileIsAvailable ? "Game file saved" : "Game file missing", systemImage: fileIsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(fileIsAvailable ? .green : .orange)
                    Text("The local catalog recognizes this system, but no compatible emulator core is linked yet.")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    Button {} label: {
                        Label("Launch unavailable", systemImage: "gamecontroller")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MediaPalette.muted).frame(maxWidth: .infinity).padding(13)
                            .background(MediaPalette.surface, in: Capsule())
                    }
                    .disabled(true)
                }
                .padding(14).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 15))
            } else if item.kind == .book {
                Button { showingReader = true } label: {
                    Label(item.fileExtension == "cbz" ? "Read comic" : "Read book", systemImage: "book.open.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(MediaPalette.background)
                        .frame(maxWidth: .infinity).padding(14).background(MediaPalette.accent, in: Capsule())
                }
                .disabled(!fileIsAvailable)
            }
            HStack {
                Button(action: toggleFavorite) {
                    Label(item.isFavorite ? "Favorited" : "Favorite", systemImage: item.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .tint(item.isFavorite ? .pink : MediaPalette.accent)
                Spacer()
                Button(role: .destructive) {
                    showingRemovalConfirmation = true
                } label: { Label("Remove", systemImage: "trash") }.font(.system(size: 12, weight: .medium, design: .rounded))
            }
            Spacer()
        }
        .padding(22).background(MediaPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large]).preferredColorScheme(.dark)
        .confirmationDialog("Remove from your library?", isPresented: $showingRemovalConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: removeFromLibrary)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\u{201C}\(item.title)\u{201D}, its imported file, and its saved artwork will be removed from this device.")
        }
        .alert(removalDidCommit ? "Removed with cleanup issue" : "Couldn’t remove media", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {
                removalError = nil
                if removalDidCommit { dismiss() }
            }
        } message: {
            Text(removalError ?? "")
        }
        .alert("Couldn’t save favorite", isPresented: Binding(get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } })) {
            Button("OK", role: .cancel) { favoriteError = nil }
        } message: {
            Text(favoriteError ?? "")
        }
        .sheet(isPresented: $showingReader) {
            ReadiumBookReader(item: item)
                .preferredColorScheme(.light)
        }
    }

    private var fileIsAvailable: Bool {
        FileManager.default.fileExists(atPath: item.localURL.path)
    }

    private func toggleFavorite() {
        let previousValue = item.isFavorite
        item.isFavorite.toggle()
        do {
            try modelContext.save()
        } catch {
            item.isFavorite = previousValue
            favoriteError = "Your favorite change wasn’t saved: \(error.localizedDescription)"
        }
    }

    private func removeFromLibrary() {
        let removedID = item.id
        let affectedPlaylists = playlists.filter { $0.itemIDs.contains(removedID) }.map { ($0, $0.itemIDs) }
        for (playlist, _) in affectedPlaylists {
            playlist.itemIDs.removeAll { $0 == removedID }
        }
        let localURL = item.localURL
        let artworkURL = item.artworkURL
        modelContext.delete(item)
        do {
            try modelContext.save()
            playback.removeFromQueue(itemID: removedID)
            var cleanupFailures: [String] = []
            if FileManager.default.fileExists(atPath: localURL.path) {
                do { try FileManager.default.removeItem(at: localURL) }
                catch { cleanupFailures.append("media file") }
            }
            if let artworkURL {
                if FileManager.default.fileExists(atPath: artworkURL.path) {
                    do { try FileManager.default.removeItem(at: artworkURL) }
                    catch { cleanupFailures.append("artwork") }
                }
            }
            if cleanupFailures.isEmpty {
                dismiss()
            } else {
                removalDidCommit = true
                removalError = "The item was removed from your library, but its \(cleanupFailures.joined(separator: " and ")) could not be deleted from this device."
            }
        } catch {
            modelContext.insert(item)
            for (playlist, previousIDs) in affectedPlaylists {
                playlist.itemIDs = previousIDs
            }
            removalError = "The item could not be removed: \(error.localizedDescription)"
        }
    }
}


