// One spoken comprehension question per page. Fully offline: questions for the
// demo book are hand written, other books get a simple question built from the
// page text, and answers are judged with plain keyword matching.

import Foundation

public struct StoryQuestion: Sendable, Equatable {
    public var question: String
    /// Each inner array is a set of keywords that together make a right answer; any one set is enough.
    public var acceptedAnswers: [[String]]
    public var hint: String
    /// Pip's warm line that states the answer.
    public var answerLine: String
    /// Open questions only: content words from the page. An answer of three or more
    /// words that shares one of these counts as right. Empty for authored questions.
    public var contentWords: [String]

    public init(question: String, acceptedAnswers: [[String]], hint: String, answerLine: String, contentWords: [String] = []) {
        self.question = question; self.acceptedAnswers = acceptedAnswers
        self.hint = hint; self.answerLine = answerLine; self.contentWords = contentWords
    }
}

public enum AnswerVerdict: String, Sendable, Equatable {
    case correct, close, tryAgain, noAnswer
}

/// Hand written questions for "Playtime" (Pratham Books StoryWeaver), one per page.
/// Every answer is stated in that page's text.
public let playtimeQuestions: [StoryQuestion] = [
    StoryQuestion(question: "Who was as round as a drum?",
                  acceptedAnswers: [["golu"], ["elephant"]],
                  hint: "Think about the big animal on this page.",
                  answerLine: "It was Golu the elephant!"),
    StoryQuestion(question: "What did Golu want to play today?",
                  acceptedAnswers: [["new", "game"], ["game"]],
                  hint: "Golu said, let's play a new...",
                  answerLine: "Golu wanted to play a new game!"),
    StoryQuestion(question: "Who took a mighty leap?",
                  acceptedAnswers: [["chhotu"], ["rabbit"], ["bunny"]],
                  hint: "It was the little one who looked like a ball of cotton.",
                  answerLine: "It was Chhotu the rabbit!"),
    StoryQuestion(question: "Where did Chhotu land?",
                  acceptedAnswers: [["back"], ["golus"], ["golu"]],
                  hint: "He landed on top of his big friend.",
                  answerLine: "Chhotu landed on Golu's back!"),
    StoryQuestion(question: "What came down on Golu's head?",
                  acceptedAnswers: [["coconuts"], ["coconut"]],
                  hint: "They fell from the tree. Thud, thud, thud!",
                  answerLine: "A shower of coconuts came down on Golu's head!"),
    StoryQuestion(question: "How did Golu feel when he ran away?",
                  acceptedAnswers: [["scared"], ["afraid"], ["frightened"], ["scary"]],
                  hint: "He ran away on his fat legs. How would you feel?",
                  answerLine: "Golu was scared, so he ran away!"),
]

private let fillerWords: Set<String> = [
    "um", "umm", "uh", "uhh", "hmm", "er", "erm", "ah", "eh", "i", "don't", "dont", "know", "idk", "dunno", "not", "sure",
]

private let stopWords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "was", "is", "are", "were", "be",
    "he", "she", "it", "they", "we", "you", "i", "me", "him", "her", "them", "his", "its", "their", "my", "your",
    "this", "that", "then", "there", "so", "said", "had", "has", "have", "do", "did", "one", "up", "down", "out",
    "like", "as", "very", "just", "yes", "no", "not", "all", "can", "will",
]

/// The question for a page. Demo book pages get the authored question; any other
/// book (or a demo page whose text no longer matches) gets a generic one.
public func storyQuestion(bookId: String, pageIndex: Int, pageText: String) -> StoryQuestion {
    if bookId.lowercased() == "playtime", playtimeQuestions.indices.contains(pageIndex) {
        let q = playtimeQuestions[pageIndex]
        let pageWords = tokenize(pageText)
        let firstSet = q.acceptedAnswers.first ?? []
        if firstSet.allSatisfy({ k in pageWords.contains { fuzzyEqual($0, k) } }) { return q }
    }
    return genericQuestion(pageText: pageText)
}

func genericQuestion(pageText: String) -> StoryQuestion {
    let tokens = tokenizeDisplay(pageText)
    for (i, t) in tokens.enumerated() where i > 0 {
        let prev = tokens[i - 1].display
        let sentenceStart = prev.range(of: "[.!?][\"'\u{201D}\u{2019})]*$", options: .regularExpression) != nil
        let letters = t.display.drop { !$0.isLetter }
        guard !sentenceStart, let first = letters.first, first.isUppercase, t.norm != "i" else { continue }
        var name = t.norm
        if name.hasSuffix("'s") { name.removeLast(2) }
        guard name.count >= 2, !stopWords.contains(name) else { continue }
        let display = name.prefix(1).uppercased() + name.dropFirst()
        return StoryQuestion(question: "Who was on this page?",
                             acceptedAnswers: [[name]],
                             hint: "Look for a name on the page.",
                             answerLine: "It was \(display)!")
    }
    let content = Array(Set(tokens.map(\.norm).filter { $0.count >= 3 && !stopWords.contains($0) })).sorted()
    return StoryQuestion(question: "What happened on this page?",
                         acceptedAnswers: [],
                         hint: "Tell Pip one thing that happened.",
                         answerLine: "Thank you for telling me about this page!",
                         contentWords: content)
}

/// Judges a spoken answer. Plain matching, no model.
public func judgeAnswer(_ transcript: String, for q: StoryQuestion) -> AnswerVerdict {
    let tokens = tokenize(transcript)
    let meaningful = tokens.filter { !fillerWords.contains($0) }
    if meaningful.isEmpty { return .noAnswer }
    let said = { (k: String) in tokens.contains { fuzzyEqual($0, k) } }

    if q.acceptedAnswers.isEmpty, !q.contentWords.isEmpty {
        let shares = q.contentWords.contains(where: said)
        if shares && meaningful.count >= 3 { return .correct }
        return shares ? .close : .tryAgain
    }
    if q.acceptedAnswers.contains(where: { set in !set.isEmpty && set.allSatisfy(said) }) { return .correct }
    if q.acceptedAnswers.contains(where: { set in set.contains(where: said) }) { return .close }
    return .tryAgain
}
