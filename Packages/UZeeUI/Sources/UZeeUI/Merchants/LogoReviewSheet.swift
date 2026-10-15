import SwiftUI
import UZeeCore

/// Settings › "Find logos" flow: scans transactions for brand names, fetches logos online,
/// lets the user apply each one to all past and future transactions from that payee.
struct LogoReviewSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss

    enum Phase { case scanning, fetching, review, done }

    @State private var phase: Phase = .scanning
    @State private var candidates: [LogoCandidate] = []

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    VStack(spacing: UZSpacing.l) {
                        ProgressView()
                        Text("Reading your transactions…").foregroundStyle(UZColor.label2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .fetching:
                    VStack(spacing: UZSpacing.l) {
                        ProgressView()
                        Text("Searching for logos…").foregroundStyle(UZColor.label2)
                        Text("Only brand names are sent — no amounts or accounts.").font(.caption).foregroundStyle(UZColor.label3).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    reviewList
                case .done:
                    VStack(spacing: UZSpacing.l) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(UZColor.positive)
                        Text("Logos saved").font(.title3.bold())
                        Text("They'll appear next to transactions and on the calendar.").foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Find logos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await scan() }
    }

    // MARK: Review list

    private var reviewList: some View {
        let visible = candidates.filter { !$0.skipped }
        return Group {
            if visible.isEmpty {
                VStack(spacing: UZSpacing.l) {
                    Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(UZColor.label3)
                    Text("No new logos found").font(.title3.bold())
                    Text("UZee searched for logos for your merchants but didn't find any it could use.")
                        .foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(visible.indices, id: \.self) { i in
                            let idx = candidates.firstIndex(where: { $0.id == visible[i].id })!
                            candidateRow(index: idx)
                        }
                    } footer: {
                        Text("Logos apply to all past and future transactions from each source.")
                            .font(.caption).foregroundStyle(UZColor.label3)
                    }
                    Section {
                        Button("Use all") { applyAll() }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(UZColor.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateRow(index: Int) -> some View {
        let candidate = candidates[index]
        HStack(spacing: UZSpacing.l) {
            logoThumbnail(candidate.logoData)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(candidate.payeeName).lineLimit(1)
                Text("\(candidate.transactionCount) transaction\(candidate.transactionCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(UZColor.label2)
            }
            Spacer()
            if candidate.isFetching {
                ProgressView().controlSize(.small)
            } else if candidate.logoData != nil {
                HStack(spacing: UZSpacing.m) {
                    Button("Use") { apply(index: index) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Skip") { candidates[index].skipped = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Text("Not found").font(.caption).foregroundStyle(UZColor.label3)
            }
        }
        .padding(.vertical, UZSpacing.xxs)
    }

    @ViewBuilder
    private func logoThumbnail(_ data: Data?) -> some View {
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(UZColor.label3.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay { Image(systemName: "photo").foregroundStyle(UZColor.label3) }
        }
    }

    // MARK: Actions

    private func apply(index: Int) {
        let candidate = candidates[index]
        guard let data = candidate.logoData else { return }
        try? session.calendar.saveMerchantLogo(candidate.payeeName, data, candidate.sourceURL)
        candidates[index].skipped = true
        session.reload()
        let remaining = candidates.filter { !$0.skipped && $0.logoData != nil }
        if remaining.isEmpty { phase = .done }
    }

    private func applyAll() {
        for i in candidates.indices where !candidates[i].skipped, let data = candidates[i].logoData {
            try? session.calendar.saveMerchantLogo(candidates[i].payeeName, data, candidates[i].sourceURL)
            candidates[i].skipped = true
        }
        session.reload()
        phase = .done
    }

    // MARK: Scan + fetch

    private func scan() async {
        phase = .scanning
        // Collect distinct payee names from transactions, sorted by frequency.
        let grouped = Dictionary(grouping: session.transactions.filter { ($0.payeeName ?? "").isEmpty == false }) { ($0.payeeName ?? "").trimmingCharacters(in: .whitespaces) }
        let alreadyHave = Set(session.merchantLogos.keys)
        var list: [LogoCandidate] = grouped
            .filter { !alreadyHave.contains($0.key.lowercased()) }
            .map { LogoCandidate(payeeName: $0.key, transactionCount: $0.value.count) }
            .sorted { $0.transactionCount > $1.transactionCount }
            .prefix(40).map { $0 }

        // Also add recurring item names not already covered.
        let recurringNames = session.recurring.items.map(\.name)
        for name in recurringNames where !alreadyHave.contains(name.lowercased()) && !list.contains(where: { $0.payeeName.caseInsensitiveCompare(name) == .orderedSame }) {
            list.append(LogoCandidate(payeeName: name, transactionCount: 0))
        }

        candidates = list
        phase = .fetching

        await withTaskGroup(of: (Int, Data?, String?).self) { group in
            for (i, candidate) in candidates.enumerated() {
                group.addTask {
                    let result = await LogoFetchService.shared.fetch(payeeName: candidate.payeeName)
                    return (i, result?.data, result?.sourceURL)
                }
            }
            for await (i, data, url) in group {
                candidates[i].logoData = data
                candidates[i].sourceURL = url
            }
        }

        phase = .review
    }
}

/// Small inline logo view used in calendar rows.
struct MerchantLogoView: View {
    let data: Data
    var size: CGFloat = 24

    var body: some View {
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        }
    }
}
