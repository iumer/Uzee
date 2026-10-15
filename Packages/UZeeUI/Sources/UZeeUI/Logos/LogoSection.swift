import PhotosUI
import SwiftUI
import UZeeCore

/// "Logo" on a transaction or an account (owner, 2026-10-15): find this one name's logo online, pick an image from
/// Photos, or remove it. Saved per brand, so it shows everywhere that name appears, past and future.
struct LogoSection: View {
    let name: String
    let note: String
    @State private var store = LogoStore.shared
    @State private var finding = false
    @State private var found: LogoFinder.Found?
    @State private var notFound = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        if let brand = LogoStore.brand(name) {
            Section {
                HStack(spacing: UZSpacing.l) {
                    BrandIcon(name: name) {
                        Image(systemName: "photo").foregroundStyle(UZColor.label3)
                            .frame(width: 36, height: 36).background(UZColor.fill, in: .rect(cornerRadius: 10))
                    }
                    Text(store.hasLogo(brand) ? "Logo for \(name)" : "No logo yet").foregroundStyle(UZColor.label2)
                }
                if let found, let image = UIImage(data: found.png) {
                    HStack(spacing: UZSpacing.l) {
                        Image(uiImage: image).resizable().scaledToFit().padding(4).frame(width: 36, height: 36)
                            .background(Color.white, in: .rect(cornerRadius: 10))
                        Text(found.domain).font(.footnote).foregroundStyle(UZColor.label2)
                        Spacer()
                        Button("Use") {
                            store.save(brand, domain: found.domain, png: found.png)
                            self.found = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("logo.use")
                    }
                }
                Button {
                    Task {
                        finding = true
                        notFound = false
                        found = await LogoFinder.find(brand, shownName: name)
                        notFound = found == nil
                        finding = false
                    }
                } label: {
                    Label(finding ? "Looking online…" : "Find logo online", systemImage: "magnifyingglass")
                }
                .disabled(finding)
                .accessibilityIdentifier("logo.find")
                if notFound {
                    Text("No logo found online for \(name). Choose one from Photos instead.").font(.footnote).foregroundStyle(UZColor.label2)
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("logo.photos")
                if store.hasLogo(brand) {
                    Button("Remove logo", role: .destructive) { store.remove(brand) }
                        .accessibilityIdentifier("logo.remove")
                }
            } header: {
                Text("Logo")
            } footer: {
                Text(note)
            }
            .onChange(of: photo) {
                guard let photo else { return }
                Task {
                    if let data = try? await photo.loadTransferable(type: Data.self), let png = Self.small(data) {
                        store.save(brand, domain: "From Photos", png: png)
                    }
                    self.photo = nil
                }
            }
        }
    }

    /// A 128-point square PNG, so a large photo doesn't fill the iPhone.
    static func small(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 128
        let scale = min(side / image.size.width, side / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.pngData()
    }
}
