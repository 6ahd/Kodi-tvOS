import SwiftUI

/// Runs the native screens in the tvOS simulator on sample replies, without Kodi.
@main
struct PreviewApp: App {
    @StateObject private var kodi = Kodi(rpc: SampleKodi.reply, command: { print("command:", $0) })

    var body: some Scene {
        WindowGroup { RootView(kodi: kodi) }
    }
}

enum SampleKodi {
    static func reply(_ request: String, _ done: @escaping (String) -> Void) {
        let object = (try? JSONSerialization.jsonObject(with: Data(request.utf8))) as? [String: Any] ?? [:]
        let method = object["method"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "Addons.GetAddons": result = ["addons": addons]
        case "Files.GetDirectory": result = ["files": directory(params["directory"] as? String ?? "")]
        default: result = [:]
        }
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": object["id"] ?? 0, "result": result])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done(String(decoding: data, as: UTF8.self)) }
    }

    static let addons: [[String: Any]] = [
        ["addonid": "plugin.video.dexhub.tvos", "name": "Dex Hub"],
        ["addonid": "plugin.video.themoviedb.helper", "name": "TheMovieDb Helper"],
        ["addonid": "plugin.video.youtube", "name": "YouTube"],
        ["addonid": "plugin.video.jellyfin", "name": "Jellyfin"],
        ["addonid": "plugin.video.plex", "name": "Plex"],
        ["addonid": "plugin.video.iptv", "name": "IPTV Simple"]
    ]

    static func directory(_ path: String) -> [[String: Any]] {
        if path.hasSuffix("/") {
            return ["Continue Watching", "Trending Movies", "Popular Shows", "New Episodes", "Search"].map {
                ["label": $0, "file": path + $0.replacingOccurrences(of: " ", with: "_"), "filetype": "directory"]
            }
        }
        let shows = path.contains("Shows") || path.contains("Episodes") || path.contains("Continue")
        let names = shows
            ? ["Salt & Ash", "The Northern Line", "Paper Kings", "Night Ferry", "Glasshouse", "Low Orbit", "Signal Box", "Blue Hour"]
            : ["Deadfall", "Clayborne", "Hollow Out", "Masterline", "The Fixer", "Animals", "Red Room", "Iceman", "Runway 9", "Whalefall"]
        return names.enumerated().map { index, name in
            var row: [String: Any] = [
                "label": name, "title": name, "file": "plugin://sample/play/\(index)", "filetype": "file",
                "year": 2026, "genre": shows ? ["Drama", "Thriller"] : ["Thriller"], "runtime": shows ? 3120 : 6600 + index * 300,
                "plot": "\(name) follows a quiet investigator through one long winter, where every answer costs a little more than the last.",
                "rating": 7.1 + Double(index % 3) / 2, "mpaa": index % 2 == 0 ? "16+" : "13+",
                "tagline": "Every answer has a price.", "director": ["Mira Hanssen"],
                "trailer": "plugin://sample/trailer/\(index)",
                "cast": ["Lena Ortiz", "Tomas Reyes", "Hana Sato", "Idris Cole", "Noor Haddad", "Elias Berg"].enumerated().map { i, person in
                    ["name": person, "role": i == 0 ? "Inspector Vale" : "Role \(i + 1)"]
                },
                "streamdetails": ["video": [["width": index % 3 == 0 ? 3840 : 1920, "hdrtype": index % 3 == 0 ? "dolbyvision" : ""]],
                                  "audio": [["codec": index % 2 == 0 ? "truehd" : "eac3", "channels": 8]]],
                "art": ["poster": SampleArt.file(name, kind: .poster, index: index),
                        "fanart": SampleArt.file(name, kind: .backdrop, index: index),
                        "clearlogo": SampleArt.file(name, kind: .logo, index: index)]
            ]
            if path.contains("Continue") {
                row["resume"] = ["position": Double(600 + index * 400), "total": 3120.0]
            }
            if shows {
                row["showtitle"] = name
                row["season"] = 1 + index % 3
                row["episode"] = 2 + index
            }
            return row
        }
    }
}

/// Local stand-in artwork, drawn once into the temporary folder.
enum SampleArt {
    enum Kind: String { case poster, backdrop, logo }
    static let hues: [UIColor] = [
        UIColor(red: 0.55, green: 0.24, blue: 0.18, alpha: 1), UIColor(red: 0.13, green: 0.36, blue: 0.52, alpha: 1),
        UIColor(red: 0.36, green: 0.42, blue: 0.16, alpha: 1), UIColor(red: 0.42, green: 0.2, blue: 0.52, alpha: 1),
        UIColor(red: 0.16, green: 0.42, blue: 0.4, alpha: 1)
    ]

    static func file(_ name: String, kind: Kind, index: Int) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(kind.rawValue)-\(index)-\(name.hashValue).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            let size = kind == .poster ? CGSize(width: 400, height: 600) : kind == .backdrop ? CGSize(width: 1920, height: 1080) : CGSize(width: 900, height: 260)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = kind != .logo
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                let hue = hues[index % hues.count]
                if kind != .logo {
                    let colors = [hue.cgColor, UIColor(white: 0.03, alpha: 1).cgColor] as CFArray
                    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                    context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                    let glow = [UIColor(white: 1, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                    let light = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1])!
                    let centre = CGPoint(x: size.width * 0.7, y: size.height * 0.35)
                    context.cgContext.drawRadialGradient(light, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: size.width * 0.5, options: [])
                }
                if kind != .backdrop {
                    let fontSize: CGFloat = kind == .logo ? 120 : 64
                    let style = NSMutableParagraphStyle()
                    style.alignment = kind == .logo ? .left : .center
                    let text = NSAttributedString(string: kind == .logo ? name.uppercased() : name, attributes: [
                        .font: UIFont.systemFont(ofSize: fontSize, weight: .black),
                        .foregroundColor: kind == .logo ? UIColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1) : UIColor.white,
                        .paragraphStyle: style, .kern: kind == .logo ? 6 : -1])
                    let box = kind == .logo ? CGRect(origin: .zero, size: size) : CGRect(x: 24, y: size.height - 230, width: size.width - 48, height: 210)
                    text.draw(with: box, options: [.usesLineFragmentOrigin], context: nil)
                }
            }
            try? image.pngData()?.write(to: url)
        }
        return url.path
    }
}
