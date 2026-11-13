// Shared session store, same shape as the web store.
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

/// Phases visited on a path. The 2 minute path skips both probes.
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
    /// .intro is the home screen; every other phase is part of one reading session.
    public var phase: Phase = .intro
    public var book: Book
    public var readPageIndex = 0
    public var pipPageIndex = 1
    public var probePre: ProbeResult?
    public var probePost: ProbeResult?
    /// The most recent page the child read.
    public var read: ReadResult?
    /// Every page read this session, by page index.
    public var pagesRead: [Int: ReadResult] = [:]
    /// Stars the child had when this reading session began.
    public private(set) var startStars = 0
    public var diagnosis: DiagnoseResponse?
    public var baselineProsody: ProsodyStats?
    public var pipPlan: PipPlan?
    public var catches: [CatchResult] = []
    public var expression: ExpressionResult?
    public var practiceBook: PracticeBook?
    /// Stars, Pip's stage and stickers. Kept across sessions.
    public var rewards: RewardState { didSet { Self.saveRewards(rewards) } }
    public var debug: [String: String] = [:]
    public private(set) var debugActions: [DebugAction] = []

    public init(book: Book = .placeholder) {
        self.book = book
        self.rewards = Self.loadRewards()
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

    /// The page this session began on.
    public private(set) var startPage = 0

    /// Opens a book at a page and starts a fresh reading session. Every page
    /// goes the same way: Pip reads it first, then the child reads it.
    public func startReading(_ book: Book, page: Int = 0) {
        clearSession()
        self.book = book
        startStars = rewards.stars
        readPageIndex = max(0, min(page, book.pages.count - 1))
        pipPageIndex = readPageIndex
        startPage = readPageIndex
        phase = .pipReads
    }

    /// Whether Pip slips on a page. Never on the first page he reads, so the
    /// child hears a good model first, then on every other page.
    public func pipSlips(onPage index: Int) -> Bool {
        (index - startPage) % 2 == 1
    }

    /// Pip has read the page; now the child reads the same page.
    public func childReadsPage() {
        readPageIndex = pipPageIndex
        phase = .read
    }

    /// The child has read a page: Pip reads the next one, or the book is done.
    public func nextPage() {
        guard readPageIndex < book.pages.count - 1 else { return finishBook() }
        readPageIndex += 1
        pipPageIndex = readPageIndex
        phase = .pipReads
    }

    /// Ends the book and shows what the child did.
    public func finishBook() {
        phase = .report
    }

    /// After the child has read, Pip reads the page after the last one they
    /// read (or that same page at the end of the book).
    public func startPipsTurn() {
        let last = pagesRead.keys.max() ?? readPageIndex
        pipPageIndex = min(last + 1, book.pages.count - 1)
        phase = .read
        advance()
    }

    /// Back to the home screen. Keeps the book and the stars, and logs any
    /// pages read, however the session ended.
    public func reset() {
        if let s = summary() { ReadingLog.shared.add(s) }
        clearSession()
        phase = .intro
    }

    /// Clears stars and stickers too (debug only).
    public func resetRewards() { rewards = RewardState() }

    private func clearSession() {
        probePre = nil; probePost = nil; read = nil; pagesRead = [:]; diagnosis = nil; baselineProsody = nil
        pipPlan = nil; catches = []; expression = nil; practiceBook = nil
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

    private static let rewardsKey = "PipRewards"

    private static func loadRewards() -> RewardState {
        guard let data = UserDefaults.standard.data(forKey: rewardsKey),
              let r = try? JSONDecoder().decode(RewardState.self, from: data) else { return RewardState() }
        return r
    }

    private static func saveRewards(_ r: RewardState) {
        if let data = try? JSONEncoder().encode(r) { UserDefaults.standard.set(data, forKey: rewardsKey) }
    }
}
