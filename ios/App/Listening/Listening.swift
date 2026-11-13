// FROZEN API. Speech listeners: the live ElevenLabs Scribe listener, an
// on-device fallback, and a scripted mock for the Simulator and rehearsal.

import Foundation
import Observation
import PipKit

enum ListenStatus { case idle, connecting, listening, error }

@MainActor protocol Listening: AnyObject, Observable {
    var status: ListenStatus { get }
    var partialText: String { get }
    /// Everything heard so far, with times in seconds since start(). Committed
    /// words carry recognizer timestamps; words still in a partial are stamped
    /// on arrival. Drives the live word colors (liveMarks).
    var liveTranscript: Transcript { get }
    var errorMessage: String? { get }
    /// Starts MicHub, mints a token, opens the socket.
    func start() async
    /// Commits, waits for word timestamps, stops MicHub.
    func stop() async -> Transcript
}

enum Listeners {
    /// The scripted listener in mock mode; otherwise the live listener chosen in Settings.
    @MainActor static func make() -> any Listening {
        if Settings.shared.mock { return MockListener() }
        switch Settings.shared.listenerKind {
        case .scribe: return AutoListener()
        case .apple: return AppleListener()
        }
    }
}
