import SwiftData
import SwiftUI

@main
struct UnifiedMediaApp: App {
    @State private var playback = PlaybackCoordinator()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(playback)
        }
        .modelContainer(for: MediaLibraryRecord.self)
    }
}
