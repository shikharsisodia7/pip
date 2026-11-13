// FROZEN shared session store, same shape as the web store.
// Reading screens write: probePre, read, diagnosis, baselineProsody, probePost, practiceBook.
// Pip screens write: pipPlan, catches, expression.
// Anyone may call award, setDebug and registerDebugAction.

import Foundation
import Observation

public struct DebugAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let run: @MainActor () -> Void
}

public let phaseOrder: [Phase] = [.intro, .probePre, .read, .pipReads, .expression, .probePost, .report]

/// Phases visited on a demo path. The 2 minute path skips both probes.
public func phasesFor(_ demoPath: DemoPath) -> [Phase] {
    demoPath == .twoMin ? phaseOrder.filter { $0 != .probePre && $0 != .probePost } : phaseOrder
}

public func nextPhase(after current: Phase, demoPath: DemoPath) -> Phase {
    let visible = phasesFor(demoPath)
    guard let start = phaseOrder.firstIndex(of: current) else { return current }
    return phaseOrder[(start + 1)...].first { visible.contains($0) } ?? current
}

@Observable @MainActor
public final class Session {
    public var phase: Phase = .intro
    public var book: Book
    public var readPageIndex = 0
    public var pipPageIndex = 1
    public var probePre: ProbeResult?
    public var probePost: ProbeResult?
    public var read: ReadResult?
    public var diagnosis: DiagnoseResponse?
    public var baselineProsody: ProsodyStats?
    public var pipPlan: PipPlan?
    public var catches: [CatchResult] = []
    public var expression: ExpressionResult?
    public var practiceBook: PracticeBook?
    public var rewards = RewardState()
    public var debug: [String: String] = [:]
    public private(set) var debugActions: [DebugAction] = []

    public init(book: Book = .placeholder) {
        self.book = book
    }

    /// Stored in Settings so it survives relaunches.
    public var demoPath: DemoPath {
        get { Settings.shared.demoPath }
        set { Settings.shared.demoPath = newValue }
    }

    public var readPage: BookPage? { book.pages.indices.contains(readPageIndex) ? book.pages[readPageIndex] : nil }
    public var pipPage: BookPage? { book.pages.indices.contains(pipPageIndex) ? book.pages[pipPageIndex] : nil }

    public func advance() { phase = nextPhase(after: phase, demoPath: demoPath) }

    public func goto(_ p: Phase) { phase = p }

    /// Starts a fresh session. Keeps the book, demo path and registered debug actions.
    public func reset() {
        phase = .intro
        probePre = nil; probePost = nil; read = nil; diagnosis = nil; baselineProsody = nil
        pipPlan = nil; catches = []; expression = nil; practiceBook = nil
        rewards = RewardState()
        debug = [:]
    }

    public func award(_ event: RewardEvent) {
        rewards.apply(event)
        setDebug("rewards", "\(rewards.stars) stars, stage \(rewards.stage)")
    }

    public func setDebug(_ key: String, _ value: Any) {
        debug[key] = String(describing: value)
    }

    /// Register in .onAppear and call the returned closure in .onDisappear.
    @discardableResult
    public func registerDebugAction(_ label: String, _ run: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let action = DebugAction(label: label, run: run)
        debugActions.removeAll { $0.label == label }
        debugActions.append(action)
        return { [weak self] in self?.debugActions.removeAll { $0.id == action.id } }
    }
}
