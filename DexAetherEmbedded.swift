import Foundation
import Combine
import UIKit
import AVFoundation
import MediaPlayer
import AetherEngine

private final class SnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var token = ""
    private var value: NSDictionary = [:]
    func begin(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        self.token = token
        value = ["state": "loading"]
    }
    func set(_ token: String, _ value: NSDictionary) {
        lock.lock(); defer { lock.unlock() }
        guard self.token == token else { return }
        self.value = value
    }
    func get(_ token: String) -> NSDictionary? {
        lock.lock(); defer { lock.unlock() }
        return self.token == token ? value : nil
    }
}
private let snapshots = SnapshotStore()

@MainActor
@objc(DexAetherBridge)
public final class DexAetherBridge: NSObject {
    private static var session: EmbeddedSession?

    @objc(startEmbedded:inView:belowView:)
    public static func startEmbedded(_ request: NSDictionary, inView parent: UIView, belowView overlay: UIView) {
        guard let token = request["token"] as? String else { return }
        session?.stop()
        session = nil
        snapshots.begin(token)
        if let engine = request["engine"] as? String, Self.externalEngines.contains(engine) {
            openExternal(request, engine: engine, token: token)
            return
        }
        do {
            let next = try EmbeddedSession(request: request, parent: parent, overlay: overlay)
            session = next
            next.start()
        } catch {
            snapshots.set(token, ["state": "error", "message": error.localizedDescription])
        }
    }

    @objc(snapshotForToken:)
    nonisolated public static func snapshotForToken(_ token: NSString) -> NSDictionary? {
        snapshots.get(token as String)
    }

    @objc(command:)
    public static func command(_ request: NSDictionary) {
        guard let current = session, request["token"] as? String == current.token else { return }
        if request["name"] as? String == "stop" {
            current.stop()
            session = nil
        } else {
            current.command(request)
        }
    }

    // v21.4: every external player Kodi's "Play using" offers. Each gets the
    // resume time and the subtitle where its link takes them.
    static let externalEngines: Set<String> = ["Infuse", "VidHub", "SenPlayer", "VLC", "Native Player", "Outplayer", "nPlayer"]

