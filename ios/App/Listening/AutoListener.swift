// The default listener: ElevenLabs Scribe through the server (best at hearing
// a child's real misreadings), falling back to Apple's recognizer when the
// server or network is unavailable or the session does not open quickly.

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class AutoListener: Listening {
    private var inner: any Listening = ScribeListener()
    @ObservationIgnored private var stopped = false

    /// How long Scribe may take to open its session before Apple takes over.
    private static let connectGrace = Duration.seconds(4)

    var status: ListenStatus { inner.status }
    var partialText: String { inner.partialText }
    var liveTranscript: Transcript { inner.liveTranscript }
    var errorMessage: String? { inner.errorMessage }

    func start() async {
        stopped = false
        await inner.start()
        let deadline = ContinuousClock.now + Self.connectGrace
        while inner.status == .connecting, !stopped, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !stopped, inner.status == .error || inner.status == .connecting else { return }
        #if DEBUG
        print("[Pip] Scribe unavailable (\(inner.errorMessage ?? "slow to connect")), using Apple speech")
        #endif
        _ = await inner.stop()
        guard !stopped else { return }
        inner = AppleListener()
        await inner.start()
    }

    func stop() async -> Transcript {
        stopped = true
        return await inner.stop()
    }
}
