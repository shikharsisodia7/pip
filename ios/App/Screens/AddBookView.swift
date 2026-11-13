// Add any book from home: snap or pick photos of its pages (text is read on
// device with Vision), or type and paste the words. Pages are split into
// reading-sized chunks and saved to the library.

import PhotosUI
import PipKit
import SwiftUI
import Vision

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var scanning = false
    @State private var showCamera = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Book title") {
                        TextField("For example: Frog and Toad", text: $title)
                            .font(.pip(19, .semibold))
                    }

                    HStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            scanButton("Snap a page", "camera.fill", Palette.blueOrb) { showCamera = true }
                        }
                        PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                            scanLabel("Pick photos", "photo.on.rectangle", Palette.purpleOrb)
                        }
                        .buttonStyle(SquishStyle())
                    }

                    if scanning {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Reading the page…").font(.pip(15, .semibold)).foregroundStyle(Palette.textSoft)
                        }
                    }
                    if let note {
                        Text(note).font(.pip(14, .semibold)).foregroundStyle(Palette.sun)
                    }

                    field("The words") {
                        TextEditor(text: $text)
                            .font(.pip(18))
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                    }

                    let preview = Book.fromText(title: title, text: text)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("\(preview.pages.count) \(preview.pages.count == 1 ? "page" : "pages"), \(preview.wordCount) words")
                            .font(.pip(14, .semibold))
                            .foregroundStyle(Palette.textSoft)
                    }

                    BigButton("Add to my books", systemImage: "plus") { save() }
                        .disabled(preview.pages.isEmpty)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(PipBackdrop().ignoresSafeArea())
            .navigationTitle("Add a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onChange(of: picks) { Task { await readPicks() } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await recognize([image]) } }.ignoresSafeArea()
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.pip(15, .bold)).foregroundStyle(Palette.textSoft)
            content()
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.stroke))
        }
    }

    private func scanButton(_ title: String, _ icon: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) { scanLabel(title, icon, colors) }.buttonStyle(SquishStyle())
    }

    private func scanLabel(_ title: String, _ icon: String, _ colors: [Color]) -> some View {
        HStack(spacing: 10) {
            Orb(systemImage: icon, colors: colors, size: 38)
            Text(title).font(.pip(16, .bold)).foregroundStyle(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.glass))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.stroke))
    }

    private func readPicks() async {
        var images: [UIImage] = []
        for item in picks {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
        }
        picks = []
        await recognize(images)
    }

    private func recognize(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        scanning = true
        note = nil
        var found: [String] = []
        for img in images {
            if let t = await Self.ocr(img), !t.isEmpty { found.append(t) }
        }
        scanning = false
        if found.isEmpty {
            note = "Pip could not find words in that photo. Try a closer, brighter picture."
        } else {
            text = ([text] + found).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    /// On-device text recognition, lines joined into paragraphs.
    private static func ocr(_ image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { c in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                c.resume(returning: lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cg, orientation: .init(image.imageOrientation)).perform([request])
                } catch {
                    c.resume(returning: nil)
                }
            }
        }
    }

    private func save() {
        let book = Book.fromText(title: title, text: text)
        guard !book.pages.isEmpty else { return }
        Library.shared.add(book)
        dismiss()
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// System camera for snapping a book page.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