    private static func openExternal(_ request: NSDictionary, engine: String, token: String) {
        guard let raw = request["url"] as? String,
              let media = URL(string: raw), ["http", "https"].contains(media.scheme?.lowercased() ?? ""),
              !raw.contains("|") else {
            snapshots.set(token, ["state": "error", "message": "External player requires a direct HTTP(S) URL without custom headers."])
            return
        }
        var target = URLComponents()
        let position = max(0, (request["position"] as? NSNumber)?.doubleValue ?? 0)
        let filename = (request["filename"] as? String) ?? ""
        let remoteSubs = ((request["subtitles"] as? [String]) ?? []).filter {
            ["http", "https"].contains(URL(string: $0)?.scheme?.lowercased() ?? "")
        }
        if engine == "nPlayer" {
            // nPlayer takes the address itself under its own scheme
            let rest = raw.components(separatedBy: "://").dropFirst().joined(separator: "://")
            let scheme = media.scheme?.lowercased() == "http" ? "nplayer-http" : "nplayer-https"
            guard let url = URL(string: scheme + "://" + (rest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)) ?? rest)) else { return }
            UIApplication.shared.open(url, options: [:]) { success in
                snapshots.set(token, success ? ["state": "external", "position": position] :
                    ["state": "error", "message": "External app could not be opened. Check that it is installed."])
            }
            return
        }
        var query = [URLQueryItem(name: "url", value: raw)]
        switch engine {
        case "VLC":
            target.scheme = "vlc-x-callback"; target.host = "x-callback-url"; target.path = "/stream"
            if let sub = remoteSubs.first { query.append(URLQueryItem(name: "sub", value: sub)) }
        case "Outplayer":
            target.scheme = "outplayer"; target.host = "x-callback-url"; target.path = "/play"
            if !filename.isEmpty { query.append(URLQueryItem(name: "filename", value: filename)) }
        case "Native Player":
            target.scheme = "nativeplayer"; target.host = "play"; target.path = ""
            query.append(URLQueryItem(name: "position", value: String(Int(position))))
            if !filename.isEmpty {
                query.append(URLQueryItem(name: "name", value: (filename as NSString).deletingPathExtension))
            }
            for sub in remoteSubs.filter({ ["srt", "sub"].contains(URL(string: $0)?.pathExtension.lowercased() ?? "") }).prefix(8) {
                query.append(URLQueryItem(name: "sub", value: sub))
            }
        default:
            // Infuse, VidHub and SenPlayer share the x-callback form
            target.scheme = engine == "VidHub" ? "open-vidhub" : (engine == "SenPlayer" ? "senplayer" : "infuse")
            target.host = "x-callback-url"
            target.path = "/play"
            query.append(URLQueryItem(name: "position", value: String(Int(position))))
            if !filename.isEmpty { query.append(URLQueryItem(name: "filename", value: filename)) }
            for sub in remoteSubs.prefix(engine == "VidHub" ? 1 : 8) {
                query.append(URLQueryItem(name: "sub", value: sub))
            }
        }
        if engine == "Infuse", let home = request["home"] as? String {
            let path = URL(fileURLWithPath: home).appendingPathComponent("dexhub-infuse-pending.json")
            var pending: [String: Any] = [:]
            if let data = try? Data(contentsOf: path),
               let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               value["video"] as? String == raw {
                pending = value
            }
            let callbackToken = UUID().uuidString
            pending["token"] = callbackToken
            pending["video"] = raw
            pending["kodi_path"] = request["kodiPath"] as? String ?? raw
            if let context = request["context"] as? [String: Any], !context.isEmpty {
                pending["context"] = context
            }
            pending["position"] = position
            let duration = (request["duration"] as? NSNumber)?.doubleValue ?? 0
            if duration > 0 || pending["duration"] == nil { pending["duration"] = duration }
            pending["created"] = Date().timeIntervalSince1970
            pending["returned"] = false
            do {
                let data = try JSONSerialization.data(withJSONObject: pending)
                try data.write(to: path, options: .atomic)
            } catch {
                snapshots.set(token, ["state": "error", "message": "Cannot save Infuse playback context."])
                return
            }
            for (key, status) in [("x-success", "success"), ("x-error", "error")] {
                var callback = URLComponents()
                callback.scheme = "dexhub-player"
                callback.host = status
                callback.queryItems = [URLQueryItem(name: "token", value: callbackToken)]
                query.append(URLQueryItem(name: key, value: callback.string))
            }
        }
        target.queryItems = query
        target.percentEncodedQuery = target.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = target.url else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            snapshots.set(token, success ? ["state": "external", "position": position] :
                ["state": "error", "message": "External app could not be opened. Check that it is installed."])
        }
    }
}

@MainActor
private final class EmbeddedSession {
    let token: String
    private let request: NSDictionary
    private let engine: AetherEngine
    private let surface: AetherPlayerView
    private weak var overlay: UIView?
    private let wasOpaque: Bool
    private let layerWasOpaque: Bool
    private let backgroundWas: UIColor?
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var stopped = false
    private var failure: String?
    private var bitmapViews: [String: UIImageView] = [:]
    private var subtitleDelay = 0.0
    private var lastAudio: [TrackInfo] = []
    private var lastSubtitles: [TrackInfo] = []
    private var audioRows: [[String: Any]] = []
    private var subtitleRows: [[String: Any]] = []
    private var trackRevision = 0
    private var retainedCues: [SubtitleCue] = []
    private var cueIndex = SubtitleWindowIndex()
    private var cueUpdates: AnyCancellable?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?

