import SwiftUI
import PipKit

/// Glossy round button: gradient orb, white symbol, soft top highlight.
struct OrbButton: View {
    let systemImage: String
    var colors: [Color] = Palette.blueOrb
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) { Orb(systemImage: systemImage, colors: colors, size: size) }
            .buttonStyle(SquishStyle())
    }
}

struct Orb: View {
    let systemImage: String
    var colors: [Color] = Palette.blueOrb
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                .padding(size * 0.06)
            Circle().stroke(.white.opacity(0.25), lineWidth: 1.5)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: (colors.last ?? .black).opacity(0.5), radius: 8, y: 5)
    }
}

/// Round category icon with a small label under it.
struct CategoryButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Orb(systemImage: systemImage, colors: colors, size: 62)
                Text(title)
                    .font(.pip(13, .semibold))
                    .foregroundStyle(Palette.textSoft)
            }
        }
        .buttonStyle(SquishStyle())
    }
}

/// Gentle press-down scale for tappable cards and orbs.
struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Rounded gradient card with a glassy rim.
struct GlassCard<Content: View>: View {
    var colors: [Color] = [Palette.surfaceHigh, Palette.surface]
    var radius: CGFloat = 28
    var padding: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }
}

/// "67%" pill with a small progress ring, like a course card badge.
struct ProgressPill: View {
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Int((value * 100).rounded()))%")
                .font(.pip(15, .bold))
                .foregroundStyle(.white)
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 3.5)
                Circle().trim(from: 0, to: max(0.02, value))
                    .stroke(Palette.mint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.25), in: Capsule())
    }
}

/// Glass pill of small stats: stars, pages, level.
struct StatsPill: View {
    @Environment(Session.self) private var session

    var body: some View {
        let r = session.rewards
        HStack(spacing: 14) {
            stat("star.fill", Palette.sun, "\(r.stars)")
                .symbolEffect(.bounce, value: r.gainCount)
            stat("book.fill", Palette.mint, "\(Library.shared.totalPagesRead)")
            stat("crown.fill", Palette.pink, r.stageName)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Palette.glass))
        .overlay(Capsule().strokeBorder(Palette.stroke))
        .animation(.spring, value: r.stars)
    }

    private func stat(_ icon: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).foregroundStyle(.white).contentTransition(.numericText())
        }
        .font(.pip(15, .bold))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.pip(20, .bold)).foregroundStyle(.white)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).font(.pip(15, .semibold)).foregroundStyle(Palette.accent)
            }
        }
    }
}

/// Thin rounded progress track used in top bars.
struct TrackBar: View {
    let value: Double
    var colors: [Color] = [Palette.sun, Palette.orange]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 10)
        .animation(.spring, value: value)
    }
}

/// Book cover tile: emoji scene on the page's soft color.
struct SceneTile: View {
    let scene: PageScene
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(hexString: scene.bg) ?? Palette.paper)
            Text(scene.emoji.split(separator: " ").prefix(2).joined())
                .font(.system(size: size * 0.36))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
    }
}

/// Small translucent chip with an icon, for book facts.
struct MetaChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            Text(text).font(.pip(12, .bold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.16), in: Capsule())
    }
}

/// A row of page dots: read pages are checked, the next page glows.
struct PagePath: View {
    let pages: Int
    let done: Set<Int>
    let next: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<pages, id: \.self) { i in
                if i > 0 {
                    Capsule()
                        .fill(done.contains(i - 1) ? Palette.mint : .white.opacity(0.22))
                        .frame(width: 10, height: 4)
                }
                node(i)
            }
        }
    }

    @ViewBuilder private func node(_ i: Int) -> some View {
        let isDone = done.contains(i)
        let isNext = i == next && !isDone
        ZStack {
            Circle()
                .fill(isDone ? AnyShapeStyle(LinearGradient(colors: Palette.mintOrb, startPoint: .top, endPoint: .bottom))
                      : isNext ? AnyShapeStyle(LinearGradient(colors: [Palette.sun, Palette.orange], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(.white.opacity(0.18)))
            Circle().strokeBorder(.white.opacity(isNext ? 0.9 : 0.25), lineWidth: isNext ? 2.5 : 1)
            if isDone {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
            } else {
                Text("\(i + 1)").font(.pip(13, .bold)).foregroundStyle(isNext ? Palette.ink : .white.opacity(0.7))
            }
        }
        .frame(width: isNext ? 32 : 26, height: isNext ? 32 : 26)
        .shadow(color: isNext ? Palette.sun.opacity(0.7) : .clear, radius: 8)
    }
}

/// Book row card: gradient, title, level and minutes, cover tile and progress.
struct BookCard: View {
    let book: Book
    let progress: Double
    let colors: [Color]

    var body: some View {
        GlassCard(colors: colors, radius: 26, padding: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.pip(19, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        MetaChip(systemImage: "chart.bar.fill", text: "Level \(book.level)")
                        MetaChip(systemImage: "book.pages.fill", text: "\(book.pages.count) pages")
                        MetaChip(systemImage: "clock.fill", text: "\(book.minutes) min")
                    }
                    if progress > 0 {
                        TrackBar(value: progress, colors: [Palette.mint, Color(hex: 0x23A884)])
                            .frame(maxWidth: 160)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                SceneTile(scene: book.pages.first?.scene ?? PageScene(emoji: "📖", bg: "#e6ebff"), size: 76)
                    .rotationEffect(.degrees(4))
            }
        }
    }
}
