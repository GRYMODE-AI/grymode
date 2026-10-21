import SwiftUI
import UIKit

/// Private-media image keyed by object path + content version (`v`), ignoring re-signed
/// `token` query values so the same bytes do not flicker — while a new `v` (face replace
/// or re-render at a fixed object key) busts the stale previous person's pixels.
struct GMRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var failureSystemImage = "hanger"

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = image ?? cached {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || url == nil {
                Image(systemName: failureSystemImage)
                    .foregroundStyle(GMColor.textSecondary)
            } else {
                ProgressView().tint(GMColor.accent)
            }
        }
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String { url.map(Self.cacheKey(for:)) ?? "" }

    private var cached: UIImage? {
        url.flatMap { GMRemoteImageCache.shared.object(forKey: Self.cacheKey(for: $0) as NSString) }
    }

    static func cacheKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let version = components?.queryItems?.first(where: { $0.name == "v" })?.value
        components?.queryItems = version.map { [URLQueryItem(name: "v", value: $0)] }
        if version == nil {
            components?.query = nil
        }
        return components?.string ?? url.absoluteString
    }

    private func load() async {
        guard let url else { return }
        let key = Self.cacheKey(for: url) as NSString
        if let hit = GMRemoteImageCache.shared.object(forKey: key) {
            image = hit
            return
        }
        image = nil
        failed = false
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let decoded = UIImage(data: data)
            else {
                failed = true
                return
            }
            GMRemoteImageCache.shared.setObject(decoded, forKey: key, cost: data.count)
            image = decoded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

@MainActor
enum GMRemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    /// Drops decoded private media after the user replaces their face (same object path).
    static func removeAll() {
        shared.removeAllObjects()
    }
}
