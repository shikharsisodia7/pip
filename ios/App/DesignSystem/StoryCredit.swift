import SwiftUI
import PipKit

/// Required on every reading screen: title, author, illustrator, publisher, license.
struct StoryCredit: View {
    private let book: Book
    private let onPaper: Bool

    /// onPaper: true when drawn on the paper story card (ink text), false on the dark background.
    init(book: Book, onPaper: Bool = false) {
        self.book = book
        self.onPaper = onPaper
    }

    var body: some View {
        Text(credit)
            .font(.pip(13))
            .foregroundStyle(onPaper ? Palette.ink.opacity(0.65) : Palette.textSoft)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var credit: String {
        var parts = ["\u{201C}\(book.title)\u{201D} by \(book.author)"]
        if !book.illustrator.isEmpty { parts[0] += ", illustrated by \(book.illustrator)" }
        if !book.publisher.isEmpty { parts.append(book.publisher) }
        if !book.license.isEmpty { parts.append(book.license) }
        return parts.joined(separator: ". ") + "."
    }
}
