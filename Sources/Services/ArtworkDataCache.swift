import Foundation

/// Shared in-memory artwork cache. Remote loads use URLSession's HTTP cache as
/// well, so server artwork can be reused by library rows and detail views.
actor ArtworkDataCache {
    static let shared = ArtworkDataCache()

    private let memoryCache = NSCache<NSURL, NSData>()

    init() {
        memoryCache.countLimit = 180
        memoryCache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func data(for url: URL) async -> Data? {
        let key = url as NSURL
        if let cached = memoryCache.object(forKey: key) {
            return cached as Data
        }

        let data: Data?
        if url.isFileURL {
            data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
        } else {
            do {
                let (responseData, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else { return nil }
                data = responseData
            } catch {
                return nil
            }
        }

        if let data {
            memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        }
        return data
    }
}
