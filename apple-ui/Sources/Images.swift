import SwiftUI
import UIKit

/// Decoded artwork shared by every screen; rows scroll back without refetching.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.totalCostLimit = 96 * 1024 * 1024 }

    private let ambients = NSCache<NSURL, UIColor>()

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    /// The artwork's average colour, deepened for a page background behind
    /// white text (EplayerX-style ambient tint).
    func ambient(_ url: URL) async -> UIColor? {
        if let color = ambients.object(forKey: url as NSURL) { return color }
        guard let image = await load(url)?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let color = UIColor(hue: hue, saturation: min(0.65, saturation * 1.15), brightness: min(0.26, max(0.12, brightness * 0.45)), alpha: 1)
        ambients.setObject(color, forKey: url as NSURL)
        return color
    }

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
