import SwiftUI

/// Status pill: always a word plus a symbol, never colour alone (A11Y-03, UI-006).
public struct StatusBadge: View {
    public enum Status: String, CaseIterable, Sendable {
        case paid, overdue, dueToday, dueSoon, estimated, paused, skipped, cancelled, pending
        case owesYou, youOwe, settled

        public var text: String {
            switch self {
            case .paid: "Paid"
            case .overdue: "Overdue"
            case .dueToday: "Due today"
            case .dueSoon: "Due soon"
            case .estimated: "Estimated"
            case .paused: "Paused"
            case .skipped: "Skipped"
            case .cancelled: "Cancelled"
            case .pending: "Pending"
            case .owesYou: "owes you"
            case .youOwe: "you owe"
            case .settled: "settled"
            }
        }

        public var symbol: String {
            switch self {
            case .paid, .settled: "checkmark"
            case .overdue, .youOwe: "exclamationmark"
            case .dueToday, .dueSoon, .pending: "clock"
            case .estimated: "questionmark"
            case .paused: "pause"
            case .skipped: "forward.end"
            case .cancelled: "xmark"
            case .owesYou: "arrow.down.left"
            }
        }

        var color: Color {
            switch self {
            case .paid, .owesYou: UZColor.positive
            case .overdue, .youOwe: UZColor.negative
            case .dueToday, .dueSoon, .estimated: UZColor.warning
            case .paused, .skipped, .cancelled, .pending, .settled: UZColor.label2
            }
        }
    }

    let status: Status

    public init(_ status: Status) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: UZSpacing.xxs) {
            Image(systemName: status.symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(status.text)
        }
        .font(.caption2.bold())
        .foregroundStyle(status.color)
        .padding(.vertical, UZSpacing.xxs)
        .padding(.horizontal, UZSpacing.m)
        .background(status.color.opacity(0.15), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status badges") {
    VStack(alignment: .leading) {
        ForEach(StatusBadge.Status.allCases, id: \.self) { StatusBadge($0) }
    }
    .padding()
}
