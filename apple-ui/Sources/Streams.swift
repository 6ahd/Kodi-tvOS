import Foundation

/// A Stremio-style add-on the person set up in Dex Hub (providers.json).
struct StreamProvider: Identifiable {
    let id: String
    let name: String
    let base: String
    let query: String
    let logo: URL?
    let types: Set<String>
    let prefixes: [String]

    init?(_ row: [String: Any]) {
        let manifest = row["manifest"] as? [String: Any] ?? [:]
        let configured = (row["manifest_url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if let range = configured.range(of: "/manifest.json") {
            base = String(configured[..<range.lowerBound])
            query = configured[range.upperBound...].hasPrefix("?") ? String(configured[range.upperBound...].dropFirst()) : ""
        } else {
            base = (row["base_url"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            query = ""
        }
        guard base.hasPrefix("http"), row["enabled"] as? Bool ?? true else { return nil }
        // Only add-ons that answer the stream resource.
        var types = Set(manifest["types"] as? [String] ?? [])
        var prefixes = manifest["idPrefixes"] as? [String] ?? []
        var streams = false
        for resource in manifest["resources"] as? [Any] ?? [] {
            if let name = resource as? String, name == "stream" { streams = true }
            if let object = resource as? [String: Any], object["name"] as? String == "stream" {
                streams = true
                if let own = object["types"] as? [String] { types = Set(own) }
                if let own = object["idPrefixes"] as? [String] { prefixes = own }
            }
        }
        guard streams || manifest.isEmpty else { return nil }
        id = row["id"] as? String ?? base
        name = row["name"] as? String ?? manifest["name"] as? String ?? URL(string: base)?.host ?? base
        logo = (manifest["logo"] as? String).flatMap(URL.init(string:))
        self.types = types
        self.prefixes = prefixes
    }

    func serves(type: String, id: String) -> Bool {
        (types.isEmpty || types.contains(type)) && (prefixes.isEmpty || prefixes.contains { id.hasPrefix($0) })
    }

    func url(type: String, id: String) -> URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        return URL(string: "\(base)/stream/\(type)/\(encoded).json" + (query.isEmpty ? "" : "?\(query)"))
    }
}

/// One playable source, with the facts people choose by.
struct StreamSource: Identifiable {
    let id = UUID()
    let provider: StreamProvider
    let name: String
    let detail: String
    let url: String
    let headers: [String: String]
    let resolution: String   // 4K, 1080p, 720p, SD
    let badges: [String]     // Dolby Vision, HDR10, Atmos, DTS-HD MA, 7.1…
    let size: String
    let bytes: Double
    let cached: Bool

    /// Kodi's way of passing request headers: url|Name=value&Name=value
    var kodiPath: String {
        guard !headers.isEmpty else { return url }
        let pairs = headers.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }
        return url + "|" + pairs.joined(separator: "&")
    }

    var rank: Int { ["4K": 4, "1080p": 3, "720p": 2][resolution] ?? 1 }

    init?(_ row: [String: Any], provider: StreamProvider) {
        guard let url = row["url"] as? String, url.hasPrefix("http") else { return nil } // torrents need a debrid link
        self.provider = provider
        self.url = url
        let hints = row["behaviorHints"] as? [String: Any] ?? [:]
        let title = (row["title"] as? String) ?? (row["description"] as? String) ?? ""
        let label = row["name"] as? String ?? provider.name
        let filename = hints["filename"] as? String ?? ""
        let text = [label, title, filename].joined(separator: " ")
        let lower = text.lowercased()
        name = label.replacingOccurrences(of: "\n", with: " ")
        detail = filename.isEmpty ? (title.split(separator: "\n").first.map(String.init) ?? "") : filename
        var headers: [String: String] = [:]
        if let proxy = hints["proxyHeaders"] as? [String: Any], let request = proxy["request"] as? [String: String] { headers = request }
        self.headers = headers
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") { resolution = "4K" }
        else if lower.contains("1080") { resolution = "1080p" }
        else if lower.contains("720") { resolution = "720p" }
        else { resolution = "SD" }
        var badges: [String] = []
        if lower.contains("dolby vision") || lower.contains(" dv") || lower.contains(".dv.") || lower.contains("dovi") { badges.append("Dolby Vision") }
        if lower.contains("hdr10+") { badges.append("HDR10+") } else if lower.contains("hdr") { badges.append("HDR") }
        if lower.contains("atmos") { badges.append("Atmos") }
        if lower.contains("truehd") { badges.append("TrueHD") }
        else if lower.contains("dts-hd") || lower.contains("dts hd") { badges.append("DTS-HD MA") }
        else if lower.contains("dts") { badges.append("DTS") }
        else if lower.contains("ddp") || lower.contains("dd+") || lower.contains("eac3") { badges.append("DD+") }
        if lower.contains("7.1") { badges.append("7.1") } else if lower.contains("5.1") { badges.append("5.1") }
        self.badges = badges
        if let size = hints["videoSize"] as? Double, size > 0 {
            bytes = size
        } else if let match = text.range(of: #"(\d+(?:\.\d+)?)\s?(GB|MB|GiB|MiB)"#, options: [.regularExpression, .caseInsensitive]) {
            let parts = text[match].split(whereSeparator: { $0 == " " || $0.isLetter }).first.map(String.init) ?? "0"
            let number = Double(parts.filter { $0.isNumber || $0 == "." }) ?? 0
            // Sizes are written as the add-on shows them; keep the same number on screen.
            bytes = number * (text[match].uppercased().contains("G") ? 1_000_000_000 : 1_000_000)
        } else {
            bytes = 0
        }
        size = bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) : ""
        cached = text.contains("⚡") || lower.contains("[rd+]") || lower.contains("cached") || lower.contains("[ad+]") || lower.contains("[pm+]")
    }
}

