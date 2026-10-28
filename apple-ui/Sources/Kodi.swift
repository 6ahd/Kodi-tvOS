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

    var poster: URL? { art["poster"] ?? art["tvshow.poster"] ?? art["thumb"] ?? art["icon"] }
    var backdrop: URL? { art["fanart"] ?? art["tvshow.fanart"] ?? art["landscape"] ?? art["thumb"] }
    var landscape: URL? { art["landscape"] ?? art["tvshow.landscape"] ?? art["fanart"] ?? art["thumb"] }
    var clearLogo: URL? { art["clearlogo"] ?? art["tvshow.clearlogo"] ?? art["logo"] }
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
        } else {
            progress = 0
        }
        var art: [String: URL] = [:]
        for (key, value) in row["art"] as? [String: String] ?? [:] {
            if let url = Kodi.imageURL(value) { art[key] = url }
        }
        if art["thumb"] == nil, let thumb = row["thumbnail"] as? String, let url = Kodi.imageURL(thumb) { art["thumb"] = url }
        if art["fanart"] == nil, let fanart = row["fanart"] as? String, let url = Kodi.imageURL(fanart) { art["fanart"] = url }
        self.art = art
    }
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

    static let fields = ["title", "art", "plot", "year", "rating", "runtime", "genre", "showtitle",
                         "season", "episode", "thumbnail", "fanart", "resume"]

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
