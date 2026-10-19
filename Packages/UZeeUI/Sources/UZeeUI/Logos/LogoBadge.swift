import PhotosUI
import SwiftUI
import UZeeCore

/// The round logo next to the amount on an entry's page (owner, 2026-10-19). With no logo it shows the same icon
/// as in Activity; tapping it offers Search online or Choose from Photos. With a logo, a small trash button
/// removes it. Saved per brand, so every entry from that payee, past and future, gets the same logo.
struct LogoBadge<Fallback: View>: View {
    let name: String
    var size: CGFloat = 64
    @ViewBuilder let fallback: () -> Fallback
    @State private var store = LogoStore.shared
    @State private var choosing = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var finding = false
    @State private var found: LogoFinder.Found?
    @State private var notFound = false
    @State private var confirmRemove = false

    private var brand: String? { store.savedBrand(in: name) ?? LogoStore.brand(name) }
    private var image: UIImage? { store.image(for: name) }

    var body: some View {
        if let brand {
            ZStack(alignment: .topTrailing) {
                Button { if image == nil { choosing = true } } label: { circle }
                    .buttonStyle(.plain)
                    .disabled(finding)
                    .accessibilityLabel(image == nil ? "Add a logo for \(name)" : "Logo for \(name)")
                    .accessibilityIdentifier("logo.badge")
                if image != nil {
                    Button { confirmRemove = true } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: size * 0.34))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, UZColor.negative)
                    }
                    .buttonStyle(.plain)
                    .offset(x: size * 0.12, y: -size * 0.08)
                    .accessibilityLabel("Remove the logo")
                    .accessibilityIdentifier("logo.remove")
                }
            }
            .confirmationDialog("Add a logo for \(name)", isPresented: $choosing, titleVisibility: .visible) {
                Button("Search online") { search(brand) }
                    .accessibilityIdentifier("logo.find")
                Button("Choose from Photos") { pickingPhoto = true }
                    .accessibilityIdentifier("logo.photos")
            } message: {
                Text("It's used for every entry from \(name), past and future.")
            }
            .confirmationDialog("Remove the logo?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { store.remove(brand) }
                    .accessibilityIdentifier("logo.confirmRemove")
            } message: {
                Text("Every entry from \(name) goes back to its usual icon.")
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) {
                guard let photo else { return }
                Task {
                    if let data = try? await photo.loadTransferable(type: Data.self), let png = LogoSection.small(data) {
                        store.save(brand, domain: "From Photos", png: png)
                    }
                    self.photo = nil
                }
            }
            .sheet(item: $found) { found in
                FoundLogoSheet(found: found, name: name) {
                    store.save(brand, domain: found.domain, png: found.png)
                }
            }
            .alert("No logo found online", isPresented: $notFound) {
                Button("Choose from Photos") { pickingPhoto = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text("UZee couldn't find a logo for \(name). You can pick one from Photos.")
            }
        } else {
            fallback().frame(width: size, height: size)
        }
    }

    private var circle: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(Color.white, in: .circle)
                    .overlay(Circle().stroke(UZColor.label3.opacity(0.3), lineWidth: 0.5))
            } else {
                fallback()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            }
            if finding { ProgressView().frame(width: size, height: size).background(.ultraThinMaterial, in: .circle) }
        }
    }

    private func search(_ brand: String) {
        Task {
            finding = true
            let result = await LogoFinder.find(brand, shownName: name)
            finding = false
            if let result { found = result } else { notFound = true }
        }
    }
}

/// What the online search found: the logo and its site, with Use.
private struct FoundLogoSheet: View {
    let found: LogoFinder.Found
    let name: String
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: UZSpacing.l) {
                if let image = UIImage(data: found.png) {
                    Image(uiImage: image).resizable().scaledToFit().padding(14)
                        .frame(width: 96, height: 96)
                        .background(Color.white, in: .circle)
                        .overlay(Circle().stroke(UZColor.label3.opacity(0.3), lineWidth: 0.5))
                }
                Text(found.domain).font(.headline)
                Text("Use this logo for \(name)?").foregroundStyle(UZColor.label2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Logo found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("logo.use")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
