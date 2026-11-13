import Foundation

/// Pip's fixed lines (port of lib/pip/lines.ts). They are spoken in his natural,
/// expressive voice; only his read-backs of the story are flat.
public enum PipLine: String, CaseIterable, Sendable {
    case didIGetItRight, howShouldItSound, showMeAgain, likeThis
    case celebrate1, celebrate2, whichWord, mixedOneUp, keepPracticing, hello

    /// Text sent to TTS, including eleven_v3 audio tags.
    public var tagged: String {
        switch self {
        case .didIGetItRight: return "[curious] Did I get that right?"
        case .howShouldItSound: return "[thoughtful] Hmm, I don't think I said that right. How should it sound?"
        case .showMeAgain: return "[curious] Hmm, I still don't get how they feel. Can you show me again?"
        case .likeThis: return "[excited] Ohh! Like this?"
        case .celebrate1: return "[excited] Yay! You're a great teacher!"
        case .celebrate2: return "[happy] Hooray! Thank you for helping me!"
        case .whichWord: return "[curious] Which word did I get wrong?"
        case .mixedOneUp: return "[thoughtful] Hmm, I think I mixed one up. Let me fix it."
        case .keepPracticing: return "[happy] I'll keep practicing that one!"
        case .hello: return "[happy] Hi! I'm Pip. Will you help me learn to read?"
        }
    }

    /// The line without audio tags, for speech bubbles.
    public var text: String { PipVoiceText.stripAudioTags(tagged) }
}

public enum PipVoiceText {
    /// Removes [tag] markers and collapses whitespace.
    public static func stripAudioTags(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        return noTags.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Evenly spaced fake word timings, used when audio is unavailable.
    public static func evenTimings(for text: String, secondsPerWord: Double = 0.42) -> [(start: Double, end: Double)] {
        let words = stripAudioTags(text).split(whereSeparator: { $0.isWhitespace })
        return words.indices.map { i in
            let start = Double(i) * secondsPerWord
            return (start, start + secondsPerWord * 0.8)
        }
    }

    /// Index of the word that should be lit at time `t`, given word start times.
    public static func wordIndex(at t: Double, starts: [Double]) -> Int? {
        var lit: Int? = nil
        for (i, s) in starts.enumerated() where t >= s { lit = i }
        return lit
    }
}
