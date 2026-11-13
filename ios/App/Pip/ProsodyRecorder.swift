// STUB, replaced by the real recorder. Keep the API.

import Foundation
import PipKit

@MainActor
final class ProsodyRecorder {
    var onFrame: ((ProsodyFrame) -> Void)?

    /// Attaches to MicHub; starts MicHub if it is not running.
    func start() {}

    /// Detaches; stops MicHub only if it started it.
    func stop() -> ProsodyStats { .zero }
}
