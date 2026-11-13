// FROZEN signature. Live color for each page word while the child reads, so the
// page lights up as they go: green when a word is read right, yellow after a
// long pause, coral when it came out differently, and a soft glow on the word
// they are about to read. Built on alignWords, so it improves when the aligner does.

import Foundation

public enum WordMark: String, Sendable, Equatable, CaseIterable {
    /// Not reached yet.
    case pending
    /// The next word to read.
    case current
    case correct
    /// Read right, after a long pause.
    case hesitant
    /// Skipped or read as a different word.
    case missed
    /// Read differently, then fixed by the reader.
    case fixed
}

/// One mark per page word (tokenizeDisplay indexes). Words after the last word
/// the reader has said stay pending, so a partial transcript never marks the
/// rest of the page as missed. Pass final: true once reading is done to mark
/// unread words as missed.
public func liveMarks(expectedText: String, transcript: Transcript,
                      hesitationSec: Double = 0.8, final: Bool = false) -> [WordMark] {
    let count = tokenizeDisplay(expectedText).count
    guard !transcript.words.isEmpty else {
        return (0..<count).map { $0 == 0 && !final ? .current : (final ? .missed : .pending) }
    }
    let aligned = alignWords(expectedText: expectedText, transcript: transcript).words
    let frontier = aligned.lastIndex { $0.status != .omission } ?? -1
    return aligned.enumerated().map { i, w -> WordMark in
        if i > frontier {
            if final { return .missed }
            return i == frontier + 1 ? .current : .pending
        }
        switch w.status {
        case .omission, .substitution: return .missed
        case .selfCorrected: return .fixed
        case .correct: return (w.hesitationBeforeSec ?? 0) >= hesitationSec ? .hesitant : .correct
        }
    }
}

/// Final marks from a finished alignment (for the report and the replay).
public func marks(for alignment: AlignmentResult, hesitationSec: Double = 0.8) -> [WordMark] {
    alignment.words.map { w in
        switch w.status {
        case .omission, .substitution: return .missed
        case .selfCorrected: return .fixed
        case .correct: return (w.hesitationBeforeSec ?? 0) >= hesitationSec ? .hesitant : .correct
        }
    }
}
