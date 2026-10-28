import AVKit
import Combine
import SwiftData
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case home, music, video, book, game
    var id: Self { self }
    var title: String { self == .home ? "Home" : MediaKind(rawValue: rawValue)?.title ?? rawValue }
    var symbol: String { self == .home ? "sparkles" : MediaKind(rawValue: rawValue)?.symbol ?? "square.grid.2x2" }
}

private enum MediaPalette {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.102, blue: 0.145)
    static let muted = Color(red: 0.62, green: 0.66, blue: 0.75)
    static let accent = Color(red: 0.49, green: 0.75, blue: 0.98)
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackCoordinator.self) private var playback
    @Query(sort: \MediaLibraryRecord.addedAt, order: .reverse) private var items: [MediaLibraryRecord]

    @State private var section: AppSection = .home
    @State private var showingImporter = false
    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var showingPlayer = false
    @State private var selectedItem: MediaLibraryRecord?
    @State private var showingDetail = false
    @State private var alertMessage: String?
    @State private var searchText = ""
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
        .sheet(isPresented: $showingSearch) { searchSheet }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .sheet(isPresented: $showingPlayer) { NowPlayingSheet() }
        .sheet(isPresented: $showingDetail) {
            if let selectedItem {
                MediaDetailSheet(item: selectedItem) {
                    playback.play(selectedItem)
                    showingDetail = false
                    showingPlayer = true
                }
            }
        }
        .alert("Unified Media", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
        .onReceive(progressTimer) { _ in playback.refreshProgress() }
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

            if items.isEmpty { emptyLibrary }
            else {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Recently added").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    ForEach(items.prefix(5), id: \.id) { item in MediaRow(item: item) { open(item) } }
                }
            }
        }
    }

    private var collectionContent: some View {
        let kind = MediaKind(rawValue: section.rawValue)
        let collection = items.filter { kind == nil || $0.kind == kind }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                if section != .game {
                    Button { showingImporter = true } label: {
                        Label("Import", systemImage: "plus").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(MediaPalette.accent)
                    }
                }
            }
            if collection.isEmpty { collectionEmptyState(for: kind) }
            else { ForEach(collection, id: \.id) { item in MediaRow(item: item) { open(item) } } }
            if section == .game {
                Text("Game runtime is planned. No emulator cores or game files are bundled.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 8)
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
            if kind != .game {
                Button { showingImporter = true } label: { Label("Import files", systemImage: "plus").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                    .tint(MediaPalette.accent).padding(.top, 3)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func emptyDescription(for kind: MediaKind?) -> String {
        switch kind {
        case .music: "Import audio files to build your local music library."
        case .video: "Import MP4, M4V, or MOV files to watch them here."
        case .book: "EPUB and CBZ import is available. Readium reading is the next integration step. CBR is not supported by the inspected Readium source."
        case .game: "The game catalog and emulator runtime are not connected yet."
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
                MediaArtwork(kind: item.kind, size: 52)
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
                MediaArtwork(kind: item.kind, size: 39)
                Button { showingPlayer = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        Text(item.kind.title).font(.system(size: 9, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
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

    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MediaPalette.muted)
                    TextField("Search books, music, video…", text: $searchText).textInputAutocapitalization(.never)
                }
                .padding(13).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 13))
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(searchResults, id: \.id) { item in MediaRow(item: item) { open(item); showingSearch = false } }
                    }
                }
                if searchText.isEmpty {
                    Text("Search imported media here. Jellyfin results will join when the server provider is connected.")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18).background(MediaPalette.background)
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingSearch = false } } }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
    }

    private var searchResults: [MediaLibraryRecord] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter {
            let haystack = "\($0.title) \($0.creator) \($0.collection) \($0.kind.title)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(query)
        }
    }

    private func open(_ item: MediaLibraryRecord) { selectedItem = item; showingDetail = true }

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

