import SwiftUI

struct RootView: View {
    @ObservedObject var kodi: Kodi

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { Stack(kodi: kodi) { HomeScreen(kodi: kodi, select: $0) } }
            Tab("Add-ons", systemImage: "puzzlepiece.extension") { Stack(kodi: kodi) { AddonsScreen(kodi: kodi, select: $0) } }
            Tab("Kodi", systemImage: "square.grid.2x2") { KodiScreen(kodi: kodi) }
            Tab("Settings", systemImage: "gearshape") { NavigationStack { SettingsScreen(kodi: kodi) } }
        }
        .background(Theme.ground)
        .preferredColorScheme(.dark)
    }
}

/// A navigation stack whose screens push folders and details by selection.
struct Stack<Content: View>: View {
    @ObservedObject var kodi: Kodi
    @ViewBuilder var content: (_ select: @escaping (MediaItem) -> Void) -> Content
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            content(select)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .directory(let folder, let title): DirectoryScreen(kodi: kodi, path: folder, title: title, select: select)
                    case .details(let item): DetailsScreen(kodi: kodi, item: item)
                    }
                }
        }
    }

    private func select(_ item: MediaItem) {
        if let route = item.route(play: kodi.play) { path.append(route) }
    }
}

// MARK: Full-screen background

/// The page behind everything: the featured artwork over the whole screen,
/// fading into a colour taken from that artwork (Settings › Background).
struct Backdrop: View {
    let item: MediaItem?
    @AppStorage(Look.background) private var style = "full"
    @State private var ambient = Theme.ground

    var body: some View {
        ZStack {
            (style == "plain" ? Theme.ground : ambient)
            if style == "full", let item {
                Artwork(url: item.backdrop) { Color.clear }
                    .id(item.id)
                    .transition(.opacity)
                // Text side and the rows below stay readable on any artwork.
                LinearGradient(colors: [ambient.opacity(0.92), ambient.opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .init(x: 0.75, y: 0.5))
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: ambient.opacity(0.8), location: 0.72),
                                       .init(color: ambient, location: 1)], startPoint: .top, endPoint: .bottom)
            } else if style == "ambient" {
                RadialGradient(colors: [ambient.opacity(0.0), Theme.ground.opacity(0.85)], center: .topTrailing,
                               startRadius: 200, endRadius: 1900)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: ambient)
        .task(id: item?.backdrop) {
            guard let url = item?.backdrop, let color = await ImageStore.shared.ambient(url) else { return }
            ambient = Color(uiColor: color)
        }
    }
}

// MARK: Home

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
    var posters: Bool { items.filter(\.hasPoster).count * 2 >= items.count }
    var resumes: Bool { items.filter { $0.progress > 0.01 }.count * 2 >= items.count }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var rows: [HomeRow] = []
    @Published var error: String?
    @Published var loaded = false
    /// Folders that are tools rather than content.
    private let skipped = ["search", "settings", "tools", "setup", "بحث", "إعدادات", "الإعدادات"]

    /// Up to eight titles with artwork, one from each row first, for the carousel.
    var featured: [MediaItem] {
        var picks: [MediaItem] = []
        for depth in 0..<4 {
            for row in rows where row.items.count > depth {
                let item = row.items[depth]
                if item.backdrop != nil, !picks.contains(where: { $0.id == item.id }) { picks.append(item) }
                if picks.count == 8 { return picks }
            }
        }
        return picks
    }

    func load(_ kodi: Kodi, source: String) async {
        error = nil
        do {
            let folders = try await kodi.directory(source).filter { folder in
                folder.isFolder && !skipped.contains { folder.title.lowercased().contains($0) }
            }
            var loaded: [HomeRow] = []
            try await withThrowingTaskGroup(of: (Int, HomeRow?).self) { group in
                for (index, folder) in folders.prefix(10).enumerated() {
                    group.addTask {
                        let items = (try? await kodi.directory(folder.file)) ?? []
                        return (index, items.isEmpty ? nil : HomeRow(id: folder.file, title: folder.title, items: Array(items.prefix(24))))
                    }
                }
                var ordered: [(Int, HomeRow)] = []
                for try await (index, row) in group { if let row { ordered.append((index, row)) } }
                loaded = ordered.sorted { $0.0 < $1.0 }.map(\.1)
            }
            rows = loaded
            if loaded.isEmpty { error = "Nothing to show from this add-on yet.\nPick another one in Settings." }
        } catch {
            self.error = error.localizedDescription
        }
        self.loaded = true
    }
}

