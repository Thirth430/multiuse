import SwiftData
import SwiftUI

struct MusicPlaylistEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tracks: [MediaLibraryRecord]
    let playlist: MusicPlaylist?
    let onSave: (String, [String]) throws -> Void
    @State private var name: String
    @State private var selectedIDs: Set<String>
    @State private var saveError: String?

    init(tracks: [MediaLibraryRecord], playlist: MusicPlaylist?, onSave: @escaping (String, [String]) throws -> Void) {
        self.tracks = tracks
        self.playlist = playlist
        self.onSave = onSave
        _name = State(initialValue: playlist?.name ?? "")
        _selectedIDs = State(initialValue: Set(playlist?.itemIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Playlist") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                }
                Section("Tracks · \(selectedIDs.count) selected") {
                    if tracks.isEmpty {
                        Text("Import music before creating a playlist.").foregroundStyle(.secondary)
                    } else {
                        ForEach(tracks, id: \.id) { track in
                            Button {
                                if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) }
                                else { selectedIDs.insert(track.id) }
                            } label: {
                                HStack(spacing: 11) {
                                    MediaArtwork(kind: .music, size: 42, artworkURL: track.artworkURL)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                                        Text(track.creator.isEmpty ? track.collection : track.creator).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 5)
                                    Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(track.id) ? MediaPalette.accent : .secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(playlist == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        do {
                            try onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), tracks.map(\.id).filter(selectedIDs.contains))
                            dismiss()
                        } catch {
                            saveError = "The playlist could not be saved: \(error.localizedDescription)"
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Couldn’t save playlist", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }
}

struct MusicPlaylistDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let playlist: MusicPlaylist
    let tracks: [MediaLibraryRecord]
    let play: ([MediaLibraryRecord], Int) -> Void
    @State private var orderedIDs: [String]
    @State private var persistenceError: String?

    init(playlist: MusicPlaylist, tracks: [MediaLibraryRecord], play: @escaping ([MediaLibraryRecord], Int) -> Void) {
        self.playlist = playlist
        self.tracks = tracks
        self.play = play
        let availableIDs = Set(tracks.map(\.id))
        _orderedIDs = State(initialValue: playlist.itemIDs.filter(availableIDs.contains))
    }

    private var orderedTracks: [MediaLibraryRecord] {
        let recordsByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return orderedIDs.compactMap { recordsByID[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if orderedTracks.isEmpty {
                        ContentUnavailableView("No available tracks", systemImage: "music.note.list", description: Text("Edit this playlist to add tracks from your music library."))
                    } else {
                        ForEach(Array(orderedTracks.enumerated()), id: \.element.id) { index, track in
                            Button { play(orderedTracks, index) } label: {
                                HStack(spacing: 11) {
                                    MediaArtwork(kind: .music, size: 42, artworkURL: track.artworkURL)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                                        Text(track.creator.isEmpty ? "Unknown Artist" : track.creator).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onMove { source, destination in
                            let previousIDs = orderedIDs
                            orderedIDs.move(fromOffsets: source, toOffset: destination)
                            playlist.itemIDs = orderedIDs
                            do { try modelContext.save() }
                            catch {
                                orderedIDs = previousIDs
                                playlist.itemIDs = previousIDs
                                persistenceError = "The playlist order could not be saved: \(error.localizedDescription)"
                            }
                        }
                    }
                } header: {
                    Text("\(orderedTracks.count) tracks")
                }
            }
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard !orderedTracks.isEmpty else { return }
                        play(orderedTracks, 0)
                    } label: { Image(systemName: "play.fill") }
                    .disabled(orderedTracks.isEmpty)
                    .accessibilityLabel("Play playlist")
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Couldn’t update playlist", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "")
        }
    }
}

struct MusicCollectionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tracks: [MediaLibraryRecord]
    let play: ([MediaLibraryRecord], Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("\(tracks.count) songs") {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button { play(tracks, index) } label: {
                            HStack(spacing: 11) {
                                MediaArtwork(kind: .music, size: 42, artworkURL: track.artworkURL)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                                    Text(track.creator.isEmpty ? "Unknown Artist" : track.creator).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !tracks.isEmpty else { return }
                        play(tracks, 0)
                    } label: { Image(systemName: "play.fill") }
                    .disabled(tracks.isEmpty)
                    .accessibilityLabel("Play collection")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
