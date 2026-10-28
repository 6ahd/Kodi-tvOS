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

// MARK: Row shapes

/// How a Home row draws its items. Automatic picks from the row's title and
/// artwork; a long press on any card in the row sets it by hand.
enum ShelfStyle: String, CaseIterable, Identifiable {
    case automatic, posters, wide, feature, ranked, collections, logos, people, circles
    var id: String { rawValue }
    var name: String {
        switch self {
        case .automatic: "Automatic"
        case .posters: "Posters"
        case .wide: "Wide with logos"
        case .feature: "Large feature"
        case .ranked: "Top 10"
        case .collections: "Collections"
        case .logos: "Logos (networks)"
        case .people: "People"
        case .circles: "Circles"
        }
    }

    static let storeKey = "DexRowStyles"

    static func chosen(for row: String) -> ShelfStyle {
        let saved = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        return saved[row].flatMap(ShelfStyle.init) ?? .automatic
    }

    static func choose(_ style: ShelfStyle, for row: String) {
        var saved = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        saved[row] = style == .automatic ? nil : style.rawValue
        UserDefaults.standard.set(saved, forKey: storeKey)
    }

    /// The automatic choice: the row's title first, then what its artwork allows.
    static func guess(title: String, items: [MediaItem], logoCards: Bool) -> ShelfStyle {
        let name = title.lowercased()
        let has = { (words: [String]) in words.contains { name.contains($0) } }
        let share = { (test: (MediaItem) -> Bool) in items.filter(test).count * 2 >= max(1, items.count) }
        if share({ $0.progress > 0.01 }) { return .wide }
        if has(["top 10", "top10", "top ", "أعلى", "الأكثر", "الأفضل"]) { return .ranked }
        if has(["of the week", "featured", "spotlight", "الأسبوع", "مميز", "المختار"]) { return .feature }
        if has(["network", "studio", "service", "channel", "provider", "الشبكات", "شبكات", "خدمات", "استوديو", "القنوات"]) { return .logos }
        if has(["actor", "actress", "director", "people", "cast", "stars", "الممثل", "المخرج", "الجهات الفاعلة", "نجوم", "المدراء"]) { return .people }
        if share({ $0.isFolder }) {
            if share({ $0.art["fanart"] != nil || $0.art["landscape"] != nil }) { return .collections }
            if share({ $0.poster == nil || $0.art["poster"] == nil }) { return .logos }
        }
        if share(\.hasPoster) { return .posters }
        return logoCards ? .wide : .collections
    }
}

/// "Movies of the week": one big scene with the title's logo and facts.
struct FeatureCard: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: item.backdrop ?? item.landscape ?? item.poster) { TitleTile(title: item.title, size: 44) }
                .frame(width: 980, height: 551)
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                ClearLogo(item: item, height: 130)
                Text(item.metadata.joined(separator: " · ")).font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(32)
        }
        .frame(width: 980, height: 551)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .hoverEffect(.highlight)
    }
}

/// Top 10: the rank set large beside the poster.
struct RankedCard: View {
    let item: MediaItem
    let rank: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: -28) {
            Text("\(rank)")
                .font(.system(size: 200, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.6), radius: 12)
                .frame(width: rank >= 10 ? 210 : 120, alignment: .trailing)
                .offset(y: 30)
            PosterCard(item: item)
        }
    }
}

/// A collection or genre: wide art with its name across it.
struct CollectionTile: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: item.landscape ?? item.backdrop ?? item.poster) { TitleTile(title: "", size: 10) }
                .frame(width: 560, height: 315)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title.uppercased()).font(.system(size: 34, weight: .black)).tracking(1).lineLimit(1).minimumScaleFactor(0.6)
                if !item.plot.isEmpty {
                    Text(item.plot.uppercased()).font(.system(size: 15, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 22)
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.85)).frame(width: 3).padding(.vertical, 22) }
        }
        .frame(width: 560, height: 315)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .hoverEffect(.highlight)
    }
}

/// A network or streaming service: its logo on a dark tile.
struct LogoTile: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            Theme.tint(for: item.title).opacity(0.35)
            Artwork(url: item.backdrop) { Color.black.opacity(0.6) }
                .opacity(0.35)
            Artwork(url: item.clearLogo ?? item.art["icon"] ?? item.art["thumb"] ?? item.poster, mode: .fit) {
                Text(item.title).font(.system(size: 38, weight: .heavy)).multilineTextAlignment(.center).padding()
            }
            .padding(48)
        }
        .frame(width: 400, height: 225)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .hoverEffect(.highlight)
    }
}

/// An actor or director: a portrait photo with the name below.
struct PersonTile: View {
    let item: MediaItem
    var round = false

    var body: some View {
        VStack(spacing: 14) {
            Artwork(url: item.art["thumb"] ?? item.poster ?? item.art["icon"]) {
                ZStack {
                    Theme.tint(for: item.title)
                    Text(String(item.title.prefix(1))).font(.system(size: 70, weight: .heavy))
                }
            }
            .frame(width: round ? 220 : 240, height: round ? 220 : 330)
            .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .contentShape(.hoverEffect, round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .hoverEffect(.highlight)
            FocusLabel(text: item.title).frame(width: 240)
        }
    }
}

// MARK: Sources

/// One source in the details page: add-on, quality, sound and size.
struct SourceCard: View {
    let source: StreamSource
    let best: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Artwork(url: source.provider.logo, mode: .fit) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 30))
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(source.provider.name).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Spacer()
                if source.cached { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                if best { Image(systemName: "crown.fill").foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.2)) }
            }
            HStack(spacing: 12) {
                Text(source.resolution).font(.system(size: 34, weight: .heavy))
                Badges(labels: source.badges)
            }
            Text(source.detail.isEmpty ? source.name : source.detail)
                .font(.system(size: 18)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            if !source.size.isEmpty {
                Label(source.size, systemImage: "film").font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(26)
        .frame(width: 560, height: 270, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(focused ? 0.9 : 0.18), lineWidth: focused ? 3 : 1))
        .scaleEffect(focused ? 1.06 : 1)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 12)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
