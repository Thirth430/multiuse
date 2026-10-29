import Observation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit

private extension FontFamily {
    static let fastSerif: FontFamily = "Fast Serif"
}

private struct SavedReadingBookmark: Codable, Identifiable {
    var id: String
    var label: String
    var locatorJSON: String
}

@MainActor
@Observable
private final class ReadiumReaderSession {
    var publication: Publication?
    var tableOfContents: [ReadiumShared.Link] = []
    var errorMessage: String?
    var currentLocator: Locator?

    @ObservationIgnored fileprivate let item: MediaLibraryRecord

    init(item: MediaLibraryRecord) {
        self.item = item
    }

    var bookmarks: [SavedReadingBookmark] {
        guard let data = item.readingBookmarksData else { return [] }
        return (try? JSONDecoder().decode([SavedReadingBookmark].self, from: data)) ?? []
    }

    func open() async {
        guard publication == nil else { return }
        do {
            guard let fileURL = FileURL(url: item.localURL) else {
                throw ReaderError.invalidFileURL
            }
            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let opener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: httpClient,
                    assetRetriever: assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                )
            )
            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
            guard !publication.isRestricted else { throw ReaderError.protectedPublication }

            self.publication = publication
            self.currentLocator = savedLocator
            self.tableOfContents = (try? await publication.tableOfContents().get()) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(location: Locator) {
        currentLocator = location
        item.readingLocatorJSON = try? location.jsonString()
        if let progression = location.locations.totalProgression {
            item.readingProgression = min(max(progression, 0), 1)
        }
        item.lastOpenedAt = .now
    }

    func addBookmark() {
        guard let currentLocator, let locatorJSON = try? currentLocator.jsonString() else { return }
        var saved = bookmarks
        saved.insert(
            SavedReadingBookmark(
                id: UUID().uuidString,
                label: currentLocator.title ?? "Page \(saved.count + 1)",
                locatorJSON: locatorJSON
            ),
            at: 0
        )
        item.readingBookmarksData = try? JSONEncoder().encode(saved)
    }

    func locator(for bookmark: SavedReadingBookmark) -> Locator? {
        try? Locator(jsonString: bookmark.locatorJSON)
    }

    private var savedLocator: Locator? {
        guard let json = item.readingLocatorJSON else { return nil }
        return try? Locator(jsonString: json)
    }

    private enum ReaderError: LocalizedError {
        case invalidFileURL
        case protectedPublication

        var errorDescription: String? {
            switch self {
            case .invalidFileURL: "This book file could not be opened. Import it again and retry."
            case .protectedPublication: "This publication is protected, and no compatible license is configured."
            }
        }
    }
}

