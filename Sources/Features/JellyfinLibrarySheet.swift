import SwiftUI

struct JellyfinLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinProvider.self) private var jellyfin
    let onPlaybackStarted: (MediaKind) -> Void
    @State private var filter = "all"
    @State private var favoritesOnly = false
    @State private var selectedEntry: JellyfinLibraryEntry?

    private var visibleItems: [JellyfinLibraryEntry] {
        let typeFiltered = filter == "all" ? jellyfin.entries : jellyfin.entries.filter { $0.kind.rawValue == filter }
        return favoritesOnly ? typeFiltered.filter(\.isFavorite) : typeFiltered
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Media type", selection: $filter) {
                    Text("All").tag("all")
                    Text("Music").tag(MediaKind.music.rawValue)
                    Text("Video").tag(MediaKind.video.rawValue)
                    Text("Books").tag(MediaKind.book.rawValue)
                    Text("Games").tag(MediaKind.game.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Label(favoritesOnly ? "Showing favorites" : "Favorites only", systemImage: favoritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(favoritesOnly ? MediaPalette.background : MediaPalette.accent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(favoritesOnly ? MediaPalette.accent : MediaPalette.surface, in: Capsule())
                }
                .buttonStyle(.plain)

                if jellyfin.isLoading && jellyfin.entries.isEmpty {
                    ProgressView("Loading server library…").tint(MediaPalette.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleItems.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly ? "No server favorites" : "No matching server items",
                        systemImage: favoritesOnly ? "heart" : "server.rack",
                        description: Text(favoritesOnly ? "Favorite a Jellyfin item or choose another media filter." : "Try another media filter or refresh the Jellyfin library.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(visibleItems) { item in
                                JellyfinEntryRow(item: item) { selectedEntry = item }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 12)
            .background(MediaPalette.background)
            .navigationTitle(jellyfin.connectedServerName ?? "Jellyfin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await jellyfin.refreshLibrary() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(jellyfin.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let error = jellyfin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.white)
                        .padding(12).frame(maxWidth: .infinity).background(.red.opacity(0.85))
                }
            }
            .sheet(item: $selectedEntry) { item in
                JellyfinEntryDetailSheet(item: item) { onPlaybackStarted(item.kind) }
            }
        }
        .preferredColorScheme(.dark)
    }
}
