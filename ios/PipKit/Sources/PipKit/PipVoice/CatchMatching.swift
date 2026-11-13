import Foundation

/// Did the child catch Pip's mistake? Plain string matching, no model.
/// Port of lib/pip/catch.ts; relies on the shared TextHelpers port
/// (tokenize, normalizeToken, fuzzyEqual) so web and iOS agree on words.
public enum CatchMatching {
    /// Every normalized word the child said, from the timed words or the text.
    static func saidTokens(_ transcript: Transcript?) -> [String] {
        guard let transcript else { return [] }
        let fromWords = transcript.words.flatMap { tokenize($0.text) }
        let fromText = tokenize(transcript.text)
        return fromWords.count >= fromText.count ? fromWords : fromText
    }

    static let objectionWords: Set<String> = [
        "no", "nope", "nah", "wrong", "not", "incorrect", "oops", "mistake", "uh-uh", "nuh-uh", "wait", "again",
    ]
    static let objectionPhrases = [
        "\\bthat'?s not right\\b", "\\btry again\\b", "\\byou got it wrong\\b", "\\bmixed (it|one) up\\b",
    ]
}

/// True when the child said the correct word anywhere ("thought", "no, it says
/// thought"). Saying Pip's misreading back does not count.
public func detectCatch(transcript: Transcript?, mistake: PlantedMistake) -> Bool {
    let misread = normalizeToken(mistake.misread)
    return CatchMatching.saidTokens(transcript).contains { $0 != misread && fuzzyEqual($0, mistake.correct) }
}

/// True for "no", "that's wrong", "nope" said without the right word.
public func isBareObjection(transcript: Transcript?, mistake: PlantedMistake? = nil) -> Bool {
    let tokens = CatchMatching.saidTokens(transcript)
    if tokens.isEmpty { return false }
    if let mistake, detectCatch(transcript: transcript, mistake: mistake) { return false }
    if tokens.contains(where: { CatchMatching.objectionWords.contains($0) }) { return true }
    let text = tokens.joined(separator: " ")
    return CatchMatching.objectionPhrases.contains { text.range(of: $0, options: .regularExpression) != nil }
}
