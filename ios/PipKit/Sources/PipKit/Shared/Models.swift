// FROZEN shared models. One-to-one port of lib/types.ts with the same JSON keys,
// so server responses decode directly.

import Foundation

public enum Phase: String, Codable, Sendable, CaseIterable {
    case intro, probePre, read, pipReads, expression, probePost, report
}

public enum Emotion: String, Codable, Sendable, CaseIterable {
    case scared, excited, sad, whispering, shouting, happy, angry
}

public struct EmotionLine: Codable, Sendable, Equatable {
    public var text: String
    public var speaker: String?
    public var emotion: Emotion
    public init(text: String, speaker: String? = nil, emotion: Emotion) {
        self.text = text; self.speaker = speaker; self.emotion = emotion
    }
}

/// Fallback art for a page: an emoji scene on a soft background color ("#rrggbb").
public struct PageScene: Codable, Sendable, Equatable {
    public var emoji: String
    public var bg: String
    public init(emoji: String, bg: String) { self.emoji = emoji; self.bg = bg }
}

public struct BookPage: Codable, Sendable, Equatable, Identifiable {
    public var index: Int
    public var text: String
    public var scene: PageScene
    public var imageUrl: String?
    public var emotionLine: EmotionLine?
    public var id: Int { index }
    public init(index: Int, text: String, scene: PageScene, imageUrl: String? = nil, emotionLine: EmotionLine? = nil) {
        self.index = index; self.text = text; self.scene = scene; self.imageUrl = imageUrl; self.emotionLine = emotionLine
    }
}

public struct Book: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var author: String
    public var illustrator: String
    public var publisher: String
    public var license: String
    public var sourceUrl: String
    public var pages: [BookPage]
    public init(id: String, title: String, author: String, illustrator: String, publisher: String,
                license: String, sourceUrl: String, pages: [BookPage]) {
        self.id = id; self.title = title; self.author = author; self.illustrator = illustrator
        self.publisher = publisher; self.license = license; self.sourceUrl = sourceUrl; self.pages = pages
    }

    /// Used until the server (or the bundled book.json fixture) provides the demo book.
    public static let placeholder = Book(
        id: "playtime",
        title: "Playtime",
        author: "Sanjiv Jaiswal 'Sanjay'; translated by Manisha Chaudhry",
        illustrator: "Ajit Narayan",
        publisher: "Pratham Books StoryWeaver",
        license: "CC BY 4.0",
        sourceUrl: "https://storyweaver.org.in/stories/375-playtime",
        pages: [
            BookPage(index: 0,
                     text: "The little elephant's name was Golu. He was as round as a drum. The little rabbit was called Chhotu. He looked like a ball of cotton.",
                     scene: PageScene(emoji: "🐘 🐇", bg: "#e6ebff")),
            BookPage(index: 1,
                     text: "They played together. One day, Golu said, \u{201C}Let's play a new game today.\u{201D}",
                     scene: PageScene(emoji: "🐘 💬 🐇", bg: "#fff2c9"),
                     emotionLine: EmotionLine(text: "Let's play a new game today.", speaker: "Golu", emotion: .excited)),
        ]
    )
}

public struct TimedWord: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

public struct Transcript: Codable, Sendable, Equatable {
    public var text: String
    public var words: [TimedWord]
    public init(text: String, words: [TimedWord]) { self.text = text; self.words = words }
    public static let empty = Transcript(text: "", words: [])

    /// Evenly spaced synthetic timestamps for plain text (mock input, fallbacks).
    public static func synthetic(_ text: String, wordsPerSec: Double = 2.2) -> Transcript {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let words = parts.enumerated().map { i, w in
            TimedWord(text: w, start: Double(i) / wordsPerSec, end: (Double(i) + 0.8) / wordsPerSec)
        }
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), words: words)
    }
}

public enum WordStatus: String, Codable, Sendable {
    case correct, substitution, omission, selfCorrected
}

