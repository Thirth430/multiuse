import SwiftData
import SwiftUI

@main
struct UnifiedMediaApp: App {
    @State private var playback = PlaybackCoordinator()
    @State private var jellyfin = JellyfinProvider()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(playback)
                .environment(jellyfin)
        }
        .modelContainer(for: MediaLibraryRecord.self)
    }
}
