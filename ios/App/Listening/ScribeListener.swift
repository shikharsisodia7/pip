// Live listening with ElevenLabs Scribe realtime. One socket per reading: a
// fresh single-use token from our server (the API key never reaches the app),
// the microphone streamed as 16 kHz PCM, and the recognizer's events turned
// into one timed transcript. The page colors itself from liveTranscript.
//
// No reconnect: if the socket fails, status becomes .error with a plain
// sentence and stop() still returns everything heard up to that point.

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class ScribeListener: Listening {
    private(set) var status: ListenStatus = .idle
    /// Everything heard so far as text, across segments.
    private(set) var partialText = ""
    private(set) var liveTranscript: Transcript = .empty
    private(set) var errorMessage: String?

    /// How long stop() waits for the final word timestamps.
    static let timestampWait: Duration = .milliseconds(2_500)
    private static let micListenerID = "scribe"

    @ObservationIgnored private var builder = ScribeTranscriptBuilder()
    @ObservationIgnored private var pump: ScribeAudioPump?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var receiveLoop: Task<Void, Never>?
    @ObservationIgnored private var origin = Date()
    @ObservationIgnored private var startedMic = false
    @ObservationIgnored private var stopping = false

    /// Seconds since start(), for the debug view.
    var elapsed: Double { Date().timeIntervalSince(origin) }

    func start() async {
        origin = Date()
        builder = ScribeTranscriptBuilder()
        partialText = ""
        liveTranscript = .empty
        errorMessage = nil
        stopping = false
        status = .connecting

        // The microphone starts first, so a child who begins reading the moment
        // they tap is heard while the socket is still opening.
        guard await AudioSessionManager.shared.requestMic() else {
            return fail("Pip needs the microphone to listen. Turn it on in Settings.")
        }
        if !MicHub.shared.isRunning {
            do { try MicHub.shared.start(); startedMic = true } catch {
                return fail("The microphone is not available right now.")
            }
        }
        let pump = ScribeAudioPump(origin: origin)
        self.pump = pump
        MicHub.shared.addListener(Self.micListenerID) { samples, rate in
            pump.ingest(samples, sampleRate: rate)
        }

        let token: String
        do { token = try await API.current.scribeToken() } catch {
            log("token request failed: \(error.localizedDescription)")
            return fail("Pip could not reach the reading server to start listening.")
        }
        // stop() may already be waiting for the socket; it still wants the
        // buffered audio. After stop() has finished, status is no longer .connecting.
        guard status == .connecting else { return }

        let task = URLSession.shared.webSocketTask(with: ScribeURL.make(token: token))
        socket = task
        task.resume()
        receiveLoop = Task { [weak self] in await self?.receive(from: task) }
    }

    func stop() async -> Transcript {
        stopping = true
        MicHub.shared.removeListener(Self.micListenerID)

        // Tapped stop while the socket was still opening: give it a moment, so
        // the buffered audio still gets transcribed.
        let clock = ContinuousClock()
        let connectDeadline = clock.now + Self.timestampWait
        while status == .connecting, clock.now < connectDeadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if status == .listening, let pump {
            let answered = builder.timestampedSegments
            pump.finish()
            let deadline = clock.now + Self.timestampWait
            while builder.timestampedSegments == answered, status == .listening, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(40))
            }
            if builder.timestampedSegments == answered { log("no final timestamps, using the last partial") }
        }

        let transcript = builder.final
        teardown()
        if status != .error { status = .idle }
        liveTranscript = transcript
        partialText = transcript.text
        return transcript
    }

    // MARK: Socket

    private func receive(from task: URLSessionWebSocketTask) async {
        while true {
            let message: URLSessionWebSocketTask.Message
            do { message = try await task.receive() } catch {
                if !stopping, socket === task {
                    log("socket closed: \(error.localizedDescription)")
                    fail("Pip lost the connection while listening.")
                }
                return
            }
            guard socket === task else { return }
            switch message {
            case .string(let text): handle(ScribeCodec.decode(text))
            case .data(let data): handle(ScribeCodec.decode(String(decoding: data, as: UTF8.self)))
            @unknown default: break
            }
        }
    }

    private func handle(_ event: ScribeEvent) {
        switch event {
        case .sessionStarted:
            guard status == .connecting, let socket else { return }
            status = .listening
            pump?.attach(socket)
        case .partial, .committedText, .committed:
            builder.audioOffset = pump?.audioOffset ?? 0
            builder.apply(event, at: elapsed)
            publish()
        case .warning(let text):
            log("warning: \(text)")
        case .error(let code, let message):
            log("\(code): \(message)")
            fail(ScribeCodec.sentence(forError: code))
        case .ignored:
            break
        }
    }

    private func publish() {
        let live = builder.live
        if live != liveTranscript { liveTranscript = live }
        let text = builder.liveText
        if text != partialText { partialText = text }
    }

    /// Keeps what was heard, releases the mic and the socket.
    private func fail(_ sentence: String) {
        guard status != .error else { return }
        errorMessage = sentence
        status = .error
        teardown()
        publish()
    }

    private func teardown() {
        MicHub.shared.removeListener(Self.micListenerID)
        pump?.cancel()
        pump = nil
        let task = socket
        socket = nil
        task?.cancel(with: .normalClosure, reason: nil)
        receiveLoop?.cancel()
        receiveLoop = nil
        if startedMic { MicHub.shared.stop(); startedMic = false }
    }

    private func log(_ text: String) {
        print("[Pip] scribe \(text)")
    }
}
