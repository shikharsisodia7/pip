// FROZEN shared rewards model. Kids earn stars for good reading moments, and
// Pip visibly levels up (stage 1 to 4) as stars add up. The thresholds are set
// so one session can reach the top stage: reading a page, catching Pip's
// mistake and teaching him expression each push him up a stage. Stars are
// kept across sessions.

import Foundation

public enum RewardEvent: Codable, Sendable, Equatable {
    case pageRead(correctWords: Int)
    case mistakeCaught
    case expressionLearned
    case probeFinished

    public var stars: Int {
        switch self {
        case .pageRead(let n): return max(3, min(n, 12))
        case .mistakeCaught: return 8
        case .expressionLearned: return 10
        case .probeFinished: return 3
        }
    }

    /// Short kid-facing reason for the toast.
    public var reason: String {
        switch self {
        case .pageRead: return "Great reading!"
        case .mistakeCaught: return "You caught it!"
        case .expressionLearned: return "You taught Pip feelings!"
        case .probeFinished: return "Warm up done!"
        }
    }
}

public struct RewardState: Codable, Sendable, Equatable {
    /// Stars needed to reach stage 1, 2, 3, 4.
    public static let stageThresholds = [0, 10, 18, 28]
    public static let stageNames = ["Sprout", "Glow", "Star", "Crown"]

    public private(set) var stars = 0
    /// Stars from the most recent award (for the "+N" toast).
    public private(set) var lastGain = 0
    /// Increments on every award, so views can react to repeated equal gains.
    public private(set) var gainCount = 0
    public private(set) var lastEvent: RewardEvent?
    /// Sticker ids unlocked so far, one per stage reached after the first.
    public private(set) var stickers: [String] = []

    public init() {}

    /// 1...4
    public var stage: Int {
        (Self.stageThresholds.lastIndex { stars >= $0 } ?? 0) + 1
    }

    public var stageName: String { Self.stageNames[stage - 1] }

    /// Stars still needed for the next stage, nil at the top stage.
    public var starsToNextStage: Int? {
        stage < Self.stageThresholds.count ? Self.stageThresholds[stage] - stars : nil
    }

    /// 0...1 progress through the current stage (1 at the top stage).
    public var stageProgress: Double {
        guard stage < Self.stageThresholds.count else { return 1 }
        let lo = Self.stageThresholds[stage - 1], hi = Self.stageThresholds[stage]
        return Double(stars - lo) / Double(hi - lo)
    }

    public mutating func apply(_ event: RewardEvent) {
        let before = stage
        stars += event.stars
        lastGain = event.stars
        gainCount += 1
        lastEvent = event
        if stage > before {
            for s in (before + 1)...stage { stickers.append(Self.stageNames[s - 1].lowercased()) }
        }
    }
}
