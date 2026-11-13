import SwiftUI
import PipKit

/// The home of the app: four tabs over the indigo backdrop.
struct IntroScreen: View {
    var body: some View { MainTabs() }
}

enum HomeTab: String, CaseIterable {
    case home, library, progress, stickers

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "books.vertical.fill"
        case .progress: return "chart.bar.fill"
        case .stickers: return "star.fill"
        }
    }
}

struct MainTabs: View {
    @Environment(Session.self) private var session
    @State private var tab: HomeTab = HomeTab(rawValue: UserDefaults.standard.string(forKey: "PipTab") ?? "") ?? .home
    @State private var askName = Settings.shared.childName.isEmpty

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeTabView(tab: $tab)
                case .library: LibraryTabView()
                case .progress: ProgressTabView()
                case .stickers: StickersTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(tab: $tab)
        }
        .sheet(isPresented: $askName) { NameSheet().environment(session).presentationDetents([.medium]) }
    }
}

/// Floating glass tab bar; the selected tab rises into a glowing orb.
struct TabBar: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack {
            ForEach(HomeTab.allCases, id: \.self) { t in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { tab = t } } label: {
                    ZStack {
                        if tab == t {
                            Orb(systemImage: t.icon, colors: Palette.purpleOrb, size: 54)
                                .offset(y: -10)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: t.icon)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Palette.textSoft.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(SquishStyle())
            }
        }
        .padding(.horizontal, 10)
        .background(
            Capsule().fill(Color(hex: 0x1D2152).opacity(0.92))
                .overlay(Capsule().strokeBorder(Palette.stroke))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }
}

/// Centered, width-limited scroll column so portrait and landscape both look right.
struct TabPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) { content() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 110)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Home

struct HomeTabView: View {
    @Environment(Session.self) private var session
    @Binding var tab: HomeTab
    @State private var showPractice = UserDefaults.standard.string(forKey: "PipSheet") == "practice"
    private var library: Library { .shared }

    var body: some View {
        TabPage {
            VStack(spacing: 14) {
                Text(greeting)
                    .font(.pip(30, .bold))
                    .foregroundStyle(.white)
                StatsPill()
            }

            HStack(alignment: .top) {
                CategoryButton(title: "Books", systemImage: "book.fill", colors: Palette.purpleOrb) { tab = .library }
                Spacer()
                CategoryButton(title: "Read", systemImage: "mic.fill", colors: Palette.blueOrb) { startContinue() }
                Spacer()
                CategoryButton(title: "Practice", systemImage: "pencil", colors: Palette.pinkOrb) { showPractice = true }
                Spacer()
                CategoryButton(title: "Stickers", systemImage: "star.fill", colors: Palette.orangeOrb) { tab = .stickers }
            }
            .padding(.horizontal, 6)

            if let book = library.continueBook { heroCard(book) }

            SectionHeader(title: "Your books", trailing: "See all") { tab = .library }
            ForEach(Array(library.books.prefix(3).enumerated()), id: \.element.id) { i, book in
                Button { session.startReading(book, page: library.nextPage(book)) } label: {
                    BookCard(book: book, progress: library.progress(book), colors: Palette.cardGradients[i % Palette.cardGradients.count])
                }
                .buttonStyle(SquishStyle())
            }
        }
        .sheet(isPresented: $showPractice) { PracticeScreen().environment(session) }
    }

    private var greeting: String {
        let name = Settings.shared.childName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Hello, reader 👋" : "Hello, \(name) 👋"
    }

    private func startContinue() {
        guard let book = library.continueBook else { return }
        session.startReading(book, page: library.nextPage(book))
    }

