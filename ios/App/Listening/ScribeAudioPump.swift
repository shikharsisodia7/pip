// Moves microphone audio to the Scribe socket. MicHub hands over mono Float
// samples at the hardware rate on the audio thread; this converts them to
// 16 kHz mono Int16 with AVAudioConverter on its own queue and sends about
// 100 ms per message. Audio captured before the socket is ready is kept and
// sent first, so the first words a child reads are never lost.

import AVFoundation
import PipKit

final class ScribeAudioPump: @unchecked Sendable {
    /// 100 ms of 16 kHz Int16 audio.
    static let chunkBytes = 3_200
    /// Largest message when catching up on audio buffered before the socket opened.
    static let backlogChunkBytes = 16_000

    private let origin: Date
    private let queue = DispatchQueue(label: "pip.scribe.audio", qos: .userInitiated)
    private let lock = NSLock()

    // Owned by `queue`.
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                             channels: 1, interleaved: true)!
    private var pending = Data()
    private var socket: URLSessionWebSocketTask?
    private var finished = false

    // Guarded by `lock`.
    private var firstSampleTime: Double?
    private var sentBytes = 0

    init(origin: Date) { self.origin = origin }

    /// Seconds from `origin` to the first captured sample: where the
    /// recognizer's clock starts. Nil until audio arrives.
    var audioOffset: Double? { lock.withLock { firstSampleTime } }

    /// Seconds of audio handed to the socket so far.
    var sentSeconds: Double { lock.withLock { Double(sentBytes) / 32_000 } }

    /// Called on the audio thread by MicHub.
    func ingest(_ samples: [Float], sampleRate: Double) {
        let arrival = Date()
        lock.withLock {
            if firstSampleTime == nil {
                firstSampleTime = arrival.timeIntervalSince(origin) - Double(samples.count) / sampleRate
            }
        }
        queue.async { [self] in
            guard !finished else { return }
            convert(samples, sampleRate: sampleRate)
            drain(minimum: Self.chunkBytes, commit: false)
        }
    }

    /// Starts sending, beginning with everything buffered so far.
    func attach(_ socket: URLSessionWebSocketTask) {
        queue.async { [self] in
            self.socket = socket
            drain(minimum: Self.chunkBytes, commit: false)
        }
    }

    /// Sends the rest of the audio with commit: true, which closes the segment
    /// and asks for its word timestamps. Later audio is dropped.
    func finish() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            guard socket != nil else { return }
            drain(minimum: 0, commit: true)
        }
    }

    /// Stops sending without a commit (the socket failed or was closed).
    func cancel() {
        queue.async { [self] in
            finished = true
            socket = nil
            pending.removeAll()
        }
    }

    // MARK: Queue work

    private func convert(_ samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }
        if inputFormat?.sampleRate != sampleRate {
            inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                        channels: 1, interleaved: false)
            converter = inputFormat.flatMap { AVAudioConverter(from: $0, to: outputFormat) }
        }
        guard let inputFormat, let converter,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            input.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let capacity = AVAudioFrameCount(Double(samples.count) * 16_000 / sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var given = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0, let ch = output.int16ChannelData else { return }
        pending.append(Data(bytes: ch[0], count: Int(output.frameLength) * 2))
    }

    /// Sends buffered audio while at least `minimum` bytes are waiting. With
    /// `commit`, sends everything left (even nothing) as the final message.
    private func drain(minimum: Int, commit: Bool) {
        guard let socket else { return }
        while pending.count >= max(minimum, 1) {
            let size = min(pending.count, pending.count > Self.chunkBytes * 2 ? Self.backlogChunkBytes : Self.chunkBytes)
            let isLast = commit && size == pending.count
            send(pending.prefix(size), commit: isLast, on: socket)
            pending.removeFirst(size)
            if isLast { return }
        }
        if commit { send(Data(), commit: true, on: socket) }
    }

    private func send(_ pcm: Data, commit: Bool, on socket: URLSessionWebSocketTask) {
        lock.withLock { sentBytes += pcm.count }
        socket.send(.string(ScribeCodec.encodeChunk(pcm16: Data(pcm), commit: commit))) { _ in
            // A failed send also fails the receive loop, which reports the error.
        }
    }
}