public struct AlignedWord: Codable, Sendable, Equatable {
    public var index: Int
    public var expected: String
    public var status: WordStatus
    public var said: String?
    public var start: Double?
    public var end: Double?
    public var hesitationBeforeSec: Double?
    public init(index: Int, expected: String, status: WordStatus, said: String? = nil,
                start: Double? = nil, end: Double? = nil, hesitationBeforeSec: Double? = nil) {
        self.index = index; self.expected = expected; self.status = status; self.said = said
        self.start = start; self.end = end; self.hesitationBeforeSec = hesitationBeforeSec
    }
}

public struct Insertion: Codable, Sendable, Equatable {
    public var afterIndex: Int
    public var said: String
    public init(afterIndex: Int, said: String) { self.afterIndex = afterIndex; self.said = said }
}

public struct AlignmentResult: Codable, Sendable, Equatable {
    public var words: [AlignedWord]
    public var insertions: [Insertion]
    public init(words: [AlignedWord], insertions: [Insertion]) { self.words = words; self.insertions = insertions }
}

public struct ReadingMetrics: Codable, Sendable, Equatable {
    public var wcpm: Double
    public var accuracyPct: Double
    public var wordsCorrect: Int
    public var wordsTotal: Int
    public var durationSec: Double
    public var hesitations: Int
    public var selfCorrections: Int
    public init(wcpm: Double, accuracyPct: Double, wordsCorrect: Int, wordsTotal: Int,
                durationSec: Double, hesitations: Int, selfCorrections: Int) {
        self.wcpm = wcpm; self.accuracyPct = accuracyPct; self.wordsCorrect = wordsCorrect; self.wordsTotal = wordsTotal
        self.durationSec = durationSec; self.hesitations = hesitations; self.selfCorrections = selfCorrections
    }
}

public struct PatternFinding: Codable, Sendable, Equatable {
    public var id: String
    public var kidLabel: String
    public var teacherLabel: String
    public var evidenceWords: [String]
    public var confidence: Double
    public init(id: String, kidLabel: String, teacherLabel: String, evidenceWords: [String], confidence: Double) {
        self.id = id; self.kidLabel = kidLabel; self.teacherLabel = teacherLabel
        self.evidenceWords = evidenceWords; self.confidence = confidence
    }
}

public struct DiagnoseResponse: Codable, Sendable, Equatable {
    public var patterns: [PatternFinding]
    public var kidMessage: String
    public init(patterns: [PatternFinding], kidMessage: String) { self.patterns = patterns; self.kidMessage = kidMessage }
}

public struct PipSentence: Codable, Sendable, Equatable {
    public var index: Int
    public var text: String
    public var spokenText: String
    public var wordStart: Int
    public var wordEnd: Int
    public init(index: Int, text: String, spokenText: String, wordStart: Int, wordEnd: Int) {
        self.index = index; self.text = text; self.spokenText = spokenText; self.wordStart = wordStart; self.wordEnd = wordEnd
    }
}

public struct PlantedMistake: Codable, Sendable, Equatable {
    public var wordIndex: Int
    public var sentenceIndex: Int
    public var correct: String
    public var misread: String
    public var speakAs: String
    public var patternId: String
    public var reaction: String
    public init(wordIndex: Int, sentenceIndex: Int, correct: String, misread: String,
                speakAs: String, patternId: String, reaction: String) {
        self.wordIndex = wordIndex; self.sentenceIndex = sentenceIndex; self.correct = correct; self.misread = misread
        self.speakAs = speakAs; self.patternId = patternId; self.reaction = reaction
    }
}

public struct PipPlan: Codable, Sendable, Equatable {
    public var pageIndex: Int
    public var sentences: [PipSentence]
    public var mistakes: [PlantedMistake]
    public init(pageIndex: Int, sentences: [PipSentence], mistakes: [PlantedMistake]) {
        self.pageIndex = pageIndex; self.sentences = sentences; self.mistakes = mistakes
    }
}

public enum CatchVia: String, Codable, Sendable { case voice, tap, missed }

public struct CatchResult: Codable, Sendable, Equatable {
    public var wordIndex: Int
    public var caught: Bool
    public var via: CatchVia
    public init(wordIndex: Int, caught: Bool, via: CatchVia) { self.wordIndex = wordIndex; self.caught = caught; self.via = via }
}

