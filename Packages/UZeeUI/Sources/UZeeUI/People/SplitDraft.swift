import SwiftUI
import UZeeCore

/// The split being edited, independent of the amount so the total can still change (SPL-03/04).
struct SplitDraft: Equatable, Sendable {
    var groupID: UUID?
    /// Everyone who can take part (the group or the people chosen), "You" first.
    var members: [UUID]
    /// Who shares this one (an equal split can leave someone out).
    var participants: [UUID]
    var method: SplitMethod = .equal
    /// One payer (or receiver, for income) of the whole amount; nil when several people paid.
    var payer: UUID?
    /// Several payers: minor units each.
    var paidAmounts: [UUID: Int64] = [:]
    /// Exact minor units, basis points or weights, by method.
    var inputs: [UUID: Int64] = [:]

    init(groupID: UUID? = nil, participants: [UUID], method: SplitMethod = .equal, payer: UUID?) {
        self.groupID = groupID
        self.members = participants
        self.participants = participants
        self.method = method
        self.payer = payer
    }

    /// The draft for an existing split, to edit it.
    init(_ split: Split) {
        groupID = split.groupID
        participants = split.shares.map(\.personID)
        members = split.people
        method = split.method
        if split.payers.count == 1 { payer = split.payers[0].personID } else {
            payer = nil
            paidAmounts = Dictionary(split.payers.map { ($0.personID, $0.amount.minorUnits) }, uniquingKeysWith: +)
        }
        inputs = Dictionary(split.shares.compactMap { share in share.input.map { (share.personID, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    func shares(total: Money) throws(SplitProblem) -> [SplitShare] {
        try SplitCalculator.shares(total: total, method: method, participants: participants, inputs: inputs,
                                   firstPayer: payer ?? participants.first { (paidAmounts[$0] ?? 0) > 0 })
    }

    func payers(total: Money) -> [SplitPayer] {
        if let payer { return [SplitPayer(personID: payer, amount: total)] }
        return participants.compactMap { person in
            guard let amount = paidAmounts[person], amount > 0 else { return nil }
            return SplitPayer(personID: person, amount: Money(minorUnits: amount, currency: total.currency))
        }
    }

    /// The split to save; throws when it doesn't add up (save stays blocked, SPL-04).
    func build(total: Money, transactionID: UUID) throws(SplitProblem) -> Split {
        let split = Split(transactionID: transactionID, groupID: groupID, method: method, payers: payers(total: total),
                          shares: try shares(total: total))
        try split.validate(total: total)
        return split
    }
}

/// Words for splits and balances, in one place.
enum SplitText {
    static func problem(_ problem: SplitProblem) -> String {
        switch problem {
        case .noParticipants: "Choose who shares this."
        case .invalidInput: "Check the amounts. They can't be negative."
        case .totalsDontMatch(let remaining):
            remaining.isNegative ? "The amounts are \(MoneyFormatter.string(Money(minorUnits: -remaining.minorUnits, currency: remaining.currency))) more than the total."
                                 : "\(MoneyFormatter.string(remaining)) still to assign."
        case .percentNot100(let bps): bps > 0 ? "\(percent(bps)) still to assign." : "The percentages add up to more than 100%."
        case .paidDoesNotMatch(let remaining):
            remaining.isNegative ? "Paid amounts are more than the total." : "\(MoneyFormatter.string(remaining)) of the payment still to assign."
        case .overflow: "That amount is too large."
        }
    }

    static func percent(_ bps: Int64) -> String {
        let whole = bps / 100
        let fraction = bps % 100
        return fraction == 0 ? "\(whole)%" : "\(whole).\(fraction < 10 ? "0" : "")\(fraction)%"
    }

    /// "owes you" / "you owe" / "settled" for a balance seen from my side.
    static func word(_ balance: Money) -> String {
        balance.minorUnits > 0 ? "owes you" : balance.minorUnits < 0 ? "you owe" : "settled"
    }

    static func magnitude(_ money: Money) -> Money {
        Money(minorUnits: money.minorUnits.magnitudeClamped, currency: money.currency)
    }

    static func color(_ balance: Money) -> Color {
        balance.minorUnits > 0 ? UZColor.positive : balance.minorUnits < 0 ? UZColor.negative : UZColor.label2
    }
}

/// Round avatar with the person's initial, tinted per name.
struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 36

    private static let palette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .green, .brown]

    var body: some View {
        let initial = Person(name: name).initial
        let index = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.palette.count
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[index].gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

/// Round tile with a group's icon.
struct GroupTile: View {
    let icon: GroupIcon
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon.symbolName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: icon.colorHex).gradient, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
