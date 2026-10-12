import SwiftUI

/// Pick a day of the month (1…31) from a small calendar-style grid, with an optional "Not fixed" choice
/// (`selection` 0). Replaces long "Day 1 … Day 31" menus.
struct DayGrid: View {
    @Binding var selection: Int
    var allowsNotFixed = true
    var identifier = "dayGrid"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: UZSpacing.xs), count: 7)

    var body: some View {
        VStack(spacing: UZSpacing.m) {
            if allowsNotFixed {
                Button { select(0) } label: {
                    Text("Not fixed").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, UZSpacing.m)
                        .foregroundStyle(selection == 0 ? Color.white : UZColor.label)
                        .background(selection == 0 ? UZColor.tint : UZColor.fill, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == 0 ? .isSelected : [])
                .accessibilityIdentifier("\(identifier).none")
            }
            LazyVGrid(columns: columns, spacing: UZSpacing.xs) {
                ForEach(1...31, id: \.self) { day in
                    Button { select(day) } label: {
                        Text("\(day)").font(.callout.weight(selection == day ? .semibold : .regular)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .aspectRatio(1, contentMode: .fit)
                            .foregroundStyle(selection == day ? Color.white : UZColor.label)
                            .background(selection == day ? UZColor.tint : Color.clear, in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Day \(day)")
                    .accessibilityAddTraits(selection == day ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).\(day)")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private func select(_ day: Int) { selection = day }
}
