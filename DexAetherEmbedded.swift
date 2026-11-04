import Foundation
import Combine
import UIKit
import AVFoundation
import AVKit
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

    // v21.43: Picture in Picture. Kodi's DexHub.PictureInPicture builtin calls this;
    // the scene delegate asks pictureInPictureState before it lets Kodi sleep.
    @objc(togglePictureInPicture)
    public static func togglePictureInPicture() -> NSNumber {
        NSNumber(value: session?.togglePictureInPicture() ?? false)
    }

    @objc(pictureInPictureState)
    public static func pictureInPictureState() -> NSNumber {
        NSNumber(value: session?.pictureInPictureActive ?? false)
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
    private var lastChapters: [ChapterInfo] = []
    private var chapterRows: [[String: Any]] = []
    private var pip: AVPictureInPictureController?
    private var pipDelegate: PictureInPictureDelegate?
    private var pipWantedUntil: Date?
    private var pipRestores = 0
    private(set) var pictureInPictureActive = false

    init(request: NSDictionary, parent: UIView, overlay: UIView) throws {
        self.request = request
        token = request["token"] as? String ?? ""
        engine = try AetherEngine()
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
                let startedAt = Date()
                try await engine.load(url: url, startPosition: position, options: options)
                guard !stopped, !Task.isCancelled else { return }
                NSLog("DexAetherBridge: video load completed in %.3f seconds", Date().timeIntervalSince(startedAt))
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
        if lastAudio != engine.audioTracks || lastSubtitles != engine.subtitleTracks ||
            lastChapters != engine.mediaChapters {
            lastAudio = engine.audioTracks
            lastSubtitles = engine.subtitleTracks
            lastChapters = engine.mediaChapters
            audioRows = lastAudio.map(track)
            subtitleRows = lastSubtitles.map(track)
            // v21.43: container chapters (MKV/MP4) for Kodi's chapter list, seek bar
            // marks, chapter skip and the credits panel. Same axis as seek(to:).
            chapterRows = lastChapters.filter { $0.startSeconds.isFinite }.map {
                ["name": $0.name, "start": max(0, $0.startSeconds)]
            }
            trackRevision += 1
        }
        preparePictureInPicture()
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
            "audio": audioRows, "subtitles": subtitleRows, "chapters": chapterRows, "cues": text,
            "pip": pictureInPictureActive, "pipPossible": pip?.isPictureInPicturePossible ?? false,
            "pipRestore": pipRestores])
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

    // MARK: Picture in Picture (v21.43)
    // tvOS PiP needs an AVPlayerLayer: only Aether's native path has one. The software
    // path cannot float on tvOS (AVKit ignores sample-buffer sources, FB9751461).
    private func preparePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard let layer = engine.nativePlayerLayer else {
            if pip != nil && !pictureInPictureActive { pip = nil }
            return
        }
        if pip == nil || pip?.playerLayer !== layer {
            let delegate = PictureInPictureDelegate(session: self)
            let controller = AVPictureInPictureController(playerLayer: layer)
            controller?.delegate = delegate
            pip = controller
            pipDelegate = delegate
        }
        // A start asked for before AVKit called the window possible.
        if let until = pipWantedUntil, let pip {
            if pip.isPictureInPicturePossible {
                pipWantedUntil = nil
                pip.startPictureInPicture()
            } else if Date() > until {
                pipWantedUntil = nil
                NSLog("DexAetherBridge: Picture in Picture did not become possible")
            }
        }
    }

    /// Returns whether PiP is (or is about to be) shown after the toggle.
    func togglePictureInPicture() -> Bool {
        guard !stopped else { return false }
        if let pip, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
            return false
        }
        preparePictureInPicture()
        guard let pip else {
            NSLog("DexAetherBridge: Picture in Picture needs Aether's native path")
            return false
        }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            pipWantedUntil = Date().addingTimeInterval(3)
        }
        return true
    }

    fileprivate func pictureInPictureChanged(_ active: Bool) {
        pictureInPictureActive = active
        // Set before the app leaves the foreground: Aether reads it for the
        // background teardown decision and the in-place next-episode handover.
        engine.pictureInPictureActive = active
        if !active {
            NotificationCenter.default.post(name: Notification.Name("DexAetherPictureInPictureDidStop"), object: nil)
        }
        // The 10 Hz timer publishes it; no publish() here, AVKit may call in from one.
    }

    fileprivate func pictureInPictureRestore() {
        pipRestores += 1
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        pipWantedUntil = nil
        if let pip, pip.isPictureInPictureActive { pip.stopPictureInPicture() }
        if pictureInPictureActive {
            pictureInPictureActive = false
            engine.pictureInPictureActive = false
            NotificationCenter.default.post(name: Notification.Name("DexAetherPictureInPictureDidStop"), object: nil)
        }
        pip?.delegate = nil
        pip = nil
        pipDelegate = nil
        cueUpdates?.cancel()
        cueUpdates = nil
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

private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private weak var session: EmbeddedSession?
    init(session: EmbeddedSession) { self.session = session }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { session?.pictureInPictureChanged(true) }
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { session?.pictureInPictureChanged(false) }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        NSLog("DexAetherBridge: Picture in Picture failed: %@", error.localizedDescription)
        MainActor.assumeIsolated { session?.pictureInPictureChanged(false) }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        // Kodi brings its full screen video window back when it reads pipRestore.
        MainActor.assumeIsolated { session?.pictureInPictureRestore() }
        completion(true)
    }
}