struct HomeScreen: View {
    @ObservedObject var kodi: Kodi
    let select: (MediaItem) -> Void
    @StateObject private var model = HomeModel()
    @AppStorage("DexAppleHomeSource") private var source = "plugin://plugin.video.dexhub.tvos/"
    @AppStorage(Look.rotate) private var rotate = true
    @FocusState private var focused: String?
    @State private var page = 0
    @State private var backdropItem: MediaItem?

    private var heroItem: MediaItem? {
        let picks = model.featured
        return picks.isEmpty ? model.rows.first?.items.first : picks[page % picks.count]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(item: backdropItem ?? heroItem)
            if !model.loaded || model.rows.isEmpty {
                LoadState(error: model.loaded ? model.error : nil) { Task { await model.load(kodi, source: source) } }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 56) {
                        if let hero = heroItem {
                            Hero(item: hero, pages: model.featured.count, page: page % max(1, model.featured.count),
                                 play: { kodi.play(hero) }, details: { select(hero) })
                                .id(hero.id)
                                .transition(.opacity)
                        }
                        ForEach(model.rows) { row in
                            Shelf(row: row, focused: $focused, select: select)
                        }
                    }
                    .padding(.bottom, 80)
                }
                .scrollClipDisabled()
            }
        }
        .task(id: source) { await model.load(kodi, source: source) }
        .task(id: rotate) {
            // The carousel turns while focus rests on the featured title.
            while rotate, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(9))
                if focused == nil, model.featured.count > 1 {
                    withAnimation(.easeInOut(duration: 0.7)) { page += 1 }
                }
            }
        }
        .onChange(of: focused) { _, id in
            // The background follows focus, as in the Apple TV app.
            let item = id.flatMap { id in model.rows.lazy.flatMap(\.items).first { $0.id == id } }
            withAnimation(.easeInOut(duration: 0.45)) { backdropItem = item?.backdrop == nil ? nil : item }
        }
    }
}

struct Hero: View {
    let item: MediaItem
    let pages: Int
    let page: Int
    let play: () -> Void
    let details: () -> Void
    @AppStorage(Look.plot) private var showPlot = true
    @AppStorage(Look.ratings) private var showRatings = true
    @AppStorage(Look.accent) private var accent = "violet"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 120)
            ClearLogo(item: item, height: 200)
            MetaLine(item: item)
            if showRatings, item.rating > 0 { Rating(item: item) }
            if showPlot, !item.plot.isEmpty {
                Text(item.plot).font(.system(size: 24)).foregroundStyle(.white.opacity(0.85)).lineLimit(2).frame(maxWidth: 900, alignment: .leading)
            }
            HStack(spacing: 24) {
                if !item.isFolder {
                    Button(action: play) { Label(item.progress > 0.01 ? "Resume" : "Play", systemImage: "play.fill").padding(.horizontal, 12) }
                }
                Button(action: details) { Text(item.isFolder ? "Open" : "Details").padding(.horizontal, 12) }
            }
            .padding(.top, 8)
            if pages > 1 {
                HStack(spacing: 12) {
                    ForEach(0..<pages, id: \.self) { index in
                        Capsule().fill(index == page ? Look.accentColor(accent) : .white.opacity(0.35))
                            .frame(width: index == page ? 28 : 10, height: 10)
                    }
                }
                .animation(.easeInOut, value: page)
                .padding(.top, 6)
            }
        }
        .frame(height: 760, alignment: .bottomLeading)
        .padding(.horizontal, 80)
    }
}

/// "2026 · Crime · Drama  [16+] [4K] [Dolby Vision]"
struct MetaLine: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 16) {
            if !item.metadata.isEmpty {
                Text(item.metadata.joined(separator: "  ·  ")).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            Badges(labels: (item.mpaa.isEmpty ? [] : [item.mpaa]) + item.badges)
        }
    }
}

