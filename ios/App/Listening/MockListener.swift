// Scripted listener. Plays back a transcript word by word at its real timings,
// so live word colors, hesitations and mistakes all show without a network.
// The mic still runs, so the level meter moves while "listening".

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class MockListener: Listening {
    private(set) var status: ListenStatus = .idle
    private(set) var partialText = ""
    private(set) var liveTranscript: Transcript = .empty
    private(set) var errorMessage: String?

    /// The next transcript any MockListener will play. Set from the debug panel.
    static var injected: Transcript?

    static func inject(_ text: String) { injected = .synthetic(text) }
    static func inject(_ transcript: Transcript) { injected = transcript }

    @ObservationIgnored private var script: Transcript = .empty
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var startedMic = false

    func start() async {
        script = Self.injected ?? (try? API.fixture("page1-demo")) ?? .synthetic("The little elephant's name was Golu.")
        Self.injected = nil
        liveTranscript = .empty
        partialText = ""
        errorMessage = nil
        status = .connecting
        if !MicHub.shared.isRunning, await AudioSessionManager.shared.requestMic() {
            startedMic = (try? MicHub.shared.start()) != nil
        }
        status = .listening
        let words = script.words
        playback = Task { [weak self] in
            let t0 = Date()
            for (i, w) in words.enumerated() {
                let wait = w.end - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if Task.isCancelled { return }
                self?.reveal(Array(words.prefix(i + 1)))
            }
        }
    }

    func stop() async -> Transcript {
        playback?.cancel()
        playback = nil
        if startedMic { MicHub.shared.stop(); startedMic = false }
        status = .idle
        // Stopping early still returns the whole script, like a recognizer flushing its buffer.
        liveTranscript = script
        partialText = script.text
        return script
    }

    private func reveal(_ words: [TimedWord]) {
        let text = words.map(\.text).joined(separator: " ")
        liveTranscript = Transcript(text: text, words: words)
        partialText = text
    }
}
