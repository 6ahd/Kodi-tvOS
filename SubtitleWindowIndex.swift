struct SubtitleWindowIndex {
    private var starts: [Double] = []
    private var latestEnds: [Double] = []

    mutating func update<Cue>(_ cues: [Cue], start: (Cue) -> Double, end: (Cue) -> Double) {
        starts = cues.map(start)
        latestEnds.removeAll(keepingCapacity: true)
        latestEnds.reserveCapacity(cues.count)
        var latest = -Double.infinity
        for cue in cues {
            latest = max(latest, end(cue))
            latestEnds.append(latest)
        }
    }

    // Aether retains cues in start order. Prefix end times retain overlapping cues.
    func candidates(around time: Double) -> Range<Int> {
        guard time.isFinite else { return 0..<0 }
        var lower = 0, upper = starts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if starts[middle] <= time + 1 { lower = middle + 1 }
            else { upper = middle }
        }
        let last = lower
        lower = 0
        upper = last
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if latestEnds[middle] <= time - 1 { lower = middle + 1 }
            else { upper = middle }
        }
        return lower..<last
    }
}
