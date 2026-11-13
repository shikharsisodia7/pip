// Records how expressive the reader's voice is (pitch movement and loudness
// variation) while they read. Audio comes only from MicHub; this class never
// opens its own input or touches the audio session.

import Foundation
import PipKit

@MainActor
final class ProsodyRecorder {
    /// Live frames for the pitch contour, delivered on the main actor.
    var onFrame: ((ProsodyFrame) -> Void)?

    private let analyzer = ProsodyAnalyzer()
    private let listenerId = "prosody-\(UUID().uuidString)"
    private var attached = false
    private var startedHub = false

    /// Attaches to MicHub; starts MicHub if it is not running.
    func start() {
        guard !attached else { return }
        analyzer.reset()
        let analyzer = self.analyzer
        // Runs on the audio thread. The analyzer is thread safe; frames hop to
        // the main actor for the UI.
        MicHub.shared.addListener(listenerId) { [weak self] samples, sampleRate in
            let frames = analyzer.push(samples: samples, sampleRate: sampleRate)
            guard !frames.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.attached, let onFrame = self.onFrame else { return }
                for frame in frames { onFrame(frame) }
            }
        }
        attached = true
        if !MicHub.shared.isRunning {
            do {
                try MicHub.shared.start()
                startedHub = true
            } catch {
                MicHub.shared.removeListener(listenerId)
                attached = false
            }
        }
    }

    /// Detaches; stops MicHub only if it started it.
    func stop() -> ProsodyStats {
        guard attached else { return .zero }
        MicHub.shared.removeListener(listenerId)
        attached = false
        if startedHub {
            MicHub.shared.stop()
            startedHub = false
        }
        return analyzer.finish()
    }
}
