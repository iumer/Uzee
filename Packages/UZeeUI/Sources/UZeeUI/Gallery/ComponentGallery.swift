import SwiftUI
import UZeeCore

/// Debug-only catalogue of design-system components with mockup-dataset values (M1 technical task).
/// Used to review light/dark mode and large text before feature screens use the components.
struct ComponentGallery: View {
    @Bindable var session: AppSession
    @State private var showConfirm = false
    @State private var showSkeleton = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                SectionHeader("Alert strip")
                AlertStrip(.error, title: "1 overdue", message: "Gas bill · SNGPL Rs 3,250 · was due Mon 5 Oct",
                           actionTitle: "Pay", action: { showConfirm = true }, onDismiss: {})
                AlertStrip(.warning, title: "Personal over by Rs 1,200")

                SectionHeader("Amounts")
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        Text("Available balance").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label2)
                        AmountText(Money(major: 484_800, .pkr), font: .system(.largeTitle, weight: .bold))
                        Text("Rs 300,000 + $660 · USD at $1 = Rs 280").font(.caption).foregroundStyle(UZColor.label2)
                    }
                }
                UZCard {
                    VStack(spacing: UZSpacing.l) {
                        row("Wise", AmountText(Money(minorUnits: 52_000, currency: .usd)))
                        row("Office tea & snacks", AmountText(Money(major: 3_200, .pkr), style: .outflow))
                        row("Salary", AmountText(Money(major: 275_000, .pkr), style: .inflow))
                        row("Transfer", AmountText(Money(minorUnits: -50_000, currency: .usd), style: .transfer))
                        row("Hidden", AmountText(Money(major: 182_400, .pkr)).environment(\.uzHideAmounts, true))
                    }
                }

                SectionHeader("Status")
                FlowRow(StatusBadge.Status.allCases.map { StatusBadge($0) })

                SectionHeader("Categories")
                UZCard {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: UZSpacing.l)], spacing: UZSpacing.l) {
                        ForEach(CategoryKind.allCases, id: \.self) { kind in
                            VStack(spacing: UZSpacing.xs) {
                                CategoryTile(kind)
                                Text(kind.name).font(.caption).multilineTextAlignment(.center)
                            }
                        }
                    }
                }

                SectionHeader("Progress")
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.l) {
                        progress("Food · Rs 11,200 of Rs 15,000", 11_200.0 / 15_000)
                        progress("Utilities · Rs 13,100 of Rs 15,000", 13_100.0 / 15_000)
                        progress("Personal · over by Rs 1,200", 9_800.0 / 8_600)
                        HStack {
                            ProgressRingView(remaining: 156_626.0 / 235_000,
                                             label: "Budget left, 156,626 rupees of 235,000, 33 percent used") {
                                VStack(spacing: 0) {
                                    Text("Left").font(.caption2).foregroundStyle(UZColor.label2)
                                    Text("67%").font(.headline).monospacedDigit()
                                }
                            }
                            .frame(width: 88, height: 88)
                            Spacer()
                        }
                    }
                }

                SectionHeader("States")
                UZCard {
                    EmptyStateView("No people yet", systemImage: "person.2",
                                   description: "Add someone you lend to, borrow from or split bills with. Each person gets one balance.",
                                   actionTitle: "Add a person", action: {})
                }
                if showSkeleton { SkeletonCard() }

                SectionHeader("Actions")
                VStack(spacing: UZSpacing.l) {
                    PrimaryButton("Pay Rs 3,250") { showConfirm = true }
                        .accessibilityIdentifier("gallery.confirm")
                    Button("Show “Saved · Undo”") {
                        session.toasts.show("Saved · Gas bill") {}
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("gallery.toast")
                }
            }
            .padding(UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("Design components")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConfirm) {
            ConfirmSheet(title: "Pay Gas bill", amount: Money(major: 3_250, .pkr),
                         rows: [.init("From", "HBL"), .init("Date paid", "Today"), .init("Bill", "Gas · SNGPL")],
                         confirmTitle: "Pay Rs 3,250") {
                session.toasts.show("Paid · Gas bill") {}
            }
        }
    }

    private func row(_ title: String, _ amount: some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            amount
        }
    }

    private func progress(_ title: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.xs) {
            Text(title).font(.subheadline)
            ProgressBarView(fraction: fraction, label: title)
        }
    }
}

/// Wraps badges onto as many lines as needed.
private struct FlowRow: View {
    let items: [StatusBadge]

    init(_ items: [StatusBadge]) {
        self.items = items
    }

    var body: some View {
        FlowLayout(spacing: UZSpacing.m) {
            ForEach(items.indices, id: \.self) { items[$0] }
        }
    }
}

/// Minimal wrapping layout for chips and badges.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + lineHeight), points)
    }
}
