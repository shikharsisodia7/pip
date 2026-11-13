import SwiftUI

extension Font {
    /// System rounded type at an explicit size.
    static func pip(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Story text on reading screens (at least 30pt).
    static let pipStory: Font = .system(size: 34, weight: .medium, design: .rounded)
}
