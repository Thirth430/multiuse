import SwiftUI
import UIKit

struct RemoteArtwork: View {
    let kind: MediaKind
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MediaPalette.accent.opacity(0.15))
                    .overlay(Image(systemName: kind.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(MediaPalette.accent))
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let data = await ArtworkDataCache.shared.data(for: url)
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

@MainActor
private func startJellyfinPlayback(
    _ entry: JellyfinLibraryEntry,
    provider: JellyfinProvider,
    playback: PlaybackCoordinator,
    queue serverQueue: [JellyfinLibraryEntry] = [],
    startIndex: Int = 0
) async -> Bool {
    do {
        let entries = serverQueue.isEmpty ? [entry] : serverQueue
        let selectedIndex = min(max(startIndex, 0), entries.count - 1)
        let selectedEntry = entries[selectedIndex]
        let session = try await provider.preparePlayback(for: selectedEntry)
        let records = entries.map { entry in
            let record = MediaLibraryRecord(
                id: "jellyfin:\(entry.id)",
                providerID: entry.id,
                origin: "Jellyfin",
                kind: entry.kind,
                title: entry.title,
                creator: entry.creator,
                fileName: entry.id,
                fileExtension: ""
            )
            record.progressSeconds = entry.resumeSeconds
            record.durationSeconds = entry.durationSeconds
            return record
        }
        playback.playRemote(
            records[selectedIndex],
            session: session,
            provider: provider,
            queue: records,
            serverQueue: entries,
            startIndex: selectedIndex
        )
        return true
    } catch {
        provider.handlePlaybackFailure(error)
        return false
    }
}

struct JellyfinEntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinProvider.self) private var jellyfin
    @Environment(PlaybackCoordinator.self) private var playback
    let item: JellyfinLibraryEntry
    let onPlaybackStarted: () -> Void
    @State private var isStartingPlayback = false
    @State private var gameConfiguration: JellyEmuGameConfiguration?
    @State private var showingGamePlayer = false
    @State private var albumTracks: [JellyfinLibraryEntry] = []
    @State private var isLoadingAlbumTracks = false
    @State private var albumTracksError: String?
    @State private var artistAlbums: [JellyfinLibraryEntry] = []
    @State private var isLoadingArtistAlbums = false
    @State private var artistAlbumsError: String?
    @State private var selectedArtistAlbum: JellyfinLibraryEntry?

    private var isFavorite: Bool {
        jellyfin.entries.first(where: { $0.id == item.id })?.isFavorite ?? item.isFavorite
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteArtwork(kind: item.kind, url: item.imageURL)
                        .frame(maxWidth: .infinity).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20))

                    Text(item.title).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text([item.gameSystem ?? "", item.creator, item.kind.title, "Jellyfin"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    if !item.overview.isEmpty {
                        Text(item.overview).font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.84))
                    }
                    if item.isAlbum || item.isPlaylist { albumTracksSection }
                    if item.isArtist { artistAlbumsSection }
                    favoriteButton
                    if let error = jellyfin.errorMessage {
                        Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(.red)
                    }
                    primaryAction
                }
                .padding(20)
            }
            .background(MediaPalette.background)
            .navigationTitle("Jellyfin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
        .sheet(item: $selectedArtistAlbum) { album in
            JellyfinEntryDetailSheet(item: album) {
                dismiss()
                onPlaybackStarted()
            }
        }
        .fullScreenCover(isPresented: $showingGamePlayer) {
            if let gameConfiguration {
                JellyEmuGamePlayer(configuration: gameConfiguration)
            }
        }
        .task(id: item.id) { await loadItemChildren() }
    }

    @ViewBuilder
    private var albumTracksSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Tracks").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                if !albumTracks.isEmpty {
                    Button("Play All", systemImage: "play.fill") {
                        Task { await startPlayback(albumTracks[0], queue: albumTracks) }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tint(MediaPalette.accent)
                    .disabled(isStartingPlayback)
                }
            }
            if isLoadingAlbumTracks {
                ProgressView("Loading tracks…").tint(MediaPalette.accent)
            } else if let albumTracksError {
                Text(albumTracksError).font(.system(size: 12, design: .rounded)).foregroundStyle(.red)
            } else if albumTracks.isEmpty {
                Text(item.isPlaylist ? "This playlist has no available tracks." : "This album has no available tracks.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            } else {
                ForEach(albumTracks.indices, id: \.self) { index in
                    let track = albumTracks[index]
                    HStack(spacing: 10) {
                        MediaArtwork(kind: .music, size: 38, artworkURL: track.imageURL)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                            Text(track.creator).font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button { Task { await startPlayback(track, queue: albumTracks, startIndex: index) } } label: {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(MediaPalette.accent)
                                .frame(width: 36, height: 36).background(MediaPalette.surface, in: Circle())
                        }
                        .disabled(isStartingPlayback)
                        .accessibilityLabel("Play \(track.title)")
                    }
                    .padding(8).background(MediaPalette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                }
            }
        }
    }

    @ViewBuilder
    private var artistAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Albums").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
            if isLoadingArtistAlbums {
                ProgressView("Loading albums…").tint(MediaPalette.accent)
            } else if let artistAlbumsError {
                Text(artistAlbumsError).font(.system(size: 12, design: .rounded)).foregroundStyle(.red)
            } else if artistAlbums.isEmpty {
                Text("This artist has no available albums.").font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            } else {
                ForEach(artistAlbums) { album in
                    Button { selectedArtistAlbum = album } label: {
                        HStack(spacing: 10) {
                            MediaArtwork(kind: .music, size: 42, artworkURL: album.imageURL)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(album.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                Text(album.creator).font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
                        }
                        .padding(8).background(MediaPalette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var favoriteButton: some View {
        Button {
            Task { await jellyfin.setFavorite(itemID: item.id, isFavorite: !isFavorite) }
        } label: {
            Label(isFavorite ? "Favorited on Jellyfin" : "Add to Favorites", systemImage: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isFavorite ? .pink : MediaPalette.accent)
                .frame(maxWidth: .infinity).padding(12)
                .background(MediaPalette.surface, in: Capsule())
        }
        .disabled(jellyfin.favoriteUpdatingIDs.contains(item.id))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if item.kind == .game {
            Button {
                guard let configuration = jellyfin.gamePlayerConfiguration(for: item) else {
                    jellyfin.handlePlaybackFailure(JellyfinGameError.unavailable)
                    return
                }
                gameConfiguration = configuration
                showingGamePlayer = true
            } label: {
                Label("Play with JellyEmu", systemImage: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MediaPalette.background).frame(maxWidth: .infinity).padding(14)
                    .background(MediaPalette.accent, in: Capsule())
            }
            Text("Game playback is provided by the JellyEmu server plugin.")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(MediaPalette.muted)
        } else if item.isPlayable {
            Button {
                Task { await startPlayback(item) }
            } label: {
                Label(isStartingPlayback ? "Connecting…" : "Play", systemImage: isStartingPlayback ? "hourglass" : "play.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MediaPalette.background).frame(maxWidth: .infinity).padding(14)
                    .background(MediaPalette.accent, in: Capsule())
            }
            .disabled(isStartingPlayback)
        } else {
            Label(
                item.isAlbum || item.isPlaylist ? "Choose a track above to play" : item.isArtist ? "Choose an album above to browse tracks" : item.kind == .book ? "Server books are browse-only here" : "This server item can’t be played here",
                systemImage: item.isAlbum || item.isPlaylist ? "music.note.list" : item.isArtist ? "music.mic" : "info.circle"
            )
            .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @MainActor
    private func startPlayback(_ entry: JellyfinLibraryEntry, queue: [JellyfinLibraryEntry] = [], startIndex: Int = 0) async {
        isStartingPlayback = true
        let started = await startJellyfinPlayback(entry, provider: jellyfin, playback: playback, queue: queue, startIndex: startIndex)
        isStartingPlayback = false
        if started {
            dismiss()
            onPlaybackStarted()
        }
    }

    @MainActor
    private func loadItemChildren() async {
        if item.isAlbum || item.isPlaylist {
            isLoadingAlbumTracks = true
            albumTracksError = nil
            defer { isLoadingAlbumTracks = false }
            do {
                albumTracks = try await jellyfin.tracks(in: item)
            } catch {
                albumTracksError = "Could not load album tracks: \(error.localizedDescription)"
            }
        } else if item.isArtist {
            isLoadingArtistAlbums = true
            artistAlbumsError = nil
            defer { isLoadingArtistAlbums = false }
            do {
                artistAlbums = try await jellyfin.albums(for: item)
            } catch {
                artistAlbumsError = "Could not load artist albums: \(error.localizedDescription)"
            }
        }
    }
}

private enum JellyfinGameError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The JellyEmu player URL is unavailable. Reconnect to the Jellyfin server and try again." }
}

struct JellyfinEntryRow: View {
    let item: JellyfinLibraryEntry
    var showsProgress = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            RemoteArtwork(kind: item.kind, url: item.imageURL)
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Text([item.gameSystem ?? "", item.creator, item.kind.title, "Jellyfin"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                if showsProgress && item.durationSeconds > 0 {
                    ProgressView(value: min(max(item.resumeSeconds / item.durationSeconds, 0), 1))
                        .tint(MediaPalette.accent)
                        .accessibilityLabel("Playback progress")
                }
            }
            Spacer()
            if item.isFavorite {
                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.pink)
            }
            Image(systemName: "server.rack").font(.system(size: 11)).foregroundStyle(MediaPalette.muted)
        }
        .padding(9).background(MediaPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
    }
}
