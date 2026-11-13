// STUB, replaced by the real player. Keep the API.
// Speaks Pip's lines. In mock mode there is no audio: words advance on a timer
// so karaoke and pacing still work.

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class PipPlayer {
    static let shared = PipPlayer()
    private(set) var isSpeaking = false

    /// Stops MicHub first, always: the mic never runs while Pip talks.
    func speak(_ request: TtsRequest, onWord: ((Int) -> Void)?) async {
        MicHub.shared.stop()
        isSpeaking = true
        defer { isSpeaking = false }
        let words = (try? await API.current.tts(request))?.words ?? Transcript.synthetic(request.text, wordsPerSec: 2.6).words
        let t0 = Date()
        for (i, w) in words.enumerated() {
            let wait = w.start - Date().timeIntervalSince(t0)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            onWord?(i)
        }
        if let last = words.last {
            let wait = last.end - Date().timeIntervalSince(t0)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
    }

    func prefetch(_ requests: [TtsRequest]) async {}
}
