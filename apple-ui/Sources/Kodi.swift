import Foundation
import SwiftUI

/// One entry of a Kodi directory: an add-on folder, a movie, an episode.
struct MediaItem: Identifiable, Hashable {
    let id: String
    let title: String
    let file: String
    let isFolder: Bool
    let type: String
    let plot: String
    let year: Int
    let rating: Double
    let runtime: Int
    let genres: [String]
    let showTitle: String
    let season: Int
    let episode: Int
    let progress: Double
    let art: [String: URL]
    let cast: [CastMember]
    let directors: [String]
    let tagline: String
    let mpaa: String
    let premiered: String
    let trailer: String
    /// From the file's stream details: "4K", "Dolby Vision", "Atmos"…
    let badges: [String]
    /// Seconds left, for Continue Watching.
    let remaining: Int
    /// The IMDb ID Stremio add-ons look sources up by (the show's, for an episode).
    let imdbID: String?
    var isEpisode: Bool { season >= 0 && episode >= 0 && (type == "episode" || !showTitle.isEmpty) }

    var poster: URL? { art["poster"] ?? art["tvshow.poster"] ?? art["thumb"] ?? art["icon"] }
    var backdrop: URL? { art["fanart"] ?? art["tvshow.fanart"] ?? art["landscape"] ?? art["thumb"] }
    var landscape: URL? { art["landscape"] ?? art["tvshow.landscape"] ?? art["fanart"] ?? art["thumb"] }
    var clearLogo: URL? { art["clearlogo"] ?? art["tvshow.clearlogo"] ?? art["logo"] }
    var timeLeft: String {
        guard remaining > 0 else { return "" }
        return remaining >= 3600 ? "\(remaining / 3600)h \(remaining % 3600 / 60)m left" : "\(max(1, remaining / 60))m left"
    }
    var hasPoster: Bool { art["poster"] != nil || art["tvshow.poster"] != nil }
    /// Worth a details page before playing (it carries more than a name).
    var isRich: Bool { !plot.isEmpty || art["fanart"] != nil }

    var metadata: [String] {
        var parts: [String] = []
        if !showTitle.isEmpty, season >= 0, episode >= 0 { parts.append("S\(season) · E\(episode)") }
        parts += genres.prefix(2)
        if year > 0 { parts.append(String(year)) }
        if runtime > 0 { parts.append(runtime >= 3600 ? "\(runtime / 3600)h \(runtime % 3600 / 60)m" : "\(runtime / 60)m") }
        return parts
    }

