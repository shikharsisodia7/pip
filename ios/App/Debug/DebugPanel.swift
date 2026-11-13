import SwiftUI
import PipKit

/// Operator panel: mic test, server and mock settings, demo path, phase jumps,
/// and the actions each screen registers.
struct DebugPanel: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var urlText = Settings.shared.baseURL.absoluteString
    @State private var micError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Microphone") {
                    Meter(value: Double(MicHub.shared.level), label: "Input level", tone: .accent)
                    Button(MicHub.shared.isRunning ? "Stop mic test" : "Start mic test") { toggleMic() }
                    if let micError { Text(micError).foregroundStyle(.red) }
                }
                Section("Server") {
                    Toggle("Mock mode (no network)", isOn: $settings.mock)
                    TextField("Server URL", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { if let u = URL(string: urlText) { settings.baseURL = u } }
                    Picker("Live listener", selection: $settings.listenerKind) {
                        ForEach(ListenerKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Demo") {
                    Picker("Path", selection: $settings.demoPath) {
                        ForEach(DemoPath.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Jump to", selection: Binding(get: { session.phase }, set: { session.goto($0) })) {
                        ForEach(Phase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Stepper(value: $settings.expressionThreshold, in: 1...3, step: 0.05) {
                        Text("Expression threshold \(settings.expressionThreshold, specifier: "%.2f")")
                    }
                    Button("Reset session", role: .destructive) { session.reset(); dismiss() }
                }
                if !session.debugActions.isEmpty {
                    Section("Screen actions") {
                        ForEach(session.debugActions) { action in
                            Button(action.label) { action.run(); dismiss() }
                        }
                    }
                }
                if !session.debug.isEmpty {
                    Section("State") {
                        ForEach(session.debug.sorted { $0.key < $1.key }, id: \.key) { item in
                            LabeledContent(item.key, value: item.value)
                        }
                    }
                }
            }
            .navigationTitle("Debug")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func toggleMic() {
        if MicHub.shared.isRunning { MicHub.shared.stop(); return }
        Task {
            guard await AudioSessionManager.shared.requestMic() else {
                micError = "Microphone permission is off."
                return
            }
            do { try MicHub.shared.start(); micError = nil } catch { micError = "Mic unavailable: \(error)" }
        }
    }
}