    private func heroCard(_ book: Book) -> some View {
        let progress = library.progress(book)
        return Button { startContinue() } label: {
            ZStack(alignment: .bottomTrailing) {
                GlassCard(colors: Palette.oceanCard, radius: 30, padding: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(progress > 0 ? "Keep reading" : "Start reading")
                                    .font(.pip(14, .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(book.title)
                                    .font(.pip(24, .bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Orb(systemImage: "arrow.right", colors: [Color(hex: 0x5FD0FF), Color(hex: 0x1F7FC0)], size: 46)
                        }
                        Spacer(minLength: 6)
                        if book.pages.count <= 7 {
                            PagePath(pages: book.pages.count, done: library.pagesDone[book.id] ?? [], next: library.nextPage(book))
                        } else {
                            ProgressPill(value: progress)
                        }
                        Text("Page \(library.nextPage(book) + 1) of \(book.pages.count)")
                            .font(.pip(14, .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(minHeight: 170, alignment: .top)
                }
                PipView(state: .idle, size: 112)
                    .padding(.trailing, 6)
                    .padding(.bottom, -6)
            }
        }
        .buttonStyle(SquishStyle())
    }
}

// MARK: Library

struct LibraryTabView: View {
    @Environment(Session.self) private var session
    @State private var adding = UserDefaults.standard.string(forKey: "PipSheet") == "add"
    private var library: Library { .shared }

    var body: some View {
        TabPage {
            HStack {
                Text("Library").font(.pip(30, .bold)).foregroundStyle(.white)
                Spacer()
                StatsPill()
            }

            Button { adding = true } label: {
                HStack(spacing: 14) {
                    Orb(systemImage: "plus", colors: Palette.mintOrb, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add a book").font(.pip(19, .bold)).foregroundStyle(.white)
                        Text("Snap a page or type it in").font(.pip(14, .semibold)).foregroundStyle(Palette.textSoft)
                    }
                    Spacer()
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.glass))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6])).foregroundStyle(Palette.mint.opacity(0.6)))
            }
            .buttonStyle(SquishStyle())

            ForEach(Array(library.books.enumerated()), id: \.element.id) { i, book in
                Button { session.startReading(book, page: library.nextPage(book)) } label: {
                    BookCard(book: book, progress: library.progress(book), colors: Palette.cardGradients[i % Palette.cardGradients.count])
                }
                .buttonStyle(SquishStyle())
                .contextMenu {
                    Button("Read from the start", systemImage: "arrow.counterclockwise") { session.startReading(book, page: 0) }
                    if book.isUserBook {
                        Button("Remove book", systemImage: "trash", role: .destructive) { library.remove(book.id) }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { AddBookView() }
    }
}

// MARK: Progress

struct ProgressTabView: View {
    @Environment(Session.self) private var session
    private var library: Library { .shared }
    private var log: ReadingLog { .shared }

    var body: some View {
        TabPage {
            HStack {
                Text("Progress").font(.pip(30, .bold)).foregroundStyle(.white)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                tile("star.fill", Palette.orangeOrb, "\(session.rewards.stars)", "stars earned")
                tile("book.fill", Palette.mintOrb, "\(library.totalPagesRead)", "pages read")
                tile("checkmark.seal.fill", Palette.blueOrb, "\(library.books.filter { library.progress($0) >= 1 }.count)", "books finished")
                tile("text.word.spacing", Palette.pinkOrb, "\(log.sessions.reduce(0) { $0 + $1.wordsCorrect })", "words read right")
            }

            SectionHeader(title: "Recent reading")
            if log.sessions.isEmpty {
                GlassCard {
                    HStack(spacing: 14) {
                        PipView(state: .idle, size: 70)
                        Text("Read a page to Pip and your reading shows up here.")
                            .font(.pip(17, .semibold))
                            .foregroundStyle(Palette.textSoft)
                    }
                }
            }
            ForEach(log.sessions) { s in
                GlassCard(colors: Palette.grapeCard, radius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.bookTitle).font(.pip(18, .bold)).foregroundStyle(.white)
                            Spacer()
                            Text(s.date, style: .date).font(.pip(13, .semibold)).foregroundStyle(.white.opacity(0.7))
                        }
                        Text("\(s.wordsCorrect) of \(s.wordsTotal) words  ·  \(s.pages) \(s.pages == 1 ? "page" : "pages")"
                             + (s.wcpm.map { "  ·  \(Int($0)) words a minute" } ?? ""))
                            .font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.85))
                        if let sound = s.trickySound {
                            Text("Practicing: \(sound)" + (s.trickyWords.isEmpty ? "" : " (\(s.trickyWords.prefix(3).joined(separator: ", ")))"))
                                .font(.pip(14, .semibold)).foregroundStyle(Palette.sun)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ icon: String, _ colors: [Color], _ value: String, _ label: String) -> some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Orb(systemImage: icon, colors: colors, size: 40)
                Text(value).font(.pip(28, .bold)).foregroundStyle(.white).contentTransition(.numericText())
                Text(label).font(.pip(14, .semibold)).foregroundStyle(Palette.textSoft)
            }
        }
    }
}

// MARK: Stickers

struct StickersTabView: View {
    @Environment(Session.self) private var session

