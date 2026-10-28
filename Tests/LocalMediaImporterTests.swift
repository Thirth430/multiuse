import SwiftData
import XCTest
@testable import UnifiedMedia

@MainActor
final class LocalMediaImporterTests: XCTestCase {
    func testImportsAudioFileIntoPersistentCatalog() async throws {
        let container = try ModelContainer(
            for: LibraryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let source = sourceDirectory.appendingPathComponent("Late Night.mp3")
        try Data([0x49, 0x44, 0x33]).write(to: source)

        let summary = await LocalMediaImporter.importFiles([source], into: container.mainContext)
        let items = try container.mainContext.fetch(FetchDescriptor<LibraryItem>())

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Late Night")
        XCTAssertEqual(items[0].kind, .music)
        XCTAssertTrue(FileManager.default.fileExists(atPath: items[0].localURL.path))
        try? FileManager.default.removeItem(at: items[0].localURL)
    }

    func testUnsupportedFileIsReportedWithoutCatalogEntry() async throws {
        let container = try ModelContainer(
            for: LibraryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let source = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("not media".utf8).write(to: source)

        let summary = await LocalMediaImporter.importFiles([source], into: container.mainContext)
        let items = try container.mainContext.fetch(FetchDescriptor<LibraryItem>())

        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertTrue(items.isEmpty)
    }
}
