// FROZEN. Configures the shared audio session once at launch. Nobody else
// touches AVAudioSession.

import AVFoundation

@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private(set) var micAllowed = false

    func configure() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try s.setActive(true)
        } catch {
            print("[Pip] audio session error: \(error)")
        }
    }

    /// Asks for the microphone once; later calls return the stored answer.
    @discardableResult
    func requestMic() async -> Bool {
        if micAllowed { return true }
        micAllowed = await AVAudioApplication.requestRecordPermission()
        return micAllowed
    }
}
