// Operator check for live listening: read anything aloud, watch the partials
// arrive, then see every word with its time. Opened from the debug panel.

import SwiftUI
import PipKit

extension View {
    /// Registers the "Listen test" debug action and presents its sheet.
    func listenTestAction() -> some View { modifier(ListenTestAction()) }
}

private struct ListenTestAction: ViewModifier {
    @Environment(Session.self) private var session
    @State private var open = false
    @State private var unregister: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content
            .onAppear {
                let show = $open
                unregister = session.registerDebugAction("Listen test") {
                    // The debug panel is closing as this runs; open once it is gone.
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        show.wrappedValue = true
                    }
                }
            }
            .onDisappear { unregister?() }
            .sheet(isPresented: $open) { ListenTestView() }
    }
}

struct ListenTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listener: (any Listening)?
    @State private var result: Transcript?
    @State private var startedAt: Date?
    @State private var firstWordAfter: Double?
    @State private var stopTook: Double?
    @State private var stopping = false

    private var isListening: Bool {
        guard let l = listener else { return false }
        return l.status == .listening || l.status == .connecting
    }

    private var listenerName: String {
        if Settings.shared.mock { return "Mock listener (mock mode is on)" }
        switch Settings.shared.listenerKind {
        case .scribe: return "ElevenLabs Scribe, \(ScribeURL.model)"
        case .apple: return "Mock listener (on-device listener not built yet)"
        }
    }

    var body: some View {
        ZStack {
            Palette.backgroundGradient.ignoresSafeArea()
            HStack(alignment: .top, spacing: 20) {
                controls.frame(width: 250)
                VStack(spacing: 16) {
                    heard
                    table
                }
            }
            .padding(20)
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onChange(of: listener?.partialText ?? "") { _, text in
            if firstWordAfter == nil, !text.isEmpty, let startedAt {
                firstWordAfter = Date().timeIntervalSince(startedAt)
            }
        }
        .onDisappear {
            if let l = listener, isListening { Task { _ = await l.stop() } }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Listen test").font(.pip(26, .bold)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.pip(26)).foregroundStyle(Palette.textSoft)
                }
                .accessibilityLabel("Close")
            }
            Text(listenerName).font(.pip(14)).foregroundStyle(Palette.textSoft)
            statusPill
            if let message = listener?.errorMessage {
                Text(message).font(.pip(15, .semibold)).foregroundStyle(Palette.sun)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                MicButton(state: stopping ? .disabled : (isListening ? .listening : .idle),
                          label: isListening ? "Tap to stop" : "Tap and read",
                          size: 84) { toggle() }
                Spacer()
            }
            Meter(value: Double(MicHub.shared.level), label: "Input level", tone: .accent, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                stat("First words after", firstWordAfter)
                stat("Final words after stop", stopTook)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch listener?.status ?? .idle {
            case .idle: return (result == nil ? "Ready" : "Done", Palette.textSoft)
            case .connecting: return ("Connecting", Palette.sun)
            case .listening: return ("Listening", Palette.mint)
            case .error: return ("Stopped", Palette.orange)
            }
        }()
        return Label(text, systemImage: "circle.fill")
            .font(.pip(15, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.surfaceHigh, in: Capsule())
    }

    private func stat(_ label: String, _ seconds: Double?) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSoft)
            Spacer()
            Text(seconds.map { String(format: "%.2f s", $0) } ?? "-").monospacedDigit().foregroundStyle(Palette.text)
        }
        .font(.pip(14))
    }

    private var heard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result == nil ? "Hearing" : "Heard").font(.pip(14, .semibold)).foregroundStyle(Palette.textSoft)
                ScrollView {
                    Text(listener?.partialText.isEmpty == false ? listener!.partialText : "Read anything aloud.")
                        .font(.pip(22, .medium))
                        .foregroundStyle(listener?.partialText.isEmpty == false ? Palette.text : Palette.textSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 70)
            }
        }
    }

    private var table: some View {
        Card(padding: 16) {
            let words = result?.words ?? listener?.liveTranscript.words ?? []
            VStack(alignment: .leading, spacing: 8) {
                Text(result == nil ? "Words so far (times are estimates until you stop)" : "Final words (seconds since start)")
                    .font(.pip(14, .semibold)).foregroundStyle(Palette.textSoft)
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            Text("#"); Text("Word"); Text("Start"); Text("End"); Text("Gap before")
                        }
                        .font(.pip(13, .semibold)).foregroundStyle(Palette.textSoft)
                        ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                            let gap = i > 0 ? w.start - words[i - 1].end : nil
                            GridRow {
                                Text("\(i + 1)").foregroundStyle(Palette.textSoft)
                                Text(w.text).foregroundStyle(Palette.text)
                                Text(String(format: "%.2f", w.start))
                                Text(String(format: "%.2f", w.end))
                                Text(gap.map { String(format: "%.2f", $0) } ?? "")
                                    .foregroundStyle((gap ?? 0) >= 0.8 ? Palette.sun : Palette.textSoft)
                            }
                            .font(.pip(15).monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func toggle() {
        if let l = listener, isListening {
            stopping = true
            let tapped = Date()
            Task {
                result = await l.stop()
                stopTook = Date().timeIntervalSince(tapped)
                stopping = false
            }
        } else {
            let l = Listeners.make()
            listener = l
            result = nil
            firstWordAfter = nil
            stopTook = nil
            startedAt = Date()
            Task { await l.start() }
        }
    }
}
