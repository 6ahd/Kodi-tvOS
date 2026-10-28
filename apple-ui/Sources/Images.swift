import SwiftUI
import UIKit

/// Decoded artwork shared by every screen; rows scroll back without refetching.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.totalCostLimit = 96 * 1024 * 1024 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let image = UIImage(data: data)?.preparingForDisplay() else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}

/// Artwork that fades in once decoded, with a placeholder until then.
struct Artwork<Placeholder: View>: View {
    let url: URL?
    var mode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: mode).transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .task(id: url) {
            image = url.flatMap(ImageStore.shared.cached)
            if image == nil, let url { image = await ImageStore.shared.load(url) }
        }
    }
}
