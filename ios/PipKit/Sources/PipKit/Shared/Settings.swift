// FROZEN shared settings, persisted in UserDefaults. Override at launch with
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
        static let threshold = "PipExpressionThreshold", listener = "PipListener"
    }

    public static let defaultBaseURL = URL(string: "http://localhost:3000")!

    public var baseURL: URL { didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: Key.baseURL) } }
    /// Mock mode: no network, bundled fixtures and the mock listener.
    public var mock: Bool { didSet { UserDefaults.standard.set(mock, forKey: Key.mock) } }
    public var demoPath: DemoPath { didSet { UserDefaults.standard.set(demoPath.rawValue, forKey: Key.demoPath) } }
    /// Expression pass threshold, tuned in the room from the debug panel.
    public var expressionThreshold: Double { didSet { UserDefaults.standard.set(expressionThreshold, forKey: Key.threshold) } }
    /// Which live listener to use when not in mock mode.
    public var listenerKind: ListenerKind { didSet { UserDefaults.standard.set(listenerKind.rawValue, forKey: Key.listener) } }

    public init() {
        let d = UserDefaults.standard
        baseURL = d.string(forKey: Key.baseURL).flatMap(URL.init(string:)) ?? Settings.defaultBaseURL
        mock = d.object(forKey: Key.mock) as? Bool ?? true
        demoPath = d.string(forKey: Key.demoPath).flatMap(DemoPath.init(rawValue:)) ?? .twoMin
        expressionThreshold = d.object(forKey: Key.threshold) as? Double ?? 1.25
        listenerKind = d.string(forKey: Key.listener).flatMap(ListenerKind.init(rawValue:)) ?? .scribe
    }
}
