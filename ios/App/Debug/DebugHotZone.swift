import SwiftUI
import PipKit

extension View {
    /// Long press the top center of the screen (around the camera) to open the debug panel.
    func debugHotZone() -> some View { modifier(DebugHotZone()) }
}

private struct DebugHotZone: ViewModifier {
    @Environment(Session.self) private var session
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Color.clear
                    .frame(width: 160, height: 44)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.8) { open = true }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $open) {
                DebugPanel().environment(session)
            }
    }
}
