// FROZEN API. The one microphone tap for the whole app. Listeners (speech
// recognition, prosody) subscribe and receive mono Float samples at the
// hardware rate on the audio thread.

import AVFoundation
import Observation

@Observable @MainActor
final class MicHub {
    static let shared = MicHub()

    private(set) var isRunning = false
    /// 0...1 input level, smoothed, for meters.
    private(set) var level: Float = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let store = ListenerStore()

    enum MicError: Error { case noInput }

    func start() throws {
        if isRunning { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicError.noInput }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.makeTap(store: store, sampleRate: format.sampleRate) { [weak self] rms in
            Task { @MainActor in self?.updateLevel(rms) }
        })
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    func addListener(_ id: String, _ handler: @escaping @Sendable (_ samples: [Float], _ sampleRate: Double) -> Void) {
        store.set(id, handler)
    }

    func removeListener(_ id: String) {
        store.remove(id)
    }

    private func updateLevel(_ rms: Float) {
        let target = min(1, rms * 8)
        level = level * 0.6 + target * 0.4
    }

    /// Built outside the main actor so the audio thread never asserts main-actor isolation.
    nonisolated private static func makeTap(store: ListenerStore, sampleRate: Double,
                                            onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: ch, count: n))
            var sum: Float = 0
            for s in samples { sum += s * s }
            onLevel(n > 0 ? (sum / Float(n)).squareRoot() : 0)
            for h in store.handlers() { h(samples, sampleRate) }
        }
    }
}

/// Lock-protected listener table shared with the audio thread.
private final class ListenerStore: @unchecked Sendable {
    typealias Handler = @Sendable ([Float], Double) -> Void
    private let lock = NSLock()
    private var table: [String: Handler] = [:]

    func set(_ id: String, _ h: @escaping Handler) { lock.lock(); table[id] = h; lock.unlock() }
    func remove(_ id: String) { lock.lock(); table[id] = nil; lock.unlock() }
    func handlers() -> [Handler] { lock.lock(); defer { lock.unlock() }; return Array(table.values) }
}
