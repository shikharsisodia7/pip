import SwiftUI
import PipKit

extension View {
    /// Long press the top left corner to open the debug panel.
    func debugHotZone() -> some View { modifier(DebugHotZone()) }
}

private struct DebugHotZone: ViewModifier {
    @Environment(Session.self) private var session
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 80, height: 80)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.8) { open = true }
            }
            .sheet(isPresented: $open) {
                DebugPanel().environment(session)
            }
    }
}