struct ReadiumBookReader: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReadiumReaderSession
    @State private var navigator: EPUBNavigatorViewController?
    @AppStorage("reader.fontChoice") private var fontChoice = "system"
    @AppStorage("reader.fontSize") private var fontSize = 100.0
    @State private var showingContents = false
    @State private var showingBookmarks = false
    @State private var comicNavigationRequest: Locator?
    @State private var navigationError: String?

    init(item: MediaLibraryRecord) {
        _session = State(initialValue: ReadiumReaderSession(item: item))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let publication = session.publication {
                    if publication.conforms(to: .divina) {
                        CBZComicReader(
                            publication: publication,
                            item: session.item,
                            initialLocation: session.currentLocator,
                            navigationRequest: comicNavigationRequest
                        ) { session.update(location: $0) }
                    } else {
                        ReadiumNavigatorContainer(
                            publication: publication,
                            initialLocation: session.currentLocator,
                            fontFamily: selectedFontFamily,
                            fontSize: fontSize,
                            onLocationChange: session.update,
                            onError: { navigationError = $0.localizedDescription },
                            onReady: { navigator = $0 }
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
                } else if let error = session.errorMessage {
                    ContentUnavailableView {
                        Label("Unable to open this book", systemImage: "book.closed")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ProgressView("Opening book…")
                        .tint(.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if session.publication?.conforms(to: .epub) == true {
                        Button { showingContents = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Table of contents")
                    }
                    Menu {
                        Button("Add bookmark", systemImage: "bookmark") { session.addBookmark() }
                        Button("Bookmarks", systemImage: "bookmark.fill") { showingBookmarks = true }
                        Divider()
                        if session.publication?.conforms(to: .epub) == true {
                            Picker("Font", selection: $fontChoice) {
                                Text("System serif").tag("system")
                                Text("Fast Serif").tag("fast")
                            }
                            Divider()
                            Button("Smaller text", systemImage: "textformat.size.smaller") { fontSize = max(80, fontSize - 10) }
                            Button("Larger text", systemImage: "textformat.size.larger") { fontSize = min(180, fontSize + 10) }
                        }
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel("Reading settings and bookmarks")
                }
            }
            .sheet(isPresented: $showingContents) { contentsSheet }
            .sheet(isPresented: $showingBookmarks) { bookmarksSheet }
            .alert("Reader error", isPresented: Binding(
                get: { navigationError != nil },
                set: { if !$0 { navigationError = nil } }
            )) {
                Button("OK", role: .cancel) { navigationError = nil }
            } message: {
                Text(navigationError ?? "The reader encountered a problem.")
            }
        }
        .task { await session.open() }
    }

    private var selectedFontFamily: FontFamily {
        fontChoice == "fast" ? .fastSerif : .serif
    }

    private var contentsSheet: some View {
        NavigationStack {
            List(Array(session.tableOfContents.enumerated()), id: \.offset) { _, link in
                Button(link.title ?? link.href) {
                    Task { _ = await navigator?.go(to: link); showingContents = false }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if session.tableOfContents.isEmpty {
                    ContentUnavailableView("No table of contents", systemImage: "list.bullet")
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingContents = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var bookmarksSheet: some View {
        NavigationStack {
            List(session.bookmarks) { bookmark in
                Button(bookmark.label) {
                    if let locator = session.locator(for: bookmark) {
                        if let navigator {
                            Task { _ = await navigator.go(to: locator); showingBookmarks = false }
                        } else {
                            comicNavigationRequest = locator
                            showingBookmarks = false
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if session.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks yet", systemImage: "bookmark")
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingBookmarks = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CBZComicReader: View {
    let publication: Publication
    let item: MediaLibraryRecord
    let initialLocation: Locator?
    let navigationRequest: Locator?
    let onLocationChange: (Locator) -> Void

    @State private var pageIndex = 0
    @State private var pageData: Data?
    @State private var errorMessage: String?
    @State private var didRestoreLocation = false

    private var pages: [ReadiumShared.Link] { publication.readingOrder }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let pageData, let image = UIImage(data: pageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("Could not open comic page", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    .foregroundStyle(.white)
            } else {
                ProgressView("Loading page…").tint(.white).foregroundStyle(.white)
            }
            VStack {
                Spacer()
                HStack {
                    Button { pageIndex = max(0, pageIndex - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 46, height: 46)
                    }
                    .disabled(pageIndex == 0)
                    Spacer()
                    Text(pages.isEmpty ? "0 / 0" : "\(pageIndex + 1) / \(pages.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Button { pageIndex = min(pages.count - 1, pageIndex + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 46, height: 46)
                    }
                    .disabled(pageIndex >= pages.count - 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
        }
        .task {
            guard !didRestoreLocation else { return }
            didRestoreLocation = true
            if let initialLocation { restore(initialLocation) }
        }
        .onChange(of: navigationRequest?.href.url.absoluteString) { _, _ in
            if let navigationRequest { restore(navigationRequest) }
        }
        .task(id: pageIndex) { await loadCurrentPage() }
    }

    @MainActor
    private func loadCurrentPage() async {
        guard pages.indices.contains(pageIndex) else {
            errorMessage = "This comic archive contains no readable image pages."
            return
        }
        pageData = nil
        errorMessage = nil
        do {
            guard let resource = publication.get(pages[pageIndex]) else {
                throw ComicReaderError.missingPage
            }
            pageData = try await resource.read().get()
            guard let mediaType = pages[pageIndex].mediaType else { throw ComicReaderError.unsupportedPage }
            let progression = Double(pageIndex) / Double(max(1, pages.count))
            let locator = Locator(
                href: pages[pageIndex].url(),
                mediaType: mediaType,
                title: pages[pageIndex].title,
                locations: .init(totalProgression: progression, position: pageIndex + 1)
            )
            item.readingLocatorJSON = try? locator.jsonString()
            item.readingProgression = progression
            item.lastOpenedAt = .now
            onLocationChange(locator)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ locator: Locator) {
        if let index = pages.firstIndex(where: { $0.url().url.absoluteString == locator.href.url.absoluteString }) {
            pageIndex = index
        }
    }

    private enum ComicReaderError: LocalizedError {
        case missingPage
        case unsupportedPage

        var errorDescription: String? {
            switch self {
            case .missingPage: "Readium could not find this page in the archive."
            case .unsupportedPage: "This comic page has no supported image type."
            }
        }
    }
}

private struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: Locator?
    let fontFamily: FontFamily
    let fontSize: Double
    let onLocationChange: (Locator) -> Void
    let onError: (NavigatorError) -> Void
    let onReady: (EPUBNavigatorViewController) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLocationChange: onLocationChange, onError: onError, onReady: onReady)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        var preferences = EPUBPreferences()
        preferences.fontFamily = fontFamily
        preferences.fontSize = fontSize
        preferences.publisherStyles = false

        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            fontFamilyDeclarations: Self.fastFontDeclarations
        )

        do {
            let controller = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: config
            )
            controller.delegate = context.coordinator
            context.coordinator.navigator = controller
            Task { @MainActor in onReady(controller) }
            return controller
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "This publication could not be displayed: \(error.localizedDescription)"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            ])
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onLocationChange = onLocationChange
        context.coordinator.onError = onError
        context.coordinator.onReady = onReady
        guard let navigator = uiViewController as? EPUBNavigatorViewController else { return }
        guard context.coordinator.appliedFontFamily != fontFamily || context.coordinator.appliedFontSize != fontSize else { return }

        var preferences = EPUBPreferences()
        preferences.fontFamily = fontFamily
        preferences.fontSize = fontSize
        preferences.publisherStyles = false
        navigator.submitPreferences(preferences)
        context.coordinator.appliedFontFamily = fontFamily
        context.coordinator.appliedFontSize = fontSize
    }

    private static var fastFontDeclarations: [AnyHTMLFontFamilyDeclaration] {
        guard
            let url = Bundle.main.url(forResource: "Fast_Serif", withExtension: "ttf"),
            let file = FileURL(url: url)
        else { return [] }

        return [
            CSSFontFamilyDeclaration(
                fontFamily: .fastSerif,
                fontFaces: [CSSFontFace(file: file)]
            ).eraseToAnyHTMLFontFamilyDeclaration(),
        ]
    }

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        weak var navigator: EPUBNavigatorViewController?
        var onLocationChange: (Locator) -> Void
        var onError: (NavigatorError) -> Void
        var onReady: (EPUBNavigatorViewController) -> Void
        var appliedFontFamily: FontFamily?
        var appliedFontSize: Double?

        init(
            onLocationChange: @escaping (Locator) -> Void,
            onError: @escaping (NavigatorError) -> Void,
            onReady: @escaping (EPUBNavigatorViewController) -> Void
        ) {
            self.onLocationChange = onLocationChange
            self.onError = onError
            self.onReady = onReady
        }

        func navigator(_ navigator: ReadiumNavigator.Navigator, locationDidChange locator: Locator) {
            onLocationChange(locator)
        }

        func navigator(_ navigator: ReadiumNavigator.Navigator, presentError error: NavigatorError) {
            onError(error)
        }
    }
}
