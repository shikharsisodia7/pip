// Shared settings, persisted in UserDefaults. Override at launch with
// arguments such as `-PipMock NO` or `-PipBaseURL http://192.168.1.20:3000`.

import Foundation
import Observation

public enum DemoPath: String, Codable, Sendable, CaseIterable {
    case twoMin = "2min", threeMin = "3min", full
    public var label: String {
        switch self {
        case .twoMin: return "2 minute"
        case .threeMin: return "3 minute"
        case .full: return "Full"
        }
    }
}

public enum ListenerKind: String, Codable, Sendable, CaseIterable {
    case scribe, apple
}

@Observable @MainActor
public final class Settings {
    public static let shared = Settings()

    private enum Key {
        static let baseURL = "PipBaseURL", mock = "PipMock", demoPath = "PipDemoPath"
        static let threshold = "PipExpressionThreshold", listener = "PipListener", name = "PipChildName"
    }

    public static let defaultBaseURL = URL(string: "http://localhost:3000")!

    public var baseURL: URL { didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: Key.baseURL) } }
    /// The reader's first name for the greeting. Empty until they tell us.
    public var childName: String { didSet { UserDefaults.standard.set(childName, forKey: Key.name) } }
    /// Mock mode: no network, bundled fixtures and the scripted listener. Off by default;
    /// for offline rehearsal only.
    public var mock: Bool { didSet { UserDefaults.standard.set(mock, forKey: Key.mock) } }
    public var demoPath: DemoPath { didSet { UserDefaults.standard.set(demoPath.rawValue, forKey: Key.demoPath) } }
    /// Expression pass threshold, tuned in the room from the debug panel.
    public var expressionThreshold: Double { didSet { UserDefaults.standard.set(expressionThreshold, forKey: Key.threshold) } }
    /// Which live listener to use when not in mock mode. Scribe falls back to
    /// Apple's recognizer when the server is unreachable.
    public var listenerKind: ListenerKind { didSet { UserDefaults.standard.set(listenerKind.rawValue, forKey: Key.listener) } }

    public init() {
        let d = UserDefaults.standard
        baseURL = d.string(forKey: Key.baseURL).flatMap(URL.init(string:)) ?? Settings.defaultBaseURL
        childName = d.string(forKey: Key.name) ?? ""
        // bool(forKey:) and double(forKey:) also parse launch arguments such as `-PipMock NO`.
        mock = d.object(forKey: Key.mock) == nil ? false : d.bool(forKey: Key.mock)
        demoPath = d.string(forKey: Key.demoPath).flatMap(DemoPath.init(rawValue:)) ?? .twoMin
        expressionThreshold = d.object(forKey: Key.threshold) == nil ? 1.25 : d.double(forKey: Key.threshold)
        listenerKind = d.string(forKey: Key.listener).flatMap(ListenerKind.init(rawValue:)) ?? .scribe
    }
}
