// Pip's voice on iPhone. Asks the server for a line (/api/tts), downloads the
// audio, plays it, and calls onWord(i) as each word starts so the screen can
// highlight it. Audio and timings are cached in memory and in the Caches
// directory, so the demo path plays instantly and survives a network drop.
//
// Mock mode or an unreachable server: no audio, but word callbacks still tick
// on evenly spaced timings so highlighting and pacing keep working.

import AVFoundation
import CryptoKit
import Foundation
import Observation
import PipKit

@Observable @MainActor
final class PipPlayer {
    static let shared = PipPlayer()

    private(set) var isSpeaking = false
    /// True when the last line could not get real audio (shown in the debug panel).
    private(set) var audioUnavailable = false

    private struct Entry: Codable { var audioFile: String?; var words: [TimedWord] }

    @ObservationIgnored private var memory: [TtsRequest: Entry] = [:]
    @ObservationIgnored private var inflight: [TtsRequest: Task<Entry?, Never>] = [:]
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var token = UUID()

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PipTTS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Speaking

    /// Stops MicHub first, always: the mic never runs while Pip talks.
    func speak(_ request: TtsRequest, onWord: ((Int) -> Void)?) async {
        MicHub.shared.stop()
        stop()
        let myToken = UUID()
        token = myToken
        isSpeaking = true
        defer { if token == myToken { isSpeaking = false } }

        let entry = await load(request)
        guard token == myToken else { return }
        var words = entry?.words ?? []
        if words.isEmpty, request.mode == .flat {
            words = Transcript.synthetic(PipVoiceText.stripAudioTags(request.text), wordsPerSec: 2.4).words
        }

        if let file = entry?.audioFile,
           let p = try? AVAudioPlayer(contentsOf: cacheDir.appendingPathComponent(file)),
           p.prepareToPlay(), p.play() {
            audioUnavailable = false
            player = p
            var next = 0
            while token == myToken, p.isPlaying {
                let t = p.currentTime
                while next < words.count, t >= words[next].start { onWord?(next); next += 1 }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if token == myToken { while next < words.count { onWord?(next); next += 1 } }
            return
        }

        // No playable audio: tick through the timings so the flow continues.
        audioUnavailable = true
        if words.isEmpty {
            words = Transcript.synthetic(PipVoiceText.stripAudioTags(request.text), wordsPerSec: 2.6).words
        }
        let start = Date()
        var next = 0
        let total = (words.last?.end ?? 1) + 0.2
        while token == myToken {
            let t = Date().timeIntervalSince(start)
            while next < words.count, t >= words[next].start { onWord?(next); next += 1 }
            if t >= total { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Stops whatever Pip is saying.
    func stop() {
        token = UUID()
        player?.stop()
        player = nil
        isSpeaking = false
    }

    // MARK: Loading and caching

    func prefetch(_ requests: [TtsRequest]) async {
        var queue = Array(Set(requests))
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            while !queue.isEmpty || running > 0 {
                while running < 3, let next = queue.popLast() {
                    running += 1
                    group.addTask { @MainActor in _ = await self.load(next) }
                }
                if running > 0 { await group.next(); running -= 1 }
            }
        }
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func key(_ r: TtsRequest) -> String {
        let digest = SHA256.hash(data: Data("v1|\(r.mode.rawValue)|\(r.text)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func load(_ request: TtsRequest) async -> Entry? {
        if let hit = memory[request] { return hit }
        if let running = inflight[request] { return await running.value }
        let task = Task<Entry?, Never> { @MainActor in await self.fetch(request) }
        inflight[request] = task
        let entry = await task.value
        inflight[request] = nil
        if let entry, entry.audioFile != nil { memory[request] = entry }
        return entry
    }

    private func fetch(_ request: TtsRequest) async -> Entry? {
        let k = key(request)
        let metaURL = cacheDir.appendingPathComponent("\(k).json")
        if let data = try? Data(contentsOf: metaURL),
           let entry = try? JSONDecoder().decode(Entry.self, from: data),
           let file = entry.audioFile,
           FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(file).path) {
            return entry
        }

        let api = API.current
        guard let resp = try? await api.tts(request) else { return nil }
        let words = resp.words ?? []
        guard !resp.audioUrl.isEmpty, !api.mock else { return Entry(audioFile: nil, words: words) }

        do {
            let (data, response) = try await URLSession.shared.data(from: api.resolve(resp.audioUrl))
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                return Entry(audioFile: nil, words: words)
            }
            let ext = resp.audioUrl.contains("placeholder") ? "wav" : "mp3"
            let file = "\(k).\(ext)"
            try data.write(to: cacheDir.appendingPathComponent(file), options: .atomic)
            let entry = Entry(audioFile: file, words: words)
            if ext == "mp3", let meta = try? JSONEncoder().encode(entry) { try? meta.write(to: metaURL, options: .atomic) }
            return entry
        } catch {
            return Entry(audioFile: nil, words: words)
        }
    }
}
