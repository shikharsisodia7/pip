// Turns the Scribe event stream into one Transcript, with every time in seconds
// since the listener started.
//
// Committed segments carry recognizer word times, measured from the first audio
// sample of the session; `audioOffset` shifts them onto the listener's clock.
// Words still in a partial have no times yet, so they are stamped as they
// arrive. A partial adds a burst of words at once, so the new words are spread
// back from the arrival time at a natural reading pace instead of piling onto
// one instant. That keeps the gaps between words honest: a real pause still
// shows as a gap, but the rhythm of the network does not.

import Foundation

public struct ScribeTranscriptBuilder: Sendable {
    /// A segment whose text has settled, still shown with its arrival stamps.
    public struct Settling: Sendable, Equatable {
        public var text: String
        public var words: [TimedWord]
    }

    /// Seconds from the listener's start to the first audio sample sent.
    public var audioOffset: Double = 0
    /// Roughly how long a spoken word takes to show up in a partial (measured
    /// median about 0.3 s on scribe_v3_live). Arrival stamps are moved back by this.
    public var arrivalLag: Double = 0.3
    /// Longest slot given to one arriving word when spreading a burst.
    public var wordStep: Double = 0.3

    /// Settled words with recognizer times, already offset.
    public private(set) var committedWords: [TimedWord] = []
    /// Settled text of each segment, in order.
    public private(set) var committedTexts: [String] = []
    /// A segment whose text has settled but whose timestamps have not arrived.
    public private(set) var awaitingTimestamps: Settling?
    /// Latest partial words, stamped on arrival.
    public private(set) var partialWords: [TimedWord] = []
    public private(set) var partialText = ""
    /// How many timestamped segments have arrived. Every commit gets one, even
    /// a commit over silence, so this is what a final commit waits on.
    public private(set) var timestampedSegments = 0
    /// How many settled-text messages have arrived. Each commit sends one text
    /// and one timestamps message; usually text first, but not always.
    private var settledTexts = 0

    public init(audioOffset: Double = 0) { self.audioOffset = audioOffset }

    /// True while some heard speech has no recognizer timestamps yet.
    public var hasUntimedSpeech: Bool { awaitingTimestamps != nil || !partialWords.isEmpty }

    /// Everything heard so far as plain text, across segments.
    public var liveText: String {
        (committedTexts + [awaitingTimestamps?.text ?? "", partialText])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Applies one event that arrived `now` seconds after the listener started.
    public mutating func apply(_ event: ScribeEvent, at now: Double) {
        switch event {
        case .partial(let text):
            partialText = text
            partialWords = restamp(tokens(text), arrival: now)
        case .committedText(let text):
            settledTexts += 1
            // Its timestamps came first and already settled this segment.
            if settledTexts <= timestampedSegments { break }
            // Keep the partial's stamps on screen until the real times arrive.
            awaitingTimestamps = Settling(text: text, words: partialWords)
            partialWords = []
            partialText = ""
        case .committed(let text, let words):
            timestampedSegments += 1
            // Text first (the usual order): the segment is waiting. Otherwise the
            // open partial is this segment.
            let segment = timestampedSegments <= settledTexts
                ? awaitingTimestamps ?? Settling(text: "", words: [])
                : Settling(text: partialText, words: partialWords)
            let settled = text.isEmpty ? segment.text : text
            if !words.isEmpty {
                committedWords += words.map {
                    TimedWord(text: $0.text, start: $0.start + audioOffset, end: $0.end + audioOffset)
                }
            } else {
                committedWords += Self.evenlySpaced(tokens(settled), over: segment.words)
            }
            let trimmed = settled.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { committedTexts.append(trimmed) }
            if timestampedSegments <= settledTexts {
                awaitingTimestamps = nil
            } else {
                partialWords = []
                partialText = ""
            }
        case .sessionStarted, .warning, .error, .ignored:
            break
        }
    }

    /// Everything heard so far: settled words, then words still being recognized.
    /// A trailing word fragment ("ele-") is left out until it resolves, so it
    /// never flashes as a misreading.
    public var live: Transcript {
        var words = committedWords + (awaitingTimestamps?.words ?? []) + partialWords
        if let last = partialWords.last, last.text.hasSuffix("-"), last.text.count > 1 {
            words.removeLast()
        }
        return Transcript(text: words.map(\.text).joined(separator: " "), words: words)
    }

    /// The finished transcript. Speech whose timestamps never arrived falls back
    /// to its words evenly spaced across the time it was heard.
    public var final: Transcript {
        var words = committedWords
        var texts = committedTexts
        if let pending = awaitingTimestamps {
            words += Self.evenlySpaced(tokens(pending.text), over: pending.words)
            if !pending.text.isEmpty { texts.append(pending.text) }
        }
        if !partialWords.isEmpty {
            let spoken = partialWords.map { w in
                w.text.hasSuffix("-") && w.text.count > 1 ? String(w.text.dropLast()) : w.text
            }
            words += Self.evenlySpaced(spoken, over: partialWords)
            texts.append(partialText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Transcript(text: texts.filter { !$0.isEmpty }.joined(separator: " "), words: words)
    }

    // MARK: Helpers

    private func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Keeps the stamp of every word slot the previous partial already had (a
    /// revised word keeps its time) and spreads the new words back from `arrival`.
    private func restamp(_ texts: [String], arrival: Double) -> [TimedWord] {
        let kept = min(texts.count, partialWords.count)
        var out = (0..<kept).map { TimedWord(text: texts[$0], start: partialWords[$0].start, end: partialWords[$0].end) }
        let fresh = texts.count - kept
        guard fresh > 0 else { return out }
        let floor = out.last?.end ?? awaitingTimestamps?.words.last?.end ?? committedWords.last?.end ?? audioOffset
        let t = max(floor, arrival - arrivalLag)
        let step = min(wordStep, (t - floor) / Double(fresh))
        for k in 0..<fresh {
            let start = max(floor, t - Double(fresh - k) * step)
            out.append(TimedWord(text: texts[kept + k], start: start, end: start + step * 0.8))
        }
        return out
    }

    /// `texts` laid out evenly from the first stamp's start to the last stamp's end.
    static func evenlySpaced(_ texts: [String], over stamps: [TimedWord]) -> [TimedWord] {
        guard !texts.isEmpty else { return [] }
        let from = stamps.first?.start ?? 0
        let to = max(stamps.last?.end ?? from, from + 0.3 * Double(texts.count))
        let slot = (to - from) / Double(texts.count)
        return texts.enumerated().map { i, w in
            let start = from + Double(i) * slot
            return TimedWord(text: w, start: start, end: start + slot * 0.8)
        }
    }
}