/// Finds sources for one title across every Stremio-style add-on in Dex Hub.
@MainActor
final class SourceSearch: ObservableObject {
    @Published var sources: [StreamSource] = []
    @Published var searching = false
    @Published var asked = 0
    @Published var answered = 0
    @Published var message: String?

    /// Dex Hub keeps one providers.json per profile; the newest is the active one.
    nonisolated static func providers() -> [StreamProvider] {
        let fm = FileManager.default
        var roots: [URL] = []
        if let data = UserDefaults.standard.string(forKey: "DexAppleDexHubData") { roots.append(URL(fileURLWithPath: data)) }
        let candidates = roots.flatMap { root -> [URL] in
            let profiles = root.appendingPathComponent("profiles")
            let names = (try? fm.contentsOfDirectory(atPath: profiles.path)) ?? []
            return names.map { profiles.appendingPathComponent($0).appendingPathComponent("providers.json") }
                + [root.appendingPathComponent("providers.json")]
        }
        let newest = candidates.filter { fm.fileExists(atPath: $0.path) }.max { a, b in
            let da = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
            let db = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
            return da < db
        }
        guard let newest, let data = try? Data(contentsOf: newest),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap(StreamProvider.init)
    }

    func search(_ item: MediaItem, providers: [StreamProvider] = SourceSearch.providers()) async {
        guard let imdb = item.imdbID else {
            message = "This title has no IMDb ID, so add-on sources cannot be looked up."
            return
        }
        let type = item.isEpisode ? "series" : "movie"
        let id = item.isEpisode ? "\(imdb):\(item.season):\(item.episode)" : imdb
        let targets = providers.filter { $0.serves(type: type, id: id) }
        guard !targets.isEmpty else {
            message = providers.isEmpty ? "No source add-ons are set up in Dex Hub yet." : "None of your add-ons serves this title."
            return
        }
        searching = true
        asked = targets.count
        answered = 0
        sources = []
        message = nil
        await withTaskGroup(of: [StreamSource].self) { group in
            for provider in targets {
                group.addTask {
                    guard let url = provider.url(type: type, id: id) else { return [] }
                    var request = URLRequest(url: url, timeoutInterval: 20)
                    if provider.name.lowercased().contains("aiostreams") { request.setValue("AIOStreams/DexHub", forHTTPHeaderField: "User-Agent") }
                    guard let (data, _) = try? await URLSession.shared.data(for: request),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
                    return (object["streams"] as? [[String: Any]] ?? []).compactMap { StreamSource($0, provider: provider) }
                }
            }
            for await found in group {
                answered += 1
                sources = (sources + found).sorted { a, b in
                    if a.rank != b.rank { return a.rank > b.rank }
                    if a.cached != b.cached { return a.cached }
                    return a.bytes > b.bytes
                }
            }
        }
        searching = false
        if sources.isEmpty { message = "No playable sources were found." }
    }
}