    var body: some View {
        let r = session.rewards
        TabPage {
            HStack {
                Text("Stickers").font(.pip(30, .bold)).foregroundStyle(.white)
                Spacer()
                StatsPill()
            }
            GlassCard(colors: Palette.berryCard, radius: 30, padding: 22) {
                VStack(spacing: 12) {
                    PipView(state: .celebrating, size: 150)
                    Text("\(r.stageName) Pip").font(.pip(26, .bold)).foregroundStyle(.white)
                    if let left = r.starsToNextStage {
                        Text("\(left) more \(left == 1 ? "star" : "stars") until Pip grows!")
                            .font(.pip(16, .semibold)).foregroundStyle(.white.opacity(0.85))
                        TrackBar(value: r.stageProgress).frame(maxWidth: 260)
                    } else {
                        Text("Pip is all grown up. You did it!")
                            .font(.pip(16, .semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(1...4, id: \.self) { stage in
                    let unlocked = r.stage >= stage
                    GlassCard(radius: 24, padding: 14) {
                        VStack(spacing: 8) {
                            PipView(state: .idle, size: 80, stage: stage)
                                .saturation(unlocked ? 1 : 0)
                                .brightness(unlocked ? 0 : -0.25)
                                .opacity(unlocked ? 1 : 0.5)
                                .overlay(alignment: .topTrailing) {
                                    if !unlocked {
                                        Orb(systemImage: "lock.fill", colors: [Color(hex: 0x8C93C9), Color(hex: 0x4A5091)], size: 30)
                                            .offset(x: 10, y: -4)
                                    }
                                }
                            Text(RewardState.stageNames[stage - 1]).font(.pip(17, .bold)).foregroundStyle(.white)
                            Text(unlocked ? "Unlocked" : "\(RewardState.stageThresholds[stage - 1]) stars")
                                .font(.pip(13, .semibold)).foregroundStyle(unlocked ? Palette.mint : Palette.textSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            SectionHeader(title: "How to earn stars")
            GlassCard(radius: 24, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    earn("book.fill", Palette.blueOrb, "Read a page to Pip", "up to 12")
                    earn("hand.raised.fill", Palette.pinkOrb, "Catch Pip's mistake", "8")
                    earn("theatermasks.fill", Palette.purpleOrb, "Teach Pip to read with feeling", "10")
                }
            }
        }
    }

    private func earn(_ icon: String, _ colors: [Color], _ title: String, _ stars: String) -> some View {
        HStack(spacing: 12) {
            Orb(systemImage: icon, colors: colors, size: 38)
            Text(title).font(.pip(16, .semibold)).foregroundStyle(.white)
            Spacer()
            Label(stars, systemImage: "star.fill").font(.pip(15, .bold)).foregroundStyle(Palette.sun)
        }
    }
}

// MARK: Name

struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(spacing: 18) {
            PipView(state: .idle, size: 100)
            Text("Hi! I'm Pip. What's your name?")
                .font(.pip(22, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            TextField("Your first name", text: $name)
                .font(.pip(22, .semibold))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.12)))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(save)
            BigButton("Let's read!", systemImage: "book.fill", action: save)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipBackdrop().ignoresSafeArea())
    }

    private func save() {
        Settings.shared.childName = name.trimmingCharacters(in: .whitespaces)
        dismiss()
    }
}
