// API client for the Next.js backend. Reading diagnosis and Pip's mistake
// plan fall back to on-device versions when the server is unreachable.

import Foundation

public enum APIError: Error, LocalizedError {
    case badStatus(Int, String)
    case missingFixture(String)
    case unavailableInMock(String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code, let path): return "\(path) returned \(code)"
        case .missingFixture(let name): return "Missing fixture \(name).json"
        case .unavailableInMock(let what): return "\(what) is not available in mock mode"
        }
    }
}

/// Remembers a recent failure to reach the server, so later calls fall back
/// to on-device versions at once. Clears after 30 seconds or any success.
public final class ServerReachability: @unchecked Sendable {
    public static let shared = ServerReachability()
    static let unreachableCodes: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .networkConnectionLost, .notConnectedToInternet,
    ]
    private let lock = NSLock()
    private var downUntil = Date.distantPast

    public var isDown: Bool { lock.withLock { Date() < downUntil } }
    public func markDown() { lock.withLock { downUntil = Date().addingTimeInterval(30) } }
    public func markUp() { lock.withLock { downUntil = .distantPast } }
}

public struct API: Sendable {
    public var baseURL: URL
    public var mock: Bool

    public init(baseURL: URL, mock: Bool) { self.baseURL = baseURL; self.mock = mock }

    /// Built from the current Settings each time, so toggles apply immediately.
    @MainActor public static var current: API {
        API(baseURL: Settings.shared.baseURL, mock: Settings.shared.mock)
    }

    /// Absolute URL for a server path such as "/api/tts/audio/abc".
    public func resolve(_ path: String) -> URL {
        if let u = URL(string: path), u.scheme != nil { return u }
        return URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    public func get<T: Decodable>(_ path: String, as: T.Type = T.self, timeout: TimeInterval = 20) async throws -> T {
        var req = URLRequest(url: resolve(path))
        req.timeoutInterval = timeout
        if mock { req.setValue("1", forHTTPHeaderField: "x-pip-mock") }
        return try await send(req, path)
    }

    public func post<B: Encodable, T: Decodable>(_ path: String, _ body: B, as: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: resolve(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if mock { req.setValue("1", forHTTPHeaderField: "x-pip-mock") }
        req.httpBody = try Self.encoder.encode(body)
        return try await send(req, path)
    }

    private func send<T: Decodable>(_ req: URLRequest, _ path: String) async throws -> T {
        // After a connection failure, fail at once for a while instead of
        // making every screen wait out its own timeout.
        if ServerReachability.shared.isDown { throw URLError(.cannotConnectToHost) }
        let data: Data, res: URLResponse
        do {
            (data, res) = try await URLSession.shared.data(for: req)
            ServerReachability.shared.markUp()
        } catch let e as URLError where ServerReachability.unreachableCodes.contains(e.code) {
            ServerReachability.shared.markDown()
            throw e
        }
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.badStatus(code, path) }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Decodes App/Fixtures/<name>.json from the app bundle.
    public static func fixture<T: Decodable>(_ name: String, as: T.Type = T.self) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw APIError.missingFixture(name)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: Routes

    /// GET /api/book, or the bundled book.json.
    public func book() async throws -> Book {
        if mock { return (try? Self.fixture("book")) ?? .placeholder }
        do { return try await get("/api/book", timeout: 5) } catch { return (try? Self.fixture("book")) ?? .placeholder }
    }

    private struct TokenResponse: Decodable { let token: String }

    /// Single-use ElevenLabs realtime token. Never available in mock mode.
    public func scribeToken() async throws -> String {
        if mock { throw APIError.unavailableInMock("Live listening") }
        let r: TokenResponse = try await get("/api/scribe-token", timeout: 4)
        guard !r.token.isEmpty else { throw APIError.badStatus(501, "/api/scribe-token") }
        return r.token
    }

    private struct DiagnoseBody: Encodable { let pageText: String; let alignment: AlignmentResult; let metrics: ReadingMetrics }

    public func diagnose(pageText: String, alignment: AlignmentResult, metrics: ReadingMetrics) async throws -> DiagnoseResponse {
        if mock { return localDiagnosis(pageText: pageText, alignment: alignment) }
        do {
            return try await post("/api/diagnose", DiagnoseBody(pageText: pageText, alignment: alignment, metrics: metrics))
        } catch {
            return localDiagnosis(pageText: pageText, alignment: alignment)
        }
    }

    private struct PracticeBody: Encodable { let pattern: PatternFinding }

    public func practiceBook(pattern: PatternFinding) async throws -> PracticeBook {
        if mock {
            if let book: PracticeBook = try? Self.fixture("practice-\(pattern.id)") { return book }
            return try Self.fixture("practice-generic")
        }
        return try await post("/api/practice-book", PracticeBody(pattern: pattern))
    }

    private struct MistakesBody: Encodable { let pageIndex: Int; let pageText: String; let patterns: [PatternFinding] }

    public func pipMistakes(pageIndex: Int, pageText: String, patterns: [PatternFinding]) async throws -> PipPlan {
        if mock { return localPipPlan(pageIndex: pageIndex, pageText: pageText, patterns: patterns) }
        do {
            return try await post("/api/pip-mistakes", MistakesBody(pageIndex: pageIndex, pageText: pageText, patterns: patterns))
        } catch {
            return localPipPlan(pageIndex: pageIndex, pageText: pageText, patterns: patterns)
        }
    }

    /// In mock mode returns an empty audioUrl and synthetic word timings; PipPlayer
    /// then animates the karaoke on a timer instead of playing audio.
    public func tts(_ request: TtsRequest) async throws -> TtsResponse {
        if mock {
            let words = request.mode == .flat ? Transcript.synthetic(request.text, wordsPerSec: 2.6).words : nil
            return TtsResponse(audioUrl: "", words: words)
        }
        return try await post("/api/tts", request)
    }

    private struct TagsBody: Encodable { let line: EmotionLine; let context: String }

    public func expressionTags(line: EmotionLine, context: String = "") async throws -> ExpressionTags {
        if mock { return try Self.fixture("pip-expression-tags") }
        return try await post("/api/expression-tags", TagsBody(line: line, context: context))
    }

    private struct SummaryResponse: Decodable { let summary: String? }

    /// One line from the measured eval, or nil when no eval has been run.
    public func evalSummary() async -> String? {
        if mock { return nil }
        let r: SummaryResponse? = try? await get("/api/eval-summary")
        return r?.summary
    }
}
