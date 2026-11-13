// The default listener: ElevenLabs Scribe through the server (best at hearing
// a child's real misreadings), falling back to Apple's recognizer when the
// server or network is unavailable.

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class AutoListener: Listening {
    private var inner: any Listening = ScribeListener()

    var status: ListenStatus { inner.status }
    var partialText: String { inner.partialText }
    var liveTranscript: Transcript { inner.liveTranscript }
    var errorMessage: String? { inner.errorMessage }

    func start() async {
        await inner.start()
        guard inner.status == .error else { return }
        #if DEBUG
        print("[Pip] Scribe unavailable (\(inner.errorMessage ?? "unknown")), using Apple speech")
        #endif
        _ = await inner.stop()
        inner = AppleListener()
        await inner.start()
    }

    func stop() async -> Transcript {
        await inner.stop()
    }
}