public struct ProsodyStats: Codable, Sendable, Equatable {
    public var pitchRangeSemitones: Double
    public var pitchSdSemitones: Double
    public var loudnessSdDb: Double
    public var wordsPerSec: Double
    public var voicedFrames: Int
    public init(pitchRangeSemitones: Double, pitchSdSemitones: Double, loudnessSdDb: Double,
                wordsPerSec: Double, voicedFrames: Int) {
        self.pitchRangeSemitones = pitchRangeSemitones; self.pitchSdSemitones = pitchSdSemitones
        self.loudnessSdDb = loudnessSdDb; self.wordsPerSec = wordsPerSec; self.voicedFrames = voicedFrames
    }
    public static let zero = ProsodyStats(pitchRangeSemitones: 0, pitchSdSemitones: 0, loudnessSdDb: 0, wordsPerSec: 0, voicedFrames: 0)
}

public struct ProsodyFrame: Codable, Sendable, Equatable {
    public var t: Double
    public var semitones: Double?
    public var rms: Double
    public init(t: Double, semitones: Double?, rms: Double) { self.t = t; self.semitones = semitones; self.rms = rms }
}

public struct ExpressionResult: Codable, Sendable, Equatable {
    public var baseline: ProsodyStats?
    public var attempt: ProsodyStats
    public var score: Double
    public var passed: Bool
    public var attempts: Int
    public var tags: [String]
    public init(baseline: ProsodyStats?, attempt: ProsodyStats, score: Double, passed: Bool, attempts: Int, tags: [String]) {
        self.baseline = baseline; self.attempt = attempt; self.score = score
        self.passed = passed; self.attempts = attempts; self.tags = tags
    }
}

public struct ProbeItem: Codable, Sendable, Equatable {
    public var word: String
    public var patternId: String
    public init(word: String, patternId: String) { self.word = word; self.patternId = patternId }
}

public struct ProbeItemResult: Codable, Sendable, Equatable {
    public var word: String
    public var patternId: String
    public var correct: Bool
    public var said: String?
    public init(word: String, patternId: String, correct: Bool, said: String? = nil) {
        self.word = word; self.patternId = patternId; self.correct = correct; self.said = said
    }
}

public struct ProbeResult: Codable, Sendable, Equatable {
    public var items: [ProbeItemResult]
    public var correctCount: Int
    public init(items: [ProbeItemResult], correctCount: Int) { self.items = items; self.correctCount = correctCount }
}

public enum TtsMode: String, Codable, Sendable { case flat, expressive }

public struct TtsRequest: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var mode: TtsMode
    public var withTimestamps: Bool?
    public init(text: String, mode: TtsMode, withTimestamps: Bool? = nil) {
        self.text = text; self.mode = mode; self.withTimestamps = withTimestamps
    }
    public static func flat(_ text: String) -> TtsRequest { TtsRequest(text: text, mode: .flat, withTimestamps: true) }
    public static func expressive(_ text: String) -> TtsRequest { TtsRequest(text: text, mode: .expressive) }
}

public struct TtsResponse: Codable, Sendable, Equatable {
    public var audioUrl: String
    public var words: [TimedWord]?
    public init(audioUrl: String, words: [TimedWord]? = nil) { self.audioUrl = audioUrl; self.words = words }
}

public struct PracticeBook: Codable, Sendable, Equatable {
    public var title: String
    public var pattern: PatternFinding
    public var sentences: [String]
    public init(title: String, pattern: PatternFinding, sentences: [String]) {
        self.title = title; self.pattern = pattern; self.sentences = sentences
    }
}

/// Response of POST /api/expression-tags.
public struct ExpressionTags: Codable, Sendable, Equatable {
    public var taggedText: String
    public var tags: [String]
    public init(taggedText: String, tags: [String]) { self.taggedText = taggedText; self.tags = tags }
}

/// What the Read phase stores (web: session.read).
public struct ReadResult: Codable, Sendable, Equatable {
    public var transcript: Transcript
    public var alignment: AlignmentResult
    public var metrics: ReadingMetrics
    public init(transcript: Transcript, alignment: AlignmentResult, metrics: ReadingMetrics) {
        self.transcript = transcript; self.alignment = alignment; self.metrics = metrics
    }
}