    init(request: NSDictionary, parent: UIView, overlay: UIView) throws {
        self.request = request
        token = request["token"] as? String ?? ""
        engine = try AetherEngine()
        // The system Now Playing card (Control Center, iPhone remote, Siri) follows
        // this session; it must be claimed before load() creates the native host.
        engine.ownsVideoNowPlayingSession = true
        surface = AetherPlayerView(frame: parent.bounds)
        self.overlay = overlay
        wasOpaque = overlay.isOpaque
        layerWasOpaque = overlay.layer.isOpaque
        backgroundWas = overlay.backgroundColor
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.isUserInteractionEnabled = false
        overlay.isOpaque = false
        overlay.layer.isOpaque = false
        overlay.backgroundColor = .clear
        parent.insertSubview(surface, belowSubview: overlay)
        engine.bind(view: surface)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        engine.setNativeSubtitleRendering(false)
        cueUpdates = engine.$subtitleCues.sink { [weak self] cues in
            guard let self else { return }
            retainedCues = cues
            cueIndex.update(cues, start: { $0.startTime }, end: { $0.endTime })
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Installed on the main run loop: avoid queued Tasks during a stall.
            MainActor.assumeIsolated { self?.publish() }
        }
        timer?.tolerance = 0.025
        loadTask = Task { [weak self] in
            guard let self, !stopped, !Task.isCancelled else { return }
            do {
                guard let raw = request["url"] as? String else { throw URLError(.badURL) }
                let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let media = String(parts[0])
                let url = media.hasPrefix("/") ? URL(fileURLWithPath: media) : URL(string: media)
                guard let url else { throw URLError(.badURL) }
                var headers: [String: String] = [:]
                if parts.count > 1 {
                    for pair in parts[1].split(separator: "&") {
                        let row = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                        if row.count == 2 {
                            let key = String(row[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(row[0])
                            let value = String(row[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(row[1])
                            headers[key] = value
                        }
                    }
                }
                let subtitles = (request["subtitles"] as? [String] ?? []).compactMap { raw -> ExternalSubtitleTrack? in
                    let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : URL(string: raw)
                    guard let url else { return nil }
                    return ExternalSubtitleTrack(url: url, language: "ar", httpHeaders: nil)
                }
                // Keep source probing and display matching intact. Mount the video before
                // adding sidecars, so a slow subtitle download cannot hold its first frame.
                let layouts: [SpatialSpeakerLayout] = [.l512, .l514, .l712, .l714, .l916]
                let layout = (request["truehdAtmosLayout"] as? NSNumber)?.intValue ?? 0
                let objectAudio: ObjectAudioRendering = (1...layouts.count).contains(layout) ? .apac(layouts[layout - 1]) : .off
                let options = LoadOptions(httpHeaders: headers, matchContentEnabled: true,
                    objectAudioRendering: objectAudio, confirmAtmos: true,
                    preferredSubtitleLanguages: ["ar", "ara"], externalSubtitles: [],
                    autoplay: true)
                let position = max(0, (request["position"] as? NSNumber)?.doubleValue ?? 0)
                stageNowPlaying()
                let startedAt = Date()
                try await engine.load(url: url, startPosition: position, options: options)
                guard !stopped, !Task.isCancelled else { return }
                NSLog("DexAetherBridge: video load completed in %.3f seconds", Date().timeIntervalSince(startedAt))
                registerRemoteCommands()
                engine.setNativeSubtitleRendering(false)
                if position == 0, let percent = request["percent"] as? NSNumber, percent.doubleValue > 0,
                   engine.duration.isFinite, engine.duration > 0 {
                    await engine.seek(to: engine.duration * min(100, percent.doubleValue) / 100)
                    guard !stopped, !Task.isCancelled else { return }
                }
                var preferredSidecar: Int?
                for subtitle in subtitles {
                    let track = engine.addExternalSubtitleTrack(subtitle)
                    if preferredSidecar == nil { preferredSidecar = track.id }
                }
                if let preferredSidecar { engine.selectSubtitleTrack(index: preferredSidecar) }
                engine.setNativeSubtitleRendering(false)
                publish()
            } catch {
                if !stopped { failure = error.localizedDescription; publish() }
            }
        }
    }

    /// Title, show or year, and poster for the system Now Playing card.
    private func stageNowPlaying() {
        let row = request["nowPlaying"] as? NSDictionary ?? [:]
        var info: [String: Any] = [MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let title = row["title"] as? String, !title.isEmpty { info[MPMediaItemPropertyTitle] = title }
        if let subtitle = row["subtitle"] as? String, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
        if let path = row["artworkPath"] as? String, let image = UIImage(contentsOfFile: path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        engine.setVideoNowPlayingInfo(info)
        guard info[MPMediaItemPropertyArtwork] == nil, let raw = row["artworkURL"] as? String,
              let url = URL(string: raw) else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), let self, !self.stopped, !Task.isCancelled else { return }
            var updated = info
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.engine.setVideoNowPlayingInfo(updated)
        }
    }

    /// Play, pause and skip from Control Center and the iPhone remote. Kodi learns
    /// the new pause state from the next snapshot.
    private func registerRemoteCommands() {
        guard commandTargets.isEmpty, let center = engine.videoNowPlayingSession?.remoteCommandCenter else { return }
        func add(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Bool) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] event in
                guard let self, !self.stopped else { return .commandFailed }
                return MainActor.assumeIsolated { action(event) } ? .success : .commandFailed
            }
            commandTargets.append((command, target))
        }
        add(center.playCommand) { [unowned self] _ in engine.play(); return true }
        add(center.pauseCommand) { [unowned self] _ in engine.pause(); return true }
        add(center.togglePlayPauseCommand) { [unowned self] _ in
            if case .playing = engine.state { engine.pause() } else { engine.play() }
            return true
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.skipForwardCommand) { [unowned self] _ in seek(by: 10); return true }
        add(center.skipBackwardCommand) { [unowned self] _ in seek(by: -10); return true }
        add(center.changePlaybackPositionCommand) { [unowned self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return false }
            command(["name": "seek", "value": event.positionTime])
            return true
        }
    }

    private func seek(by seconds: Double) {
        let now = engine.clock.currentTime
        guard now.isFinite else { return }
        command(["name": "seek", "value": now + seconds])
    }

    func command(_ request: NSDictionary) {
        let value = (request["value"] as? NSNumber)?.doubleValue ?? 0
        switch request["name"] as? String {
        case "rate":
            if value == 0 { engine.pause() } else { engine.play(); engine.setRate(Float(value)) }
        case "seek":
            seekTask?.cancel()
            seekTask = Task { [weak self] in
                guard let self, !stopped, !Task.isCancelled else { return }
                await engine.seek(to: max(0, value))
            }
        case "volume": engine.volume = Float(max(0, min(1, value)))
        case "audioDelay": engine.setAudioDelay(value)
        case "subtitleDelay": subtitleDelay = value
        case "audio": engine.selectAudioTrack(index: Int(value))
        case "subtitle":
            if value < 0 { engine.clearSubtitle() } else { engine.selectSubtitleTrack(index: Int(value)) }
            engine.setNativeSubtitleRendering(false)
        case "addSubtitle":
            if let raw = request["text"] as? String {
                let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : URL(string: raw)
                if let url {
                    let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: url, language: nil, httpHeaders: nil))
                    engine.selectSubtitleTrack(index: track.id)
                }
            }
        case "rect":
            if let parent = surface.superview {
                let x = (request["x"] as? NSNumber)?.doubleValue ?? 0
                let y = (request["y"] as? NSNumber)?.doubleValue ?? 0
                let width = (request["width"] as? NSNumber)?.doubleValue ?? 1
                let height = (request["height"] as? NSNumber)?.doubleValue ?? 1
                surface.frame = CGRect(x: x * parent.bounds.width, y: y * parent.bounds.height,
                    width: width * parent.bounds.width, height: height * parent.bounds.height)
            }
        default: break
        }
    }

    private func track(_ row: TrackInfo) -> [String: Any] {
        ["id": row.id, "name": row.name, "language": row.language ?? "", "codec": row.codec,
         "channels": row.channels, "samplerate": row.sampleRate, "bits": row.bitsPerSample,
         "external": row.isExternal]
    }

    private func publish() {
        guard !stopped else { return }
        var state = "loading"
        switch engine.state {
        case .playing: state = "playing"
        case .paused: state = "paused"
        case .ended: state = "ended"
        case .error(let message): state = "error"; failure = message
        case .seeking: state = "seeking"
        default: break
        }
        if failure != nil { state = "error" }
        let sourceTime = engine.clock.sourceTime
        let time = sourceTime + subtitleDelay
        var cues: [SubtitleCue] = []
        var text: [[String: Any]] = []
        for index in cueIndex.candidates(around: time) {
            let cue = retainedCues[index]
            guard cue.startTime <= time + 1 && cue.endTime > time - 1 else { continue }
            if time >= cue.startTime && time < cue.endTime { cues.append(cue) }
            if let value = cue.text { text.append(["text": value, "start": cue.startTime, "end": cue.endTime]) }
        }
        updateBitmaps(cues)
        if lastAudio != engine.audioTracks || lastSubtitles != engine.subtitleTracks {
            lastAudio = engine.audioTracks
            lastSubtitles = engine.subtitleTracks
            audioRows = lastAudio.map(track)
            subtitleRows = lastSubtitles.map(track)
            trackRevision += 1
        }
        snapshots.set(token, ["state": state, "message": failure ?? "",
            "position": engine.clock.currentTime.isFinite ? engine.clock.currentTime : 0,
            "sourceTime": sourceTime.isFinite ? sourceTime : 0,
            "duration": engine.duration.isFinite ? engine.duration : 0,
            "width": engine.sourceVideoWidth, "height": engine.sourceVideoHeight,
            "fps": engine.sourceVideoFrameRate ?? 0, "codec": engine.sourceVideoCodecName ?? "",
            "surfaceInWindow": surface.window != nil,
            "surfaceWidth": surface.bounds.width, "surfaceHeight": surface.bounds.height,
            "surfaceLayers": surface.layer.sublayers?.count ?? 0,
            "hdr": String(describing: engine.sourceVideoFormat),
            "audioId": engine.activeAudioTrackIndex ?? -1, "subtitleId": engine.activeSubtitleTrackIndex ?? -1,
            "trackRevision": trackRevision,
            "audio": audioRows, "subtitles": subtitleRows, "cues": text])
    }

    private func updateBitmaps(_ cues: [SubtitleCue]) {
        var visible = Set<String>()
        let videoSize = CGSize(width: CGFloat(max(1, Int(engine.sourceVideoWidth))), height: CGFloat(max(1, Int(engine.sourceVideoHeight))))
        let scale = min(surface.bounds.width / videoSize.width, surface.bounds.height / videoSize.height)
        let videoRect = CGRect(x: (surface.bounds.width - videoSize.width * scale) / 2,
            y: (surface.bounds.height - videoSize.height * scale) / 2,
            width: videoSize.width * scale, height: videoSize.height * scale)
        for cue in cues {
            guard case .image(let image) = cue.body else { continue }
            let key = "\(cue.id):\(cue.startTime)"
            visible.insert(key)
            let view = bitmapViews[key] ?? UIImageView(image: UIImage(cgImage: image.cgImage))
            if bitmapViews[key] == nil { surface.addSubview(view); bitmapViews[key] = view }
            let canvas = image.canvasSize.width > 0 && image.canvasSize.height > 0 ? image.canvasSize : videoSize
            let canvasScale = videoRect.width / canvas.width
            let originY = videoRect.midY - canvas.height * canvasScale / 2
            view.frame = CGRect(x: videoRect.minX + image.position.minX * canvas.width * canvasScale,
                y: originY + image.position.minY * canvas.height * canvasScale,
                width: image.position.width * canvas.width * canvasScale,
                height: image.position.height * canvas.height * canvasScale)
        }
        for key in Array(bitmapViews.keys) where !visible.contains(key) {
            bitmapViews.removeValue(forKey: key)?.removeFromSuperview()
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        cueUpdates?.cancel()
        cueUpdates = nil
        artworkTask?.cancel()
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets = []
        timer?.invalidate()
        loadTask?.cancel()
        seekTask?.cancel()
        engine.stop()
        surface.removeFromSuperview()
        overlay?.isOpaque = wasOpaque
        overlay?.layer.isOpaque = layerWasOpaque
        overlay?.backgroundColor = backgroundWas
        snapshots.set(token, ["state": "stopped"])
    }
}
