import SwiftUI

enum Theme {
    static let ground = Color(red: 0.027, green: 0.031, blue: 0.059)
    static let accent = Color(red: 0.643, green: 0.592, blue: 1.0)
    static let secondary = Color.white.opacity(0.68)
    static let tints: [Color] = [
        Color(red: 0.42, green: 0.23, blue: 0.18), Color(red: 0.12, green: 0.31, blue: 0.42),
        Color(red: 0.29, green: 0.35, blue: 0.16), Color(red: 0.35, green: 0.18, blue: 0.42),
        Color(red: 0.18, green: 0.29, blue: 0.42), Color(red: 0.42, green: 0.35, blue: 0.18)
    ]
    static func tint(for text: String) -> Color { tints[abs(text.hashValue) % tints.count] }
}

/// Look settings people choose in Settings › Appearance.
enum Look {
    static let background = "DexLookBackground"   // full | ambient | plain
    static let accent = "DexLookAccent"           // violet | teal | gold | white
    static let rotate = "DexLookRotateFeatured"
    static let logoCards = "DexLookLogoCards"
    static let plot = "DexLookShowPlot"
    static let ratings = "DexLookShowRatings"

    static let accents: [(id: String, name: String, color: Color)] = [
        ("violet", "Dex Violet", Color(red: 0.643, green: 0.592, blue: 1.0)),
        ("teal", "Teal", Color(red: 0.37, green: 0.78, blue: 0.9)),
        ("gold", "Gold", Color(red: 0.96, green: 0.71, blue: 0.36)),
        ("white", "White", .white)
    ]
    static func accentColor(_ id: String) -> Color { accents.first { $0.id == id }?.color ?? accents[0].color }
}

/// Where a selection leads.
enum Route: Hashable {
    case directory(path: String, title: String)
    case details(MediaItem)
}

/// Stand-in for missing artwork: the title on a deep tint.
struct TitleTile: View {
    let title: String
    var size: CGFloat = 26

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Theme.tint(for: title), Theme.ground], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(title)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(16)
        }
    }
}

/// The title's clear logo, or the title set large when there is none.
struct ClearLogo: View {
    let item: MediaItem
    var height: CGFloat = 170

    var body: some View {
        Artwork(url: item.clearLogo, mode: .fit) {
            Text(item.showTitle.isEmpty ? item.title : item.showTitle)
                .font(.system(size: height * 0.55, weight: .heavy))
                .tracking(-1)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.5), radius: 20)
        }
        .frame(maxWidth: 760, maxHeight: height, alignment: .bottomLeading)
    }
}

/// A poster with Apple TV's card focus: lift, shine and tilt with the remote.
struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Artwork(url: item.poster) { TitleTile(title: item.title) }
                .frame(width: width, height: width * 1.5)
                .overlay(alignment: .bottom) { ProgressLine(progress: item.progress) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .hoverEffect(.highlight)
            FocusLabel(text: item.title)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// A 16:9 card, for episodes, add-on folders and anything without a poster.
struct LandscapeCard: View {
    let title: String
    let subtitle: String
    let image: URL?
    var progress: Double = 0
    var width: CGFloat = 400
    var fit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Artwork(url: image, mode: fit ? .fit : .fill) { TitleTile(title: title, size: 30) }
                .padding(fit ? 36 : 0)
                .frame(width: width, height: width * 9 / 16)
                .background(fit ? Theme.tint(for: title).opacity(0.55) : .clear)
                .overlay(alignment: .bottom) { ProgressLine(progress: progress) }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hoverEffect(.highlight)
            FocusLabel(text: title)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 18)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct ProgressLine: View {
    let progress: Double
    @AppStorage(Look.accent) private var accent = "violet"

    var body: some View {
        if progress > 0.01 {
            GeometryReader { box in
                Capsule().fill(.white.opacity(0.3))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Look.accentColor(accent)).frame(width: box.size.width * min(1, progress))
                    }
            }
            .frame(height: 6)
            .padding(14)
        }
    }
}

/// Loading, failure and empty states shared by every screen.
struct LoadState: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let error {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                Text(error).font(.system(size: 26)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                Button("Try Again", action: retry)
            } else {
                ProgressView().scaleEffect(1.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension MediaItem {
    /// Folders open; rich items show details first; the rest play at once.
    func route(play: (MediaItem) -> Void) -> Route? {
        if isFolder { return .directory(path: file, title: title) }
        if isRich { return .details(self) }
        play(self)
        return nil
    }
}

/// A card's title: brighter while its card has focus, as on the Apple TV Home screen.
struct FocusLabel: View {
    let text: String
    @Environment(\.isFocused) private var focused

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(focused ? .white : .white.opacity(0.7))
            .lineLimit(1)
            .animation(.easeOut(duration: 0.2), value: focused)
    }
}

/// Buttons whose artwork carries the focus effect itself (hoverEffect).
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Continue Watching style: the scene, the title's clear logo over it, and
/// what is left to watch.
struct LogoCard: View {
    let item: MediaItem
    var width: CGFloat = 520

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: item.landscape ?? item.backdrop ?? item.poster) { TitleTile(title: item.title, size: 34) }
                .frame(width: width, height: width * 9 / 16)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Artwork(url: item.clearLogo, mode: .fit) {
                    Text(item.showTitle.isEmpty ? item.title : item.showTitle)
                        .font(.system(size: 34, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: width * 0.62, maxHeight: 84, alignment: .bottomLeading)
                HStack(spacing: 12) {
                    if item.progress > 0.01 {
                        ProgressLine(progress: item.progress).padding(0).frame(width: 110)
                    }
                    Text(([item.timeLeft] + (item.season >= 0 && item.episode >= 0 ? ["S\(item.season), E\(item.episode)"] : []))
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(22)
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .hoverEffect(.highlight)
    }
}

/// Round badges like "4K" and "Dolby Vision".
struct Badges: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 17, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.55), lineWidth: 1.5))
            }
        }
    }
}
