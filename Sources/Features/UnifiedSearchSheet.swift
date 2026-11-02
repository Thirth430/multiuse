import SwiftUI

struct UnifiedSearchSheet: View {
    let localItems: [MediaLibraryRecord]
    let onOpenLocal: (MediaLibraryRecord) -> Void
    let onPlaybackStarted: (MediaKind) -> Void
    let onDismiss: () -> Void

    @Environment(JellyfinProvider.self) private var jellyfin
    @State private var query = ""
    @State private var selectedKind: MediaKind?
    @State private var selectedServerEntry: JellyfinLibraryEntry?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var foldedQuery: String {
        trimmedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var localResults: [MediaLibraryRecord] {
        guard !foldedQuery.isEmpty else { return [] }
        return localItems.filter { item in
            if let selectedKind, item.kind != selectedKind { return false }
            let searchableText = "\(item.title) \(item.creator) \(item.collection) \(item.kind.title)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return searchableText.contains(foldedQuery)
        }
    }

    private var serverResults: [JellyfinLibraryEntry] {
        guard jellyfin.isConnected, !foldedQuery.isEmpty else { return [] }
        return jellyfin.entries.filter { item in
            if let selectedKind, item.kind != selectedKind { return false }
            let searchableText = "\(item.title) \(item.creator) \(item.kind.title)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return searchableText.contains(foldedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MediaPalette.muted)
                    TextField("Search all media…", text: $query).textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(MediaPalette.muted)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(13).background(MediaPalette.surface, in: RoundedRectangle(cornerRadius: 13))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        filterChip("All", selected: selectedKind == nil) { selectedKind = nil }
                        ForEach(MediaKind.allCases) { kind in
                            filterChip(kind.title, selected: selectedKind == kind) { selectedKind = kind }
                        }
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        if !trimmedQuery.isEmpty {
                            if localResults.isEmpty && serverResults.isEmpty {
                                ContentUnavailableView.search(text: query).padding(.top, 32)
                            } else {
                                if !localResults.isEmpty {
                                    resultHeading("On this device")
                                    ForEach(localResults, id: \.id) { item in
                                        MediaRow(item: item) { onOpenLocal(item) }
                                    }
                                }
                                if !serverResults.isEmpty {
                                    resultHeading("Jellyfin server")
                                    ForEach(serverResults) { item in
                                        JellyfinEntryRow(item: item) { selectedServerEntry = item }
                                    }
                                }
                            }
                        }
                    }
                }

                if trimmedQuery.isEmpty {
                    Text(jellyfin.isConnected ? "Search your local and Jellyfin libraries." : "Search imported media here, or connect a Jellyfin server in Settings.")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(MediaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18).background(MediaPalette.background)
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDismiss) } }
            .sheet(item: $selectedServerEntry) { item in
                JellyfinEntryDetailSheet(item: item) { onPlaybackStarted(item.kind) }
            }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
    }

    private func resultHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MediaPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? MediaPalette.background : MediaPalette.muted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? MediaPalette.accent : MediaPalette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
