// Wire format for the ElevenLabs Scribe realtime speech-to-text WebSocket.
// Pure Foundation so it is unit tested with `swift test`.

import Foundation

public enum ScribeEvent: Equatable, Sendable {
    case sessionStarted
    /// Interim text for the open segment. Each one replaces the last.
    case partial(String)
    /// `committed_transcript`: the segment's settled text. Its word timestamps follow.
    case committedText(String)
    /// `committed_transcript_with_timestamps`: the settled segment with word
    /// times in seconds from the first audio sample of the session.
    case committed(String, [TimedWord])
    case warning(String)
    /// `code` is the server's message_type, such as "auth_error" or "rate_limited".
    case error(code: String, message: String)
    case ignored
}

public enum ScribeURL {
    public static let base = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"

    /// scribe_v3_live keeps made-up words as heard ("cottle" stays "cottle") where
    /// scribe_v2_realtime snaps them to the nearest real word, and its partials
    /// arrive about three times as often, so the page colors keep up with the reader.
    public static let model = "scribe_v3_live"

    /// The socket URL for one single-use token.
    ///
    /// Deliberately absent:
    /// - `keyterms`: we never send the story words. Biasing the recognizer toward
    ///   the page would turn a child's misreading into the printed word, and the
    ///   whole point is to hear what they actually said.
    /// - `no_verbatim`: left at its default (false) so "um", restarts and repeated
    ///   words stay in the transcript.
    public static func make(token: String) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = [
            URLQueryItem(name: "model_id", value: model),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "include_timestamps", value: "true"),
            URLQueryItem(name: "language_code", value: "en"),
        ]
        return c.url!
    }
}

public enum ScribeCodec {
    public static let sampleRate = 16_000

    /// Error message types listed in the realtime API reference.
    static let errorTypes: Set<String> = [
        "error", "auth_error", "quota_exceeded", "commit_throttled", "unaccepted_terms",
        "rate_limited", "queue_overflow", "resource_exhausted", "session_time_limit_exceeded",
        "input_error", "invalid_request", "chunk_size_exceeded", "insufficient_audio_activity",
        "transcriber_error",
    ]

    /// One `input_audio_chunk` message for 16 kHz mono Int16 little-endian PCM.
    /// `commit: true` closes the segment and asks for its word timestamps.
    public static func encodeChunk(pcm16: Data, commit: Bool) -> String {
        let obj: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm16.base64EncodedString(),
            "commit": commit,
            "sample_rate": sampleRate,
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> ScribeEvent {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["message_type"] as? String else { return .ignored }
        let text = obj["text"] as? String ?? ""
        switch type {
        case "session_started": return .sessionStarted
        case "partial_transcript": return .partial(text)
        case "committed_transcript": return .committedText(text)
        case "committed_transcript_with_timestamps":
            let raw = obj["words"] as? [[String: Any]] ?? []
            let words = raw.compactMap { w -> TimedWord? in
                // Only spoken words; "spacing" entries carry the gaps between them.
                guard (w["type"] as? String ?? "word") == "word",
                      let t = w["text"] as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty,
                      let start = number(w["start"]) else { return nil }
                return TimedWord(text: t, start: start, end: number(w["end"]) ?? start)
            }
            return .committed(text, words)
        case "warning": return .warning(obj["warning"] as? String ?? "")
        default:
            if errorTypes.contains(type) || type.hasSuffix("error") {
                return .error(code: type, message: obj["error"] as? String ?? "")
            }
            return .ignored
        }
    }

    /// A plain sentence for the operator. Never shown as a grade.
    public static func sentence(forError code: String) -> String {
        switch code {
        case "auth_error": return "The listening service did not accept our key."
        case "quota_exceeded": return "The listening service is out of quota."
        case "unaccepted_terms": return "The listening account still needs to accept the Scribe terms."
        case "rate_limited", "commit_throttled", "queue_overflow", "resource_exhausted":
            return "The listening service is busy. Try again in a moment."
        case "session_time_limit_exceeded": return "The listening session ran out of time."
        case "insufficient_audio_activity": return "Listening stopped because no sound was reaching it."
        case "input_error", "invalid_request", "chunk_size_exceeded":
            return "The listening service did not accept our audio."
        default: return "The listening service had a problem."
        }
    }

    private static func number(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }
}
