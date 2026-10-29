import SwiftData
import XCTest
@testable import UnifiedMedia

@MainActor
final class MusicPlaylistTests: XCTestCase {
    func testPlaylistPersistsOrderedTrackIDs() throws {
        let container = try ModelContainer(
            for: MediaLibraryRecord.self, MusicPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let playlist = MusicPlaylist(name: "Evening", itemIDs: ["track-b", "track-a", "track-c"])
        container.mainContext.insert(playlist)
        try container.mainContext.save()

        let saved = try container.mainContext.fetch(FetchDescriptor<MusicPlaylist>())

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "Evening")
        XCTAssertEqual(saved.first?.itemIDs, ["track-b", "track-a", "track-c"])
    }
}
