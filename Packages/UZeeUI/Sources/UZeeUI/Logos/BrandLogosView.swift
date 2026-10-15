import SwiftUI
import UZeeCore

/// Settings › Brand logos (owner, 2026-10-15): "Find logos" reads the shops, apps and companies in your transactions and
/// bills, looks each up online, and shows what it found to tick. A ticked logo shows on every transaction and bill from
/// that source, before and after today. Nothing is changed until you tap Use.
struct BrandLogosView: View {
    @Bindable var session: AppSession
    @State private var store = LogoStore.shared
    @State private var askingPermission = false
    @State private var searching = false
    @State private var checked = 0
    @State private var total = 0
    @State private var found: [LogoFinder.Found] = []
    @State private var chosen: Set<String> = []
    @State private var notFound = 0
    @State private var finished = false

    /// Brands in transactions and bills, most used first, without people's names or ones already handled.
    private var candidates: [(brand: String, shown: String, count: Int)] {
        let people = Set(session.people.others.compactMap { LogoStore.brand($0.name) })
        var counts: [String: (shown: String, count: Int)] = [:]
        let names = session.transactions.filter { $0.deletedAt == nil && ($0.kind == .expense || $0.kind == .income) }.compactMap(\.payeeName)
            + session.recurring.items.map(\.name)
        for name in names {
            guard let brand = LogoStore.brand(name), brand.count >= 3, !people.contains(brand) else { continue }
            counts[brand, default: (name, 0)].count += 1
        }
        return counts.filter { !store.hasLogo($0.key) && !store.isSkipped($0.key) }
            .map { ($0.key, $0.value.shown, $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.brand < $1.brand }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Label("Logos for shops, apps and banks", systemImage: "photo.on.rectangle.angled").font(.headline)
                    Text("UZee reads the names in your transactions and bills, finds each brand's logo online and asks before using it. A logo you pick shows on every transaction and bill from that source, old and new.")
                        .font(.subheadline).foregroundStyle(UZColor.label2)
                }
                .padding(.vertical, UZSpacing.xs)
                if searching {
                    HStack(spacing: UZSpacing.m) {
                        ProgressView()
                        Text("Checking \(checked) of \(total)…").foregroundStyle(UZColor.label2)
                    }
                    .accessibilityIdentifier("logos.progress")
                } else {
                    let count = candidates.count
                    Button {
                        askingPermission = true
                    } label: {
                        Label(count == 0 ? "No new names to check" : "Find logos for \(count) \(count == 1 ? "name" : "names")",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(count == 0)
                    .accessibilityIdentifier("logos.find")
                }
            } footer: {
                Text("Only the names are sent (to Clearbit and Google, to find the website and its icon). Amounts and everything else stay on this iPhone.")
            }

            if !found.isEmpty {
                Section {
                    ForEach(found) { item in
                        Button {
                            if chosen.contains(item.brand) { chosen.remove(item.brand) } else { chosen.insert(item.brand) }
                        } label: {
                            HStack(spacing: UZSpacing.l) {
                                Image(systemName: chosen.contains(item.brand) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(chosen.contains(item.brand) ? UZColor.tint : UZColor.label3)
                                if let image = UIImage(data: item.png) {
                                    Image(uiImage: image).resizable().scaledToFit().padding(4).frame(width: 36, height: 36)
                                        .background(Color.white, in: .rect(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.shownName).foregroundStyle(UZColor.label).lineLimit(1)
                                    Text(item.domain).font(.caption).foregroundStyle(UZColor.label2)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("logos.found.\(item.brand)")
                    }
                } header: {
                    Text("Found \(found.count)")
                } footer: {
                    Text(notFound > 0 ? "No logo found for \(notFound) other \(notFound == 1 ? "name" : "names"); they keep their usual icon." : "")
                }
                Section {
                    Button {
                        apply()
                    } label: {
                        Text(chosen.isEmpty ? "Select the logos to use" : "Use \(chosen.count) \(chosen.count == 1 ? "logo" : "logos") for past and future")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("logos.use")
                }
            } else if finished {
                Section { Text("No logos found this time.").foregroundStyle(UZColor.label2) }
            }

            if !store.entries.isEmpty {
                Section("In use") {
                    ForEach(store.entries.keys.sorted(), id: \.self) { brand in
                        HStack(spacing: UZSpacing.l) {
                            BrandIcon(name: brand) { Color.clear.frame(width: 36, height: 36) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand.capitalized)
                                Text(store.entries[brand]?.domain ?? "").font(.caption).foregroundStyle(UZColor.label2)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { store.remove(brand) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Brand logos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Look up logos online?", isPresented: $askingPermission) {
            Button("Look up") { Task { await search() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("UZee sends only the shop and company names to Clearbit and Google to find their logos. You choose which to use.")
        }
    }

    private func search() async {
        let list = Array(candidates.prefix(60))
        searching = true
        finished = false
        checked = 0
        total = list.count
        found = []
        notFound = 0
        var missing: [String] = []
        for candidate in list {
            if let hit = await LogoFinder.find(candidate.brand, shownName: candidate.shown) {
                found.append(hit)
                chosen.insert(hit.brand)
            } else {
                missing.append(candidate.brand)
            }
            checked += 1
        }
        notFound = missing.count
        store.skip(missing)
        searching = false
        finished = true
    }

    private func apply() {
        for item in found where chosen.contains(item.brand) {
            store.save(item.brand, domain: item.domain, png: item.png)
        }
        store.skip(found.filter { !chosen.contains($0.brand) }.map(\.brand))
        let count = chosen.count
        found = []
        chosen = []
        session.toasts.show("Using \(count) \(count == 1 ? "logo" : "logos")")
    }
}
