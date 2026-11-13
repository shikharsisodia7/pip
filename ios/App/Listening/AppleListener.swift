// Live listening with Apple's speech recognizer, fed from MicHub. Works with no
// server and, where the device supports it, fully on device.

import AVFoundation
import Foundation
import Observation
import PipKit
import Speech

@Observable @MainActor
final class AppleListener: Listening {
    private(set) var status: ListenStatus = .idle
    private(set) var partialText = ""
    private(set) var liveTranscript: Transcript = .empty
    private(set) var errorMessage: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var startedMic = false
    @ObservationIgnored private var gotFinal = false
    @ObservationIgnored private var t0 = Date()
    /// When each word index first appeared, for partials that have no timestamps yet.
    @ObservationIgnored private var arrivals: [Double] = []

    private static let listenerId = "apple-speech"

    func start() async {
        status = .connecting
        errorMessage = nil
        gotFinal = false
        arrivals = []
        liveTranscript = .empty
        partialText = ""

        guard await Self.requestSpeechPermission() else { return fail("Speech recognition is turned off for Pip in Settings.") }
        guard await AudioSessionManager.shared.requestMic() else { return fail("The microphone is turned off for Pip in Settings.") }
        guard let recognizer, recognizer.isAvailable else { return fail("Speech recognition is not available right now.") }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let segments = result?.bestTranscription.segments.map { ($0.substring, $0.timestamp, $0.duration) } ?? []
            let isFinal = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor in self?.handle(segments, isFinal: isFinal, error: message) }
        }

        MicHub.shared.addListener(Self.listenerId) { samples, sampleRate in
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            req.append(buffer)
        }
        if !MicHub.shared.isRunning {
            do { try MicHub.shared.start(); startedMic = true } catch { return fail("The microphone could not start.") }
        }
        t0 = Date()
        status = .listening
    }

    func stop() async -> Transcript {
        MicHub.shared.removeListener(Self.listenerId)
        if startedMic { MicHub.shared.stop(); startedMic = false }
        request?.endAudio()
        // Wait briefly for the final result, which carries real word timestamps.
        for _ in 0..<20 where !gotFinal && status != .error {
            try? await Task.sleep(for: .milliseconds(100))
        }
        task?.cancel()
        task = nil
        request = nil
        if status != .error { status = .idle }
        return liveTranscript
    }

    private func handle(_ segments: [(String, TimeInterval, TimeInterval)], isFinal: Bool, error: String?) {
        if !segments.isEmpty {
            let now = Date().timeIntervalSince(t0)
            while arrivals.count < segments.count { arrivals.append(now) }
            let words = segments.enumerated().map { i, s -> TimedWord in
                s.1 > 0 || s.2 > 0
                    ? TimedWord(text: s.0, start: s.1, end: s.1 + s.2)
                    : TimedWord(text: s.0, start: arrivals[i], end: arrivals[i] + 0.3)
            }
            let text = segments.map(\.0).joined(separator: " ")
            liveTranscript = Transcript(text: text, words: words)
            partialText = text
        }
        if isFinal { gotFinal = true }
        // Recognition ending with no speech is not an error worth showing.
        if let error, segments.isEmpty, !gotFinal, status == .listening {
            errorMessage = error
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        status = .error
    }

    private static func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        }
    }
}
