import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UZeeCore

/// Receipts on a transaction (ATT-001…004): photos from the camera or library and PDFs from Files.
/// Photos are re-encoded as JPEG, which also drops location and other metadata.
struct ReceiptsSection: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var receipts: [ReceiptFile] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingCamera = false
    @State private var showingFiles = false
    @State private var previewURL: URL?
    @State private var removing: ReceiptFile?

    var body: some View {
        Section {
            ForEach(receipts) { receipt in
                Button { previewURL = session.activity.fileURL(receipt) } label: {
                    HStack(spacing: UZSpacing.l) {
                        ReceiptThumbnail(url: session.activity.fileURL(receipt), kind: receipt.kind)
                        VStack(alignment: .leading) {
                            Text(receipt.kind == .pdf ? "PDF" : "Photo").foregroundStyle(UZColor.label)
                            Text(ByteCountFormatter.string(fromByteCount: receipt.byteCount, countStyle: .file))
                                .font(.footnote).foregroundStyle(UZColor.label2)
                        }
                    }
                }
                .accessibilityLabel(receipt.kind == .pdf ? "Receipt PDF" : "Receipt photo")
                .accessibilityIdentifier("receipt.\(receipt.kind.rawValue)")
                .swipeActions { Button("Remove", role: .destructive) { removing = receipt } }
                .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { removing = receipt } }
            }
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo", systemImage: "camera") { showingCamera = true }
                }
                Button("Choose photo", systemImage: "photo") { showingPhotos = true }
                Button("Choose PDF from Files", systemImage: "doc") { showingFiles = true }
            } label: {
                Label("Attach receipt", systemImage: "paperclip")
            }
            .accessibilityIdentifier("receipt.attach")
        } header: {
            Text("Receipts")
        }
        .onAppear(perform: load)
        .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                addPhoto(data)
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            add(.pdf, try? Data(contentsOf: url))
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in addPhoto(image?.jpegData(compressionQuality: 0.8)) }
                .ignoresSafeArea()
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Remove this receipt?", isPresented: removingBinding, titleVisibility: .visible, presenting: removing) { receipt in
            Button("Remove", role: .destructive) {
                if session.perform("Couldn't remove the receipt. Try again.", { try session.activity.removeAttachment(receipt.id) }) {
                    load()
                }
            }
        } message: { _ in
            Text("The file is deleted from UZee.")
        }
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func load() {
        receipts = (try? session.activity.attachments(transactionID)) ?? []
    }

    /// Re-encodes as JPEG at most 2,400 px on the long side.
    private func addPhoto(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            session.errorMessage = "Couldn't read that photo. Try another one."
            return
        }
        add(.photo, image.resizedForReceipt().jpegData(compressionQuality: 0.8))
    }

    private func add(_ kind: ReceiptFile.Kind, _ data: Data?) {
        guard let data, !data.isEmpty else {
            session.errorMessage = "Couldn't read that file. Try another one."
            return
        }
        guard Int64(data.count) <= ReceiptFile.maxBytes else {
            session.errorMessage = "That file is too large. Receipts can be up to 20 MB."
            return
        }
        if session.perform("Couldn't attach the receipt. Try again.", { _ = try session.activity.addAttachment(transactionID, kind, data) }) {
            session.toasts.show("Receipt attached")
            load()
        }
    }
}

/// Small preview: the photo itself, or a document icon for PDFs.
struct ReceiptThumbnail: View {
    let url: URL?
    let kind: ReceiptFile.Kind

    var body: some View {
        Group {
            if kind == .photo, let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: kind == .pdf ? "doc.richtext" : "photo")
                    .font(.title2).foregroundStyle(UZColor.label2)
            }
        }
        .frame(width: 44, height: 44)
        .background(UZColor.fill)
        .clipShape(.rect(cornerRadius: UZRadius.badge, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension UIImage {
    func resizedForReceipt(maxSide: CGFloat = 2_400) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// The system camera, for "Take photo".
struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.completion(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Tags on a transaction (CAT-006): shown as chips, edited in a sheet.
struct TagsSection: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var editing = false

    var body: some View {
        Section {
            Button { editing = true } label: {
                HStack {
                    Text("Tags").foregroundStyle(UZColor.label)
                    Spacer()
                    Text(current.isEmpty ? "None" : current.map { "#" + $0.name }.joined(separator: " "))
                        .foregroundStyle(UZColor.label2).lineLimit(1)
                }
            }
            .accessibilityIdentifier("detail.tags")
        }
        .sheet(isPresented: $editing) {
            NavigationStack { TagPickerView(session: session, transactionID: transactionID) }
        }
    }

    private var current: [MoneyTag] {
        let ids = session.tagMap[transactionID] ?? []
        return session.tags.filter { ids.contains($0.id) }
    }
}

struct TagPickerView: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var selection: Set<UUID> = []
    @State private var name = ""
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New tag", text: $name).onSubmit(create).accessibilityIdentifier("tagPicker.name")
                    Button("Add", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("tagPicker.add")
                }
                if let problem { Text(problem).foregroundStyle(UZColor.negative) }
            }
            Section {
                ForEach(session.tags) { tag in
                    Button {
                        if selection.contains(tag.id) { selection.remove(tag.id) } else { selection.insert(tag.id) }
                    } label: {
                        HStack {
                            Text("#" + tag.name).foregroundStyle(UZColor.label)
                            Spacer()
                            if selection.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(UZColor.tint) }
                        }
                    }
                    .accessibilityIdentifier("tagPicker.\(tag.name)")
                    .accessibilityAddTraits(selection.contains(tag.id) ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if session.perform("Couldn't save the tags. Try again.", { try session.activity.setTags(selection, transactionID) }) {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("tagPicker.done")
            }
        }
        .onAppear { selection = session.tagMap[transactionID] ?? [] }
    }

    private func create() {
        do {
            let tag = try session.activity.createTag(name)
            selection.insert(tag.id)
            name = ""
            problem = nil
            session.reload()
        } catch {
            problem = CategoryProblemText.text(error)
        }
    }
}
