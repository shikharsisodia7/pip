// STUB codec for the ElevenLabs Scribe realtime WebSocket, finished by the
// scribe card. Pure Foundation so it is unit tested with `swift test`.

import Foundation

public enum ScribeEvent: Equatable, Sendable {
    case sessionStarted
    case partial(String)
    case committed(String, [TimedWord])
    case error(String)
    case ignored
}

public enum ScribeURL {
    public static let base = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"

    public static func make(token: String) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            URLQueryItem(name: "include_timestamps", value: "true"),
        ]
        return c.url!
    }
}

public enum ScribeCodec {
    /// One input_audio_chunk message for 16 kHz mono Int16 little-endian PCM.
    public static func encodeChunk(_ pcm16: Data) -> String {
        let obj: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm16.base64EncodedString(),
            "commit": false,
            "sample_rate": 16000,
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> ScribeEvent {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["message_type"] as? String else { return .ignored }
        switch type {
        case "session_started": return .sessionStarted
        case "partial_transcript": return .partial(obj["text"] as? String ?? "")
        case "committed_transcript", "committed_transcript_with_timestamps":
            let text = obj["text"] as? String ?? ""
            let raw = obj["words"] as? [[String: Any]] ?? []
            let words = raw.compactMap { w -> TimedWord? in
                guard (w["type"] as? String ?? "word") == "word", let t = w["text"] as? String else { return nil }
                return TimedWord(text: t, start: (w["start"] as? Double) ?? 0, end: (w["end"] as? Double) ?? 0)
            }
            return .committed(text, words)
        default:
            if type.contains("error") { return .error(obj["error"] as? String ?? type) }
            return .ignored
        }
    }
}