private struct MediaRow: View {
    let item: MediaLibraryRecord
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MediaArtwork(kind: item.kind, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text([item.creator, item.kind.title, item.origin].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                }
                Spacer()
                if item.isFavorite { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.pink) }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
            }
            .padding(9).background(MediaPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

private struct MediaArtwork: View {
    let kind: MediaKind
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(MediaPalette.accent.opacity(0.15))
            .overlay(Image(systemName: kind.symbol).font(.system(size: size * 0.34, weight: .medium)).foregroundStyle(MediaPalette.accent))
            .frame(width: size, height: size)
    }
}

private struct MediaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: MediaLibraryRecord
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(MediaPalette.muted).padding(10).background(MediaPalette.surface, in: Circle()) } }
            MediaArtwork(kind: item.kind, size: 92).frame(maxWidth: .infinity)
            Text(item.title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("\(item.kind.title) · \(item.fileExtension.uppercased()) · \(item.origin)")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            if item.kind == .music || item.kind == .video {
                Button(action: play) {
                    Label("Play", systemImage: "play.fill").font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(MediaPalette.background).frame(maxWidth: .infinity).padding(14).background(MediaPalette.accent, in: Capsule())
                }
            } else if item.kind == .book {
                Text(item.fileExtension == "cbz" ? "CBZ imported · comic reader connection is next." : "EPUB imported · Readium reader connection is next.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
            }
            HStack {
                Button { item.isFavorite.toggle(); try? modelContext.save() } label: {
                    Label(item.isFavorite ? "Favorited" : "Favorite", systemImage: item.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .tint(item.isFavorite ? .pink : MediaPalette.accent)
                Spacer()
                Button(role: .destructive) {
                    try? FileManager.default.removeItem(at: item.localURL)
                    modelContext.delete(item)
                    try? modelContext.save()
                    dismiss()
                } label: { Label("Remove", systemImage: "trash") }.font(.system(size: 12, weight: .medium, design: .rounded))
            }
            Spacer()
        }
        .padding(22).background(MediaPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }
}

private struct NowPlayingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        VStack(spacing: 17) {
            HStack {
                Text("NOW PLAYING").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(MediaPalette.muted)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(9).background(MediaPalette.surface, in: Circle()) }
            }
            if let item = playback.currentItem {
                if item.kind == .video { VideoPlayer(player: playback.player).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 18)) }
                else { MediaArtwork(kind: item.kind, size: 180).frame(maxWidth: .infinity).padding(.vertical, 13) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                    Text(item.creator.isEmpty ? "\(item.kind.title) · Local library" : item.creator).font(.system(size: 13, design: .rounded)).foregroundStyle(MediaPalette.muted)
                }
                Slider(value: Binding(get: { playback.elapsedSeconds }, set: { playback.seek(to: $0) }), in: 0...max(playback.durationSeconds, 1)).tint(MediaPalette.accent)
                HStack { Text(timeLabel(playback.elapsedSeconds)); Spacer(); Text(timeLabel(playback.durationSeconds)) }
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                HStack(spacing: 38) {
                    Button { playback.seek(to: max(0, playback.elapsedSeconds - 15)) } label: { Image(systemName: "gobackward.15") }
                    Button { playback.togglePlayback() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 21, weight: .bold))
                            .foregroundStyle(MediaPalette.background).frame(width: 60, height: 60).background(MediaPalette.accent, in: Circle())
                    }
                    Button { playback.seek(to: playback.elapsedSeconds + 15) } label: { Image(systemName: "goforward.15") }
                }
                .font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                if let error = playback.errorMessage { Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }
        .padding(20).background(MediaPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}

private struct SettingsSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Label("Local files", systemImage: "folder")
                    Label("Jellyfin server", systemImage: "server.rack")
                    Text("Server sign-in and discovery are the next integration phase.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Playback") {
                    Label("Music and video currently use Apple AVPlayer.", systemImage: "play.circle")
                    Text("Format coverage, background behavior, subtitle selection, and remote controls need device verification.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Reading and games") {
                    Label("Readium and the game runtime are not connected yet.", systemImage: "book.closed")
                    Text("EPUB and CBZ can be imported. CBR is not supported by the inspected Readium source.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(MediaPalette.background)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
    }
}
