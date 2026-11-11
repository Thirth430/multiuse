import AVKit
import Combine
import SwiftData
import SwiftUI
import UIKit
private enum AppSection: String, CaseIterable, Identifiable {
    case home, music, video, book, game
    var id: Self { self }
    var title: String { self == .home ? "Home" : MediaKind(rawValue: rawValue)?.title ?? rawValue }
    var symbol: String { self == .home ? "sparkles" : MediaKind(rawValue: rawValue)?.symbol ?? "square.grid.2x2" }
}

private enum MusicBrowseMode: String, CaseIterable, Identifiable {
    case songs, albums, artists, playlists
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

private enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recentlyAdded, recentlyOpened, title
    var id: Self { self }
    var label: String {
        switch self {
        case .recentlyAdded: "Recently added"
        case .recentlyOpened: "Recently opened"
        case .title: "Title"
        }
    }
}

private struct MusicCollectionSelection: Identifiable {
    let id = UUID()
    let title: String
    let tracks: [MediaLibraryRecord]
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(JellyfinProvider.self) private var jellyfin
    @Query(sort: \MediaLibraryRecord.addedAt, order: .reverse) private var items: [MediaLibraryRecord]
    @Query(sort: \MusicPlaylist.updatedAt, order: .reverse) private var playlists: [MusicPlaylist]

