import SwiftUI

struct RootView: View {
    @ObservedObject var kodi: Kodi

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { Stack(kodi: kodi) { HomeScreen(kodi: kodi, select: $0) } }
            Tab("Add-ons", systemImage: "puzzlepiece.extension") { Stack(kodi: kodi) { AddonsScreen(kodi: kodi, select: $0) } }
            Tab("Kodi", systemImage: "square.grid.2x2") { KodiScreen(kodi: kodi) }
            Tab("Settings", systemImage: "gearshape") { SettingsScreen(kodi: kodi) }
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

// MARK: Home

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
    var posters: Bool { items.filter(\.hasPoster).count * 2 >= items.count }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var rows: [HomeRow] = []
    @Published var error: String?
    @Published var loaded = false
    /// Folders that are tools rather than content.
    private let skipped = ["search", "settings", "tools", "setup", "بحث", "إعدادات", "الإعدادات"]

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
    @FocusState private var focused: String?
    @State private var featured: MediaItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(item: featured)
            if !model.loaded || model.rows.isEmpty {
                LoadState(error: model.loaded ? model.error : nil) { Task { await model.load(kodi, source: source) } }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 56) {
                        if let featured {
                            Hero(item: featured, play: { kodi.play(featured) }, details: { select(featured) })
                                .id(featured.id)
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
        .task(id: source) {
            await model.load(kodi, source: source)
            featured = model.rows.first?.items.first { $0.backdrop != nil } ?? model.rows.first?.items.first
        }
        .onChange(of: focused) { _, id in
            // The backdrop follows focus, as in the Apple TV app.
            guard let id, let item = model.rows.lazy.flatMap(\.items).first(where: { $0.id == id }), item.backdrop != nil else { return }
            withAnimation(.easeInOut(duration: 0.45)) { featured = item }
        }
    }
}

/// The featured title's artwork filling the screen, fading into the ground.
struct Backdrop: View {
    let item: MediaItem?

    var body: some View {
        ZStack {
            Theme.ground
            if let item {
                Artwork(url: item.backdrop) { Color.clear }
                    .id(item.id)
                    .transition(.opacity)
                LinearGradient(colors: [Theme.ground.opacity(0.95), Theme.ground.opacity(0.4), .clear],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, Theme.ground.opacity(0.7), Theme.ground],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

struct Hero: View {
    let item: MediaItem
    let play: () -> Void
    let details: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 140)
            ClearLogo(item: item)
            if !item.metadata.isEmpty {
                Text(item.metadata.joined(separator: "  ·  ")).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            if !item.plot.isEmpty {
                Text(item.plot).font(.system(size: 24)).foregroundStyle(.white.opacity(0.85)).lineLimit(2).frame(maxWidth: 900, alignment: .leading)
            }
            HStack(spacing: 24) {
                if !item.isFolder {
                    Button(action: play) { Label(item.progress > 0.01 ? "Resume" : "Play", systemImage: "play.fill").padding(.horizontal, 12) }
                }
                Button(action: details) { Text(item.isFolder ? "Open" : "Details").padding(.horizontal, 12) }
            }
            .padding(.top, 8)
        }
        .frame(height: 620, alignment: .bottomLeading)
        .padding(.horizontal, 80)
    }
}

struct Shelf: View {
    let row: HomeRow
    var focused: FocusState<String?>.Binding
    let select: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title).font(.system(size: 32, weight: .bold)).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(row.items) { item in
                        Button { select(item) } label: {
                            if row.posters {
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Backdrop(item: item)
            VStack(alignment: .leading, spacing: 24) {
                ClearLogo(item: item, height: 200)
                if !item.metadata.isEmpty {
                    Text(item.metadata.joined(separator: "  ·  ")).font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                if item.rating > 0 {
                    Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.yellow)
                }
                if !item.plot.isEmpty {
                    Text(item.plot).font(.system(size: 26)).foregroundStyle(.white.opacity(0.85)).lineLimit(4).frame(maxWidth: 1000, alignment: .leading)
                }
                HStack(spacing: 24) {
                    Button { kodi.play(item) } label: {
                        Label(item.progress > 0.01 ? "Resume" : "Play", systemImage: "play.fill").padding(.horizontal, 16)
                    }
                    Button { kodi.command("kodi") } label: { Label("Open in Kodi Mode", systemImage: "square.grid.2x2") }
                }
                .padding(.top, 12)
            }
            .padding(80)
        }
    }
}

// MARK: Kodi mode and settings

struct KodiScreen: View {
    @ObservedObject var kodi: Kodi

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "square.grid.2x2").font(.system(size: 80, weight: .light)).foregroundStyle(Theme.accent)
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
    @State private var addons: [Addon] = []

    var body: some View {
        List {
            Section("Home rows come from") {
                ForEach(addons) { addon in
                    Button { source = addon.path } label: {
                        HStack {
                            Text(addon.name)
                            Spacer()
                            if source == addon.path { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
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