struct Rating: View {
    let item: MediaItem

    var body: some View {
        Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.2))
    }
}

struct Shelf: View {
    let row: HomeRow
    var focused: FocusState<String?>.Binding
    let select: (MediaItem) -> Void
    @AppStorage(Look.logoCards) private var logoCards = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title).font(.system(size: 32, weight: .bold)).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(row.items) { item in
                        Button { select(item) } label: {
                            if row.resumes || (logoCards && !row.posters) {
                                LogoCard(item: item)
                            } else if row.posters {
                                PosterCard(item: item)
                            } else {
                                LandscapeCard(title: item.title, subtitle: item.metadata.joined(separator: " · "),
                                              image: item.landscape ?? item.poster, progress: item.progress)
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                        .focused(focused, equals: item.id)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

// MARK: Add-ons and folders

struct AddonsScreen: View {
    @ObservedObject var kodi: Kodi
    let select: (MediaItem) -> Void
    @State private var addons: [Addon] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded || addons.isEmpty {
                LoadState(error: loaded ? (error ?? "No video add-ons are installed.") : nil) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(400), spacing: 48), count: 4), alignment: .leading, spacing: 56) {
                        ForEach(addons) { addon in
                            NavigationLink(value: Route.directory(path: addon.path, title: addon.name)) {
                                LandscapeCard(title: addon.name, subtitle: addon.id, image: addon.icon, fit: true)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(80)
                }
                .scrollClipDisabled()
            }
        }
        .background(Theme.ground)
        .task { if !loaded { await load() } }
    }

    private func load() async {
        do { addons = try await kodi.addons(); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct DirectoryScreen: View {
    @ObservedObject var kodi: Kodi
    let path: String
    let title: String
    let select: (MediaItem) -> Void
    @State private var items: [MediaItem] = []
    @State private var error: String?
    @State private var loaded = false

    private var posters: Bool { items.filter(\.hasPoster).count * 2 >= max(1, items.count) && !items.isEmpty }

    var body: some View {
        Group {
            if !loaded || items.isEmpty {
                LoadState(error: loaded ? (error ?? "This folder is empty.") : nil) { Task { await load() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        Text(title).font(.system(size: 52, weight: .heavy))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(posters ? 220 : 400), spacing: 48), count: posters ? 7 : 4),
                                  alignment: .leading, spacing: 56) {
                            ForEach(items) { item in
                                Button { select(item) } label: {
                                    if posters {
                                        PosterCard(item: item)
                                    } else {
                                        LandscapeCard(title: item.title, subtitle: item.metadata.joined(separator: " · "),
                                                      image: item.landscape ?? item.poster, progress: item.progress)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                    .padding(80)
                }
                .scrollClipDisabled()
            }
        }
        .background(Theme.ground)
        .task { if !loaded { await load() } }
    }

    private func load() async {
        do { items = try await kodi.directory(path); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

// MARK: Details

struct DetailsScreen: View {
    @ObservedObject var kodi: Kodi
    let item: MediaItem
    @AppStorage(Look.ratings) private var showRatings = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(item: item)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 60) {
                    VStack(alignment: .leading, spacing: 24) {
                        Spacer(minLength: 0)
                        ClearLogo(item: item, height: 220)
                        MetaLine(item: item)
                        if !item.tagline.isEmpty {
                            Text(item.tagline).font(.system(size: 24, weight: .medium)).italic().foregroundStyle(Theme.secondary)
                        }
                        HStack(spacing: 24) {
                            Button { kodi.play(item) } label: {
                                Label(item.progress > 0.01 ? "Resume · \(item.timeLeft)" : "Play", systemImage: "play.fill").padding(.horizontal, 16)
                            }
                            if !item.trailer.isEmpty {
                                Button { kodi.playTrailer(item.trailer) } label: { Label("Trailer", systemImage: "film") }
                            }
                            Button { kodi.command("kodi") } label: { Label("Kodi Mode", systemImage: "square.grid.2x2") }
                        }
                        .padding(.top, 8)
                        if !item.plot.isEmpty {
                            Text(item.plot).font(.system(size: 26)).foregroundStyle(.white.opacity(0.88)).lineLimit(3).frame(maxWidth: 1100, alignment: .leading)
                        }
                        HStack(spacing: 32) {
                            if showRatings, item.rating > 0 { Rating(item: item) }
                            if !item.directors.isEmpty {
                                Text("Directed by \(item.directors.prefix(2).joined(separator: ", "))")
                                    .font(.system(size: 22)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    .frame(height: 980, alignment: .bottomLeading)
                    .padding(.horizontal, 80)
                    .focusSection()

                    if !item.cast.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Cast & Crew").font(.system(size: 32, weight: .bold)).padding(.horizontal, 80)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 44) {
                                    ForEach(item.cast, id: \.self) { person in
                                        Button {} label: { PersonCard(person: person) }
                                            .buttonStyle(CardButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 80)
                                .padding(.vertical, 20)
                            }
                            .scrollClipDisabled()
                        }
                        .padding(.bottom, 80)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

struct PersonCard: View {
    let person: CastMember

    var body: some View {
        VStack(spacing: 14) {
            Artwork(url: person.photo) {
                ZStack {
                    Theme.tint(for: person.name)
                    Text(String(person.name.prefix(1))).font(.system(size: 64, weight: .heavy))
                }
            }
            .frame(width: 190, height: 190)
            .clipShape(Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            VStack(spacing: 4) {
                FocusLabel(text: person.name)
                Text(person.role).font(.system(size: 18)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .frame(width: 210)
        }
    }
}

// MARK: Kodi mode and settings

struct KodiScreen: View {
    @ObservedObject var kodi: Kodi
    @AppStorage(Look.accent) private var accent = "violet"

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "square.grid.2x2").font(.system(size: 80, weight: .light)).foregroundStyle(Look.accentColor(accent))
            Text("Kodi Mode").font(.system(size: 56, weight: .heavy))
            Text("The full Kodi with the Dex Hub skin, for add-ons that need their own windows.\nPress Back on Kodi's Home to return here.")
                .font(.system(size: 26)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            Button { kodi.command("kodi") } label: { Text("Open Kodi Mode").padding(.horizontal, 24) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
    }
}

struct SettingsScreen: View {
    @ObservedObject var kodi: Kodi
    @AppStorage("DexAppleHomeSource") private var source = "plugin://plugin.video.dexhub.tvos/"
    @AppStorage(Look.background) private var background = "full"
    @AppStorage(Look.accent) private var accent = "violet"
    @AppStorage(Look.rotate) private var rotate = true
    @AppStorage(Look.logoCards) private var logoCards = true
    @AppStorage(Look.plot) private var showPlot = true
    @AppStorage(Look.ratings) private var showRatings = true
    @State private var addons: [Addon] = []

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Background", selection: $background) {
                    Text("Full artwork").tag("full")
                    Text("Artwork colour").tag("ambient")
                    Text("Plain").tag("plain")
                }
                .pickerStyle(.navigationLink)
                Picker("Accent", selection: $accent) {
                    ForEach(Look.accents, id: \.id) { option in
                        Label { Text(option.name) } icon: { Circle().fill(option.color).frame(width: 24, height: 24) }.tag(option.id)
                    }
                }
                .pickerStyle(.navigationLink)
                Toggle("Rotate featured titles", isOn: $rotate)
                Toggle("Clear-logo cards", isOn: $logoCards)
                Toggle("Show synopsis", isOn: $showPlot)
                Toggle("Show ratings", isOn: $showRatings)
            }
            Section("Home rows come from") {
                ForEach(addons) { addon in
                    Button { source = addon.path } label: {
                        HStack {
                            Text(addon.name)
                            Spacer()
                            if source == addon.path { Image(systemName: "checkmark").foregroundStyle(Look.accentColor(accent)) }
                        }
                    }
                }
            }
            Section {
                Button("Open Kodi Mode") { kodi.command("kodi") }
            }
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .background(Theme.ground)
        .task { addons = (try? await kodi.addons()) ?? [] }
    }
}