    @State private var section: AppSection = .home
    @State private var showingImporter = false
    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var showingPlayer = false
    @State private var showingFullscreenVideo = false
    @State private var showingJellyfinLibrary = false
    @State private var showingPlaylistEditor = false
    @State private var showingPlaylistDetail = false
    @State private var musicBrowseMode: MusicBrowseMode = .songs
    @State private var editingPlaylist: MusicPlaylist?
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var selectedMusicCollection: MusicCollectionSelection?
    @State private var selectedHomeServerEntry: JellyfinLibraryEntry?
    @State private var selectedItem: MediaLibraryRecord?
    @State private var showingDetail = false
    @State private var alertMessage: String?
    @State private var gameSystemFilter: String?
    @State private var showFavoritesOnly = false
    @AppStorage("library.sortOrder") private var librarySortOrder = LibrarySortMode.recentlyAdded.rawValue
    @AppStorage("home.showLocalContinue") private var showLocalContinue = true
    @AppStorage("home.showServerContinue") private var showServerContinue = true
    @AppStorage("home.showRecentlyAdded") private var showRecentlyAdded = true
    private let progressTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MediaPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 25) {
                        if section == .home { homeContent } else { collectionContent }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }
                if playback.currentItem != nil && section != .book && section != .game { miniPlayer }
                tabBar
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: LocalMediaImporter.allowedContentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    let summary = await LocalMediaImporter.importFiles(urls, into: modelContext)
                    if !summary.failures.isEmpty { alertMessage = summary.failures.joined(separator: "\n") }
                    else if summary.importedCount == 0 { alertMessage = "No supported media files were imported." }
                }
            case .failure(let error): alertMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingSearch) {
            UnifiedSearchSheet(
                localItems: items,
                onOpenLocal: { item in open(item); showingSearch = false },
                onPlaybackStarted: { openPlayback(for: $0, closingSearch: true) },
                onDismiss: { showingSearch = false }
            )
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .sheet(isPresented: $showingPlayer) { NowPlayingSheet(showingFullscreenVideo: $showingFullscreenVideo) }
        .sheet(item: $selectedHomeServerEntry) { item in
            JellyfinEntryDetailSheet(item: item) {
                openPlayback(for: item.kind)
            }
        }
        .fullScreenCover(isPresented: $showingFullscreenVideo) { FullScreenVideoPlayer() }
        .sheet(isPresented: $showingJellyfinLibrary) {
            JellyfinLibrarySheet { kind in openPlayback(for: kind, closingJellyfinLibrary: true) }
        }
        .sheet(isPresented: $showingPlaylistEditor) {
            MusicPlaylistEditorSheet(
                tracks: items.filter { $0.kind == .music },
                playlist: editingPlaylist
            ) { name, selectedIDs in
                if let editingPlaylist {
                    let previousName = editingPlaylist.name
                    let previousIDs = editingPlaylist.itemIDs
                    editingPlaylist.name = name
                    editingPlaylist.itemIDs = selectedIDs
                    do { try modelContext.save() }
                    catch {
                        editingPlaylist.name = previousName
                        editingPlaylist.itemIDs = previousIDs
                        throw error
                    }
                } else {
                    let playlist = MusicPlaylist(name: name, itemIDs: selectedIDs)
                    modelContext.insert(playlist)
                    do { try modelContext.save() }
                    catch {
                        modelContext.delete(playlist)
                        throw error
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlaylistDetail) {
            if let selectedPlaylist {
                MusicPlaylistDetailSheet(
                    playlist: selectedPlaylist,
                    tracks: items.filter { $0.kind == .music }
                ) { tracks, index in
                    guard tracks.indices.contains(index) else { return }
                    playback.play(tracks[index], queue: tracks, startIndex: index)
                    showingPlaylistDetail = false
                    showingPlayer = true
                }
            }
        }
        .sheet(item: $selectedMusicCollection) { collection in
            MusicCollectionDetailSheet(title: collection.title, tracks: collection.tracks) { tracks, index in
                guard tracks.indices.contains(index) else { return }
                playback.play(tracks[index], queue: tracks, startIndex: index)
                selectedMusicCollection = nil
                showingPlayer = true
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let selectedItem {
                MediaDetailSheet(item: selectedItem) {
                    let queue = items.filter { $0.kind == selectedItem.kind }
                    let index = queue.firstIndex(where: { $0.id == selectedItem.id }) ?? 0
                    playback.play(selectedItem, queue: queue, startIndex: index)
                    showingDetail = false
                    if selectedItem.kind == .video { showingFullscreenVideo = true }
                    else { showingPlayer = true }
                }
            }
        }
        .alert("Unified Media", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
        .onReceive(progressTimer) { _ in playback.refreshProgress() }
        .task { await jellyfin.restoreConnection() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(MediaPalette.accent)
                .frame(width: 40, height: 40).background(MediaPalette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("ATLAS").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.2).foregroundStyle(MediaPalette.muted)
                Text(section == .home ? "Your worlds, together." : section.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            Spacer()
            Button { showingSearch = true } label: { headerIcon("magnifyingglass", label: "Search") }
            Button { showingImporter = true } label: { headerIcon("plus", label: "Import media") }
            Button { showingSettings = true } label: { headerIcon("slider.horizontal.3", label: "Settings") }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
    }

    private func headerIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 38, height: 38).background(MediaPalette.surface, in: Circle()).accessibilityLabel(label)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(MediaPalette.accent)
                Text("Find your next\nfavorite thing.")
                    .font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.6).foregroundStyle(.white)
                Text("One library for all the ways you unwind.").font(.system(size: 13, design: .rounded)).foregroundStyle(MediaPalette.muted)
            }
            if let current = playback.currentItem { continueCard(current) }
            else if let recent = items.filter({ $0.lastOpenedAt != nil }).max(by: {
                ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast)
            }) { recentCard(recent) }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Your library").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text("\(items.count) items").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(MediaPalette.muted)
                }
                HStack(spacing: 9) {
                    ForEach([MediaKind.music, .video, .book, .game]) { kind in
                        Button { section = AppSection(rawValue: kind.rawValue) ?? .home } label: {
                            VStack(alignment: .leading, spacing: 11) {
                                Image(systemName: kind.symbol).font(.system(size: 17, weight: .medium))
                                Text(kind.title).font(.system(size: 12, weight: .bold, design: .rounded))
                                Text("\(items.filter { $0.kind == kind }.count) items")
                                    .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.68))
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
                            .padding(10).background(categoryGradient(kind), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if jellyfin.isConnected { jellyfinServerCard }

            if showLocalContinue && !continueItems.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    ForEach(continueItems.prefix(5), id: \.id) { item in
                        ContinueMediaRow(item: item) { open(item) }
                    }
                }
            }

            if showServerContinue && !continueServerItems.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Continue on Jellyfin")
                        .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    ForEach(continueServerItems.prefix(5)) { item in
                        JellyfinEntryRow(item: item, showsProgress: true) { selectedHomeServerEntry = item }
                    }
                }
            }

            if items.isEmpty { emptyLibrary }
            else if showRecentlyAdded {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Recently added").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    ForEach(items.prefix(5), id: \.id) { item in MediaRow(item: item) { open(item) } }
                }
            }

            if showRecentlyAdded && !recentServerItems.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Recently added on Jellyfin")
                        .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    ForEach(recentServerItems.prefix(5)) { item in
                        JellyfinEntryRow(item: item) { selectedHomeServerEntry = item }
                    }
                }
            }
        }
    }

    private var continueItems: [MediaLibraryRecord] {
        let activeID = playback.currentItem?.id
        return items.filter { item in
            guard item.id != activeID else { return false }
            switch item.kind {
            case .music, .video:
                return item.progressSeconds > 15 &&
                    (item.durationSeconds <= 0 || item.progressSeconds < item.durationSeconds - 15)
            case .book:
                return item.readingProgression > 0 && item.readingProgression < 0.99
            case .game:
                return false
            }
        }
        .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private var continueServerItems: [JellyfinLibraryEntry] {
        guard jellyfin.isConnected else { return [] }
        return jellyfin.entries.filter { item in
            guard (item.kind == .music || item.kind == .video), item.isPlayable, item.resumeSeconds > 15 else { return false }
            return item.durationSeconds <= 0 || item.resumeSeconds < item.durationSeconds - 15
        }
        .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    private var recentServerItems: [JellyfinLibraryEntry] {
        guard jellyfin.isConnected else { return [] }
        return jellyfin.entries
            .filter { $0.dateAdded != nil && !$0.isAlbum && !$0.isArtist && !$0.isPlaylist }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }

    private var jellyfinServerCard: some View {
        Button { showingJellyfinLibrary = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "server.rack")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(MediaPalette.accent)
                    .frame(width: 42, height: 42).background(MediaPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(jellyfin.connectedServerName ?? "Jellyfin server")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("\(jellyfin.entries.count) server items · Browse library")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(MediaPalette.muted)
            }
            .padding(13).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    private var collectionContent: some View {
        let kind = MediaKind(rawValue: section.rawValue)
        let allCollection = items.filter { kind == nil || $0.kind == kind }
        let shouldFilterFavorites = showFavoritesOnly && !(section == .music && musicBrowseMode == .playlists)
        let collection = allCollection
            .filter { !shouldFilterFavorites || $0.isFavorite }
            .sorted(by: librarySortComparator)
        let serverCollection = jellyfinCollection(for: kind)
        let visibleServerCollection = serverCollection.filter { item in
            (!shouldFilterFavorites || item.isFavorite) &&
                (section != .game || gameSystemFilter == nil || item.gameSystem == gameSystemFilter)
        }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                if section == .music {
                    Button {
                        editingPlaylist = nil
                        showingPlaylistEditor = true
                    } label: {
                        Label("Playlist", systemImage: "plus").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(MediaPalette.accent)
                    }
                }
                Button { showingImporter = true } label: {
                    Label(section == .game ? "Add games" : "Import", systemImage: "plus").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(MediaPalette.accent)
                }
            }
            HStack {
                if section != .music || musicBrowseMode != .playlists {
                    filterChipButton(title: "Favorites", isSelected: showFavoritesOnly) { showFavoritesOnly.toggle() }
                }
                Spacer()
            }
            HStack(spacing: 7) {
                Image(systemName: "iphone").foregroundStyle(MediaPalette.accent)
                Text("On this device").foregroundStyle(.white)
                Spacer()
                Text(section == .music && musicBrowseMode == .playlists ? "\(playlists.count) playlists" : "\(collection.count) items")
                    .foregroundStyle(MediaPalette.muted)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            if section == .music {
                musicBrowsePicker
                switch musicBrowseMode {
                case .songs:
                    if collection.isEmpty { filteredCollectionEmptyState(for: kind, totalCount: allCollection.count) }
                    else { ForEach(collection, id: \.id) { item in MediaRow(item: item) { open(item) } } }
                case .albums: groupedMusicRows(collection, by: \.collection, fallback: "Unknown Album", totalCount: allCollection.count)
                case .artists: groupedMusicRows(collection, by: \.creator, fallback: "Unknown Artist", totalCount: allCollection.count)
                case .playlists: musicPlaylistSection
                }
            } else if section == .game {
                gameSystemPicker(collection, serverGames: serverCollection)
                let filteredGames = collection.filter { game in
                    if let gameSystemFilter, game.creator != gameSystemFilter { return false }
                    return true
                }
                if filteredGames.isEmpty {
                    if allCollection.isEmpty && serverCollection.isEmpty {
                        collectionEmptyState(for: kind)
                    } else if !visibleServerCollection.isEmpty {
                        ContentUnavailableView("No matching games on this device", systemImage: "gamecontroller", description: Text("Matching Jellyfin games are listed below."))
                    } else {
                        ContentUnavailableView("No games match these filters", systemImage: "gamecontroller", description: Text("Choose another system or favorite a game in this library."))
                    }
                } else {
                    ForEach(filteredGames, id: \.id) { item in MediaRow(item: item) { open(item) } }
                }
            } else if collection.isEmpty { filteredCollectionEmptyState(for: kind, totalCount: allCollection.count) }
            else { ForEach(collection, id: \.id) { item in MediaRow(item: item) { open(item) } } }
            if !visibleServerCollection.isEmpty {
                serverLibrarySection(visibleServerCollection, kind: kind)
            }
            if section == .game {
                Text("Local game files are cataloged by system. Emulation launch is unavailable until a compatible, licensed core runtime is integrated. No games or BIOS files are bundled.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 8)
    }

    private func jellyfinCollection(for kind: MediaKind?) -> [JellyfinLibraryEntry] {
        guard jellyfin.isConnected, let kind else { return [] }
        return jellyfin.entries
            .filter { item in
                guard item.kind == kind else { return false }
                guard kind == .music else { return true }
                switch musicBrowseMode {
                case .songs: return !item.isAlbum && !item.isArtist && !item.isPlaylist
                case .albums: return item.isAlbum
                case .artists: return item.isArtist
                case .playlists: return item.isPlaylist
                }
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func serverLibrarySection(_ entries: [JellyfinLibraryEntry], kind: MediaKind?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "server.rack").foregroundStyle(MediaPalette.accent)
                Text("On Jellyfin").foregroundStyle(.white)
                Spacer()
                Text("\(entries.count) items").foregroundStyle(MediaPalette.muted)
                if jellyfin.isLoading {
                    ProgressView().controlSize(.small).tint(MediaPalette.accent)
                } else {
                    Button {
                        Task { await jellyfin.refreshLibrary() }
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(MediaPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Jellyfin library")
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            ForEach(entries) { item in
                JellyfinEntryRow(item: item, showsProgress: item.resumeSeconds > 0) {
                    selectedHomeServerEntry = item
                }
            }
        }
        .padding(.top, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind?.title ?? "Media") from Jellyfin")
    }

    private var librarySortComparator: (MediaLibraryRecord, MediaLibraryRecord) -> Bool {
        let mode = LibrarySortMode(rawValue: librarySortOrder) ?? .recentlyAdded
        return { lhs, rhs in
            switch mode {
            case .recentlyAdded:
                return lhs.addedAt == rhs.addedAt
                    ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    : lhs.addedAt > rhs.addedAt
            case .recentlyOpened:
                let leftDate = lhs.lastOpenedAt ?? .distantPast
                let rightDate = rhs.lastOpenedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .title:
                let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return order == .orderedSame ? lhs.addedAt > rhs.addedAt : order == .orderedAscending
            }
        }
    }

    private var musicBrowsePicker: some View {
        HStack(spacing: 5) {
            ForEach(MusicBrowseMode.allCases) { mode in
                Button { musicBrowseMode = mode } label: {
                    Text(mode.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(musicBrowseMode == mode ? MediaPalette.background : MediaPalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(musicBrowseMode == mode ? MediaPalette.accent : MediaPalette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(MediaPalette.surface.opacity(0.62), in: Capsule())
    }

    private func gameSystemPicker(_ games: [MediaLibraryRecord], serverGames: [JellyfinLibraryEntry]) -> some View {
        let systems = Array(Set(games.map(\.creator).filter { !$0.isEmpty } + serverGames.compactMap(\.gameSystem)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterChipButton(title: "All systems", isSelected: gameSystemFilter == nil) { gameSystemFilter = nil }
                ForEach(systems, id: \.self) { system in
                    filterChipButton(title: system, isSelected: gameSystemFilter == system) { gameSystemFilter = system }
                }
            }
        }
    }

    @ViewBuilder
    private func groupedMusicRows(
        _ tracks: [MediaLibraryRecord],
        by keyPath: KeyPath<MediaLibraryRecord, String>,
        fallback: String,
        totalCount: Int
    ) -> some View {
        let groups = Dictionary(grouping: tracks) { item in
            let value = item[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? fallback : value
        }
        if groups.isEmpty {
            if totalCount == 0 {
                Text("Import tracks with album or artist tags to browse this view.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            } else {
                filteredCollectionEmptyState(for: .music, totalCount: totalCount)
            }
        } else {
            ForEach(groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { title in
                let groupTracks = (groups[title] ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                if let first = groupTracks.first {
                    Button { selectedMusicCollection = MusicCollectionSelection(title: title, tracks: groupTracks) } label: {
                        HStack(spacing: 11) {
                            MediaArtwork(kind: .music, size: 48, artworkURL: first.artworkURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                Text("\(groupTracks.count) songs · \(first.creator.isEmpty ? "Local library" : first.creator)")
                                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
                        }
                        .padding(9).background(MediaPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var musicPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Playlists").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Text("\(playlists.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(MediaPalette.muted)
            }
            if playlists.isEmpty {
                Text("Create a playlist from your imported tracks.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(playlists, id: \.id) { playlist in
                    HStack(spacing: 10) {
                        Button {
                            selectedPlaylist = playlist
                            showingPlaylistDetail = true
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "music.note.list").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(MediaPalette.accent).frame(width: 40, height: 40)
                                    .background(MediaPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                    Text("\(playlist.itemIDs.count) tracks").font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Menu {
                            Button("Edit playlist", systemImage: "pencil") {
                                editingPlaylist = playlist
                                showingPlaylistEditor = true
                            }
                            Button("Delete playlist", systemImage: "trash", role: .destructive) {
                                modelContext.delete(playlist)
                                do { try modelContext.save() }
                                catch {
                                    modelContext.insert(playlist)
                                    alertMessage = "The playlist could not be deleted: \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(MediaPalette.muted)
                                .frame(width: 36, height: 40).contentShape(Rectangle())
                        }
                    }
                    .padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 5)
                    .background(MediaPalette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring something in").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("Import music, movies, EPUBs, or CBZ comics. Files are copied into this app’s private library.")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            Button { showingImporter = true } label: {
                Label("Choose files", systemImage: "folder.badge.plus").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MediaPalette.background).padding(.horizontal, 15).padding(.vertical, 10).background(MediaPalette.accent, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(17).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func collectionEmptyState(for kind: MediaKind?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: kind?.symbol ?? "square.stack").font(.system(size: 23)).foregroundStyle(MediaPalette.accent)
            Text(kind == .book ? "No books yet" : kind == .game ? "Game library is not connected" : "Nothing here yet")
                .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(emptyDescription(for: kind)).font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            Button { showingImporter = true } label: {
                Label(kind == .game ? "Import game files" : "Import files", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .tint(MediaPalette.accent).padding(.top, 3)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func filteredCollectionEmptyState(for kind: MediaKind?, totalCount: Int) -> some View {
        if totalCount == 0 {
            collectionEmptyState(for: kind)
        } else {
            ContentUnavailableView("No favorites here", systemImage: "heart", description: Text("Mark an item as a favorite to see it in this library view."))
        }
    }

    private func emptyDescription(for kind: MediaKind?) -> String {
        switch kind {
        case .music: "Import audio files to build your local music library."
        case .video: "Import MP4, M4V, or MOV files to watch them here."
        case .book: "Open EPUB books and CBZ comics with Readium. CBR is not supported by the inspected Readium source."
        case .game: "Import supported ROM files to build a local catalog. Core-based emulation is not available yet."
        case nil: "Import local media or connect a server from Settings."
        }
    }

    private func continueCard(_ item: MediaLibraryRecord) -> some View {
        Button { showingPlayer = true } label: {
            VStack(alignment: .leading, spacing: 13) {
                Label("CONTINUE PLAYING", systemImage: item.kind.symbol)
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 5)
                Text(item.title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                HStack { Text(item.kind.title.uppercased()); Spacer(); Text("\(Int(playback.elapsedSeconds / 60)) MIN") }
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                ProgressView(value: playback.durationSeconds > 0 ? playback.elapsedSeconds / playback.durationSeconds : 0).tint(.white.opacity(0.9))
            }
            .padding(18).frame(height: 160, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.2, green: 0.4, blue: 0.55), Color(red: 0.1, green: 0.17, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 21))
        }
        .buttonStyle(.plain)
    }

    private func recentCard(_ item: MediaLibraryRecord) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 13) {
                MediaArtwork(kind: item.kind, size: 52, artworkURL: item.artworkURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PICK UP WHERE YOU LEFT OFF").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(MediaPalette.accent)
                    Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(item.kind.title).font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
            }
            .padding(13).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        HStack(spacing: 11) {
            if let item = playback.currentItem {
                MediaArtwork(kind: item.kind, size: 39, artworkURL: item.artworkURL)
                Button { showingPlayer = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        Text(item.kind.title).font(.system(size: 9, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing: \(item.title)")
                .accessibilityHint("Open playback controls")
                Button { playback.togglePlayback() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(MediaPalette.surface)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { tab in
                Button { withAnimation(.easeInOut(duration: 0.18)) { section = tab } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 16, weight: section == tab ? .semibold : .regular))
                        Text(tab.title).font(.system(size: 8, weight: section == tab ? .bold : .medium, design: .rounded))
                    }
                    .foregroundStyle(section == tab ? MediaPalette.accent : MediaPalette.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    private func filterChipButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? MediaPalette.background : MediaPalette.muted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isSelected ? MediaPalette.accent : MediaPalette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func open(_ item: MediaLibraryRecord) { selectedItem = item; showingDetail = true }

    private func openPlayback(for kind: MediaKind, closingSearch: Bool = false, closingJellyfinLibrary: Bool = false) {
        if closingSearch { showingSearch = false }
        if closingJellyfinLibrary { showingJellyfinLibrary = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if kind == .video { showingFullscreenVideo = true }
            else { showingPlayer = true }
        }
    }

    private func categoryGradient(_ kind: MediaKind) -> LinearGradient {
        let colors: [Color]
        switch kind {
        case .music: colors = [.purple.opacity(0.75), .indigo.opacity(0.42)]
        case .video: colors = [.orange.opacity(0.75), .pink.opacity(0.35)]
        case .book: colors = [.teal.opacity(0.75), .cyan.opacity(0.35)]
        case .game: colors = [.blue.opacity(0.75), .mint.opacity(0.32)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct ContinueMediaRow: View {
    let item: MediaLibraryRecord
    let action: () -> Void

    private var progress: Double {
        if item.kind == .book { return min(max(item.readingProgression, 0), 1) }
        guard item.durationSeconds > 0 else { return 0 }
        return min(max(item.progressSeconds / item.durationSeconds, 0), 1)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MediaArtwork(kind: item.kind, size: 48, artworkURL: item.artworkURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(item.kind == .book ? "\(Int(progress * 100))% read" : "\(Int(progress * 100))% complete")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    ProgressView(value: progress).tint(MediaPalette.accent)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
            }
            .padding(9).background(MediaPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
private struct SettingsSheet: View {
    @Environment(JellyfinProvider.self) private var jellyfin
    @AppStorage("library.sortOrder") private var librarySortOrder = LibrarySortMode.recentlyAdded.rawValue
    @AppStorage("home.showLocalContinue") private var showLocalContinue = true
    @AppStorage("home.showServerContinue") private var showServerContinue = true
    @AppStorage("home.showRecentlyAdded") private var showRecentlyAdded = true

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Label("Local files", systemImage: "folder")
                    Picker("Sort libraries by", selection: $librarySortOrder) {
                        ForEach(LibrarySortMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                }
                Section("Home screen") {
                    Toggle("Continue on this device", isOn: $showLocalContinue)
                    Toggle("Continue on Jellyfin", isOn: $showServerContinue)
                    Toggle("Recently added", isOn: $showRecentlyAdded)
                }
                Section("Jellyfin server") {
                    if jellyfin.isConnected {
                        Label(jellyfin.connectedServerName ?? "Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(jellyfin.entries.count) music, video, and book items loaded")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Server browsing, AVPlayer streaming, and progress reporting are wired; live-server playback checks remain.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            Task { await jellyfin.refreshLibrary() }
                        } label: {
                            Label(jellyfin.isLoading ? "Refreshing…" : "Refresh library", systemImage: "arrow.clockwise")
                        }
                        .disabled(jellyfin.isLoading)
                        Button("Disconnect server", role: .destructive) {
                            Task { await jellyfin.disconnect() }
                        }
                    } else {
                        TextField("https://your-jellyfin-server", text: Binding(
                            get: { jellyfin.serverAddress },
                            set: { jellyfin.serverAddress = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        TextField("Username", text: Binding(
                            get: { jellyfin.username },
                            set: { jellyfin.username = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        SecureField("Password", text: Binding(
                            get: { jellyfin.password },
                            set: { jellyfin.password = $0 }
                        ))
                        Button {
                            Task { await jellyfin.connect() }
                        } label: {
                            Label(jellyfin.isLoading ? "Connecting…" : "Connect to Jellyfin", systemImage: "server.rack")
                        }
                        .disabled(jellyfin.isLoading)
                    }
                    if let error = jellyfin.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Playback") {
                    Label("Music and video currently use Apple AVPlayer.", systemImage: "play.circle")
                    Text("Format coverage, background behavior, subtitle selection, and remote controls need device verification.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Reading and games") {
                    Label("EPUB and CBZ reading use Readium. Game runtime is not connected yet.", systemImage: "book.closed")
                    Text("The Fast Serif reading option is included from Fast-Font.").font(.caption).foregroundStyle(.secondary)
                    Text("EPUB and CBZ can be imported. CBR is not supported by the inspected Readium source.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(MediaPalette.background)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
    }
}
