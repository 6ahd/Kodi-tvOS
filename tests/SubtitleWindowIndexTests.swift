struct Cue {
    let start: Double
    let end: Double
}

@main
struct SubtitleWindowIndexTests {
    static func main() {
        var index = SubtitleWindowIndex()
        func check(_ cues: [Cue], at time: Double) {
            index.update(cues, start: { $0.start }, end: { $0.end })
            let actual = index.candidates(around: time).filter {
                cues[$0].start <= time + 1 && cues[$0].end > time - 1
            }
            let expected = cues.indices.filter {
                cues[$0].start <= time + 1 && cues[$0].end > time - 1
            }
            precondition(actual == expected, "Subtitle window differs at \(time)")
        }
        check([], at: 0)
        let overlapping = [Cue(start: 0, end: 100), Cue(start: 1, end: 2),
                           Cue(start: 1, end: 4), Cue(start: 20, end: 22)]
        for time in [-2.0, -1, 0, 1, 3, 19, 20, 23, 100, 101, 0] {
            check(overlapping, at: time)
        }
        let many = (0..<50_000).map { Cue(start: Double($0 * 3), end: Double($0 * 3 + 2)) }
        index.update(many, start: { $0.start }, end: { $0.end })
        var visited = 0
        for tick in 0..<1_000 {
            let time = Double((tick * 137) % 150_000)
            let range = index.candidates(around: time)
            visited += range.count
            let actual = range.filter { many[$0].start <= time + 1 && many[$0].end > time - 1 }
            let expected = many.indices.filter { many[$0].start <= time + 1 && many[$0].end > time - 1 }
            precondition(actual == expected)
        }
        precondition(visited < 5_000)
        check([], at: 100)
        check([Cue(start: 98, end: 102)], at: 100)
        print("PASS: subtitle boundaries, overlaps, backward seeks and replacement; \(visited) candidates versus 50,000,000 full-scan comparisons")
    }
}
