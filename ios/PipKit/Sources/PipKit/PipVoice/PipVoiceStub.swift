// STUB, deleted when the catch detector port lands. Keep the signature.

import Foundation

/// Did the child say the correct word (or "no" / "stop") after Pip's mistake?
public func detectCatch(transcript: String, mistake: PlantedMistake) -> Bool {
    let words = tokenize(transcript)
    return words.contains { fuzzyEqual($0, mistake.correct) } || words.contains("no") || words.contains("stop")
}