    /// Add-ons put the IMDb ID in different places: the item's unique IDs, a
    /// list item property, or the plugin URL. An episode needs its show's.
    static func imdb(_ row: [String: Any], episode: Bool) -> String? {
        let valid = { (value: String) -> String? in value.range(of: #"^tt\d{6,}$"#, options: .regularExpression) != nil ? value : nil }
        let properties = row["customproperties"] as? [String: Any] ?? [:]
        let unique = row["uniqueid"] as? [String: Any] ?? [:]
        let showKeys = properties.filter { $0.key.lowercased().contains("imdb") && $0.key.lowercased().contains("show") }
        let anyKeys = properties.filter { $0.key.lowercased().contains("imdb") }
        let fromURL = (row["file"] as? String).flatMap { file -> String? in
            file.range(of: #"tt\d{6,}"#, options: .regularExpression).map { String(file[$0]) }
        }
        let ordered: [String?] = episode
            ? showKeys.values.map { $0 as? String } + [fromURL] + anyKeys.values.map { $0 as? String } + [unique["imdb"] as? String]
            : [unique["imdb"] as? String] + anyKeys.values.map { $0 as? String } + [fromURL]
        return ordered.compactMap { $0.flatMap(valid) }.first
    }

    /// Quality labels in the order Apple's TV app shows them.
    static func badges(_ details: [String: Any]) -> [String] {
        var labels: [String] = []
        if let video = (details["video"] as? [[String: Any]])?.first {
            let width = video["width"] as? Int ?? 0
            if width >= 3200 { labels.append("4K") } else if width >= 1800 { labels.append("HD") }
            switch (video["hdrtype"] as? String ?? "").lowercased() {
            case "dolbyvision": labels.append("Dolby Vision")
            case "hdr10", "hdr10plus": labels.append("HDR10")
            case "hlg": labels.append("HLG")
            default: break
            }
        }
        if let audio = (details["audio"] as? [[String: Any]])?.first {
            let codec = (audio["codec"] as? String ?? "").lowercased()
            let channels = audio["channels"] as? Int ?? 0
            if codec.contains("truehd") || codec.contains("atmos") { labels.append("Dolby Atmos") }
            else if codec.contains("eac3") || codec.contains("ac3") { labels.append(channels > 2 ? "Dolby 5.1" : "Dolby") }
            else if codec.contains("dts") { labels.append("DTS") }
        }
        return labels
    }

    init(_ row: [String: Any]) {
        file = row["file"] as? String ?? ""
        let label = row["label"] as? String ?? ""
        let name = row["title"] as? String ?? ""
        title = name.isEmpty ? label : name
        id = file.isEmpty ? label : file
        isFolder = (row["filetype"] as? String) == "directory"
        type = row["type"] as? String ?? ""
        plot = row["plot"] as? String ?? ""
        year = row["year"] as? Int ?? 0
        rating = row["rating"] as? Double ?? 0
        runtime = row["runtime"] as? Int ?? 0
        genres = row["genre"] as? [String] ?? []
        showTitle = row["showtitle"] as? String ?? ""
        season = row["season"] as? Int ?? -1
        episode = row["episode"] as? Int ?? -1
        if let resume = row["resume"] as? [String: Any], let position = resume["position"] as? Double,
           let total = resume["total"] as? Double, total > 0 {
            progress = position / total
            remaining = Int(total - position)
        } else {
            progress = 0
            remaining = 0
        }
        cast = (row["cast"] as? [[String: Any]] ?? []).prefix(20).compactMap { person in
            guard let name = person["name"] as? String, !name.isEmpty else { return nil }
            return CastMember(name: name, role: person["role"] as? String ?? "",
                              photo: Kodi.imageURL(person["thumbnail"] as? String ?? ""))
        }
        directors = row["director"] as? [String] ?? []
        tagline = row["tagline"] as? String ?? ""
        mpaa = (row["mpaa"] as? String ?? "").replacingOccurrences(of: "Rated ", with: "")
        premiered = row["premiered"] as? String ?? ""
        trailer = row["trailer"] as? String ?? ""
        badges = Self.badges(row["streamdetails"] as? [String: Any] ?? [:])
        imdbID = Self.imdb(row, episode: (row["season"] as? Int ?? -1) >= 0 && (row["episode"] as? Int ?? -1) >= 0)
        var art: [String: URL] = [:]
        for (key, value) in row["art"] as? [String: String] ?? [:] {
            if let url = Kodi.imageURL(value) { art[key] = url }
        }
        if art["thumb"] == nil, let thumb = row["thumbnail"] as? String, let url = Kodi.imageURL(thumb) { art["thumb"] = url }
        if art["fanart"] == nil, let fanart = row["fanart"] as? String, let url = Kodi.imageURL(fanart) { art["fanart"] = url }
        self.art = art
    }
}

struct CastMember: Hashable {
    let name: String
    let role: String
    let photo: URL?
}

struct Addon: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: URL?
    let backdrop: URL?
    var path: String { "plugin://\(id)/" }
}

enum KodiError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

/// Kodi seen from the native screens: JSON-RPC inside the app, plus a few
/// commands to the host (switch to Kodi mode).
final class Kodi: ObservableObject {
    typealias RPC = (String, @escaping (String) -> Void) -> Void
    private let rpc: RPC
    private let commandHandler: (String) -> Void
    private var nextID = 1

    init(rpc: @escaping RPC, command: @escaping (String) -> Void) {
        self.rpc = rpc
        commandHandler = command
    }

    func command(_ name: String) { commandHandler(name) }

    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let request: [String: Any] = ["jsonrpc": "2.0", "id": nextID, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: request)
        let text = String(decoding: data, as: UTF8.self)
        let reply: String = await withCheckedContinuation { continuation in
            rpc(text) { continuation.resume(returning: $0) }
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any] else {
            throw KodiError.failed("Kodi sent an unreadable reply")
        }
        if let error = object["error"] as? [String: Any] {
            throw KodiError.failed(error["message"] as? String ?? "Kodi error")
        }
        return object["result"] as? [String: Any] ?? [:]
    }

    // Every name must be in Kodi's List.Fields.Files, or the whole request fails.
    static let fields = ["title", "art", "plot", "year", "rating", "runtime", "genre", "showtitle",
                         "season", "episode", "thumbnail", "fanart", "resume", "cast", "director",
                         "tagline", "mpaa", "premiered", "trailer", "streamdetails", "uniqueid", "customproperties"]

    func directory(_ path: String) async throws -> [MediaItem] {
        let result = try await call("Files.GetDirectory", ["directory": path, "media": "video", "properties": Self.fields])
        return (result["files"] as? [[String: Any]] ?? []).map(MediaItem.init)
    }

    func addons() async throws -> [Addon] {
        let result = try await call("Addons.GetAddons", ["type": "xbmc.addon.video", "enabled": true,
                                                         "properties": ["name", "thumbnail", "fanart"]])
        return (result["addons"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["addonid"] as? String else { return nil }
            return Addon(id: id, name: row["name"] as? String ?? id,
                         icon: Self.imageURL(row["thumbnail"] as? String ?? ""),
                         backdrop: Self.imageURL(row["fanart"] as? String ?? ""))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A source found by the native screens, played by Kodi (Aether).
    func play(source: StreamSource, for item: MediaItem) {
        Task { _ = try? await call("Player.Open", ["item": ["file": source.kodiPath]]) }
    }

    func playTrailer(_ file: String) {
        Task { _ = try? await call("Player.Open", ["item": ["file": file]]) }
    }

    func play(_ item: MediaItem) {
        Task { _ = try? await call("Player.Open", ["item": ["file": item.file]]) }
    }

    /// Kodi wraps artwork as image://<percent-encoded source>/.
    static func imageURL(_ value: String) -> URL? {
        var text = value
        if text.hasPrefix("image://") {
            text.removeFirst("image://".count)
            if text.hasSuffix("/") { text.removeLast() }
            text = text.removingPercentEncoding ?? text
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text) }
        return nil
    }
}
