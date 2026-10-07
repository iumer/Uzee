import Foundation

/// How a split divides the total (SPL-04). Raw values are stored; never rename them.
public enum SplitMethod: String, CaseIterable, Sendable, Codable {
    case equal, exact, percent, shares

    public var name: String {
        switch self {
        case .equal: "Equally"
        case .exact: "Exact amounts"
        case .percent: "Percentages"
        case .shares: "Shares"
        }
    }
}

/// Who paid (for income: who received) and how much.
public struct SplitPayer: Hashable, Sendable {
    public var personID: UUID
    public var amount: Money

    public init(personID: UUID, amount: Money) {
        self.personID = personID
        self.amount = amount
    }
}

/// One person's part. `input` is what was typed for the method: exact minor units, basis points or a
/// weight; nil for an equal split.
public struct SplitShare: Hashable, Sendable {
    public var personID: UUID
    public var input: Int64?
    public var share: Money

    public init(personID: UUID, input: Int64? = nil, share: Money) {
        self.personID = personID
        self.input = input
        self.share = share
    }
}

/// A split of one transaction (DATA_MODEL §3.15): payers and shares each add up to the transaction amount.
public struct Split: Hashable, Sendable {
    public var transactionID: UUID
    public var groupID: UUID?
    public var method: SplitMethod
    public var payers: [SplitPayer]
    public var shares: [SplitShare]

    public init(transactionID: UUID, groupID: UUID? = nil, method: SplitMethod, payers: [SplitPayer], shares: [SplitShare]) {
        self.transactionID = transactionID
        self.groupID = groupID
        self.method = method
        self.payers = payers
        self.shares = shares
    }

    public func share(of person: UUID) -> Money? { shares.first { $0.personID == person }?.share }
    public func paid(by person: UUID) -> Money? { payers.first { $0.personID == person }?.amount }
    public var people: [UUID] {
        var seen = Set<UUID>()
        return (payers.map(\.personID) + shares.map(\.personID)).filter { seen.insert($0).inserted }
    }

    /// Payers and shares must both add up to `total` exactly, in its currency (SPL-04).
    public func validate(total: Money) throws(SplitProblem) {
        guard !shares.isEmpty, !payers.isEmpty else { throw .noParticipants }
        guard payers.allSatisfy({ $0.amount.currency == total.currency && $0.amount.minorUnits > 0 }),
              shares.allSatisfy({ $0.share.currency == total.currency && $0.share.minorUnits >= 0 }) else { throw .invalidInput }
        let paid = payers.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }
        guard paid == total.minorUnits else { throw .paidDoesNotMatch(remaining: Money(minorUnits: total.minorUnits &- paid, currency: total.currency)) }
        let shared = shares.reduce(Int64(0)) { $0 &+ $1.share.minorUnits }
        guard shared == total.minorUnits else { throw .totalsDontMatch(remaining: Money(minorUnits: total.minorUnits &- shared, currency: total.currency)) }
    }
}

public enum SplitProblem: Error, Equatable, Sendable {
    case noParticipants
    case invalidInput
    /// Exact amounts don't add up; `remaining` is what is still to assign (negative = too much).
    case totalsDontMatch(remaining: Money)
    /// Percentages must add up to 100%; `remainingBasisPoints` is what is still to assign.
    case percentNot100(remainingBasisPoints: Int64)
    case paidDoesNotMatch(remaining: Money)
    case overflow
}

/// One person owes another (pairwise, from a split, loan or settlement).
public struct Debt: Hashable, Sendable {
    public var debtor: UUID
    public var creditor: UUID
    public var amount: Money

    public init(debtor: UUID, creditor: UUID, amount: Money) {
        self.debtor = debtor
        self.creditor = creditor
        self.amount = amount
    }
}

/// Split arithmetic (DATA_MODEL §4 "Splits" and "Pairwise debts"). Every result adds up to the total
/// exactly: leftover minor units are handed out deterministically, never lost or created.
public enum SplitCalculator {
    /// Shares for `participants` (in member order). `inputs` holds exact minor units, basis points or
    /// weights depending on `method`. In an equal split the leftover paisa go one each in member order,
    /// starting with `firstPayer` when they take part.
    public static func shares(total: Money, method: SplitMethod, participants: [UUID], inputs: [UUID: Int64] = [:],
                              firstPayer: UUID? = nil) throws(SplitProblem) -> [SplitShare] {
        guard !participants.isEmpty, total.minorUnits >= 0 else { throw .noParticipants }
        let currency = total.currency
        switch method {
        case .equal:
            let count = Int64(participants.count)
            let base = total.minorUnits / count
            let leftover = Int(total.minorUnits % count)
            let start = firstPayer.flatMap { participants.firstIndex(of: $0) } ?? 0
            var amounts = Array(repeating: base, count: participants.count)
            for step in 0..<leftover { amounts[(start + step) % participants.count] += 1 }
            return zip(participants, amounts).map { SplitShare(personID: $0, share: Money(minorUnits: $1, currency: currency)) }
        case .exact:
            let values = participants.map { inputs[$0] ?? 0 }
            guard values.allSatisfy({ $0 >= 0 }) else { throw .invalidInput }
            let (sum, overflow) = sumChecked(values)
            guard !overflow else { throw .overflow }
            guard sum == total.minorUnits else {
                throw .totalsDontMatch(remaining: Money(minorUnits: total.minorUnits - sum, currency: currency))
            }
            return zip(participants, values).map { SplitShare(personID: $0, input: $1, share: Money(minorUnits: $1, currency: currency)) }
        case .percent:
            let values = participants.map { inputs[$0] ?? 0 }
            guard values.allSatisfy({ $0 >= 0 }) else { throw .invalidInput }
            let (sum, overflow) = sumChecked(values)
            guard !overflow else { throw .overflow }
            guard sum == 10_000 else { throw .percentNot100(remainingBasisPoints: 10_000 - sum) }
            let amounts = apportion(total.minorUnits, weights: values)
            return zip(participants, zip(values, amounts)).map {
                SplitShare(personID: $0, input: $1.0, share: Money(minorUnits: $1.1, currency: currency))
            }
        case .shares:
            let values = participants.map { inputs[$0] ?? 1 }
            guard values.allSatisfy({ $0 >= 0 }) else { throw .invalidInput }
            let (sum, overflow) = sumChecked(values)
            guard !overflow else { throw .overflow }
            guard sum > 0 else { throw .invalidInput }
            let amounts = apportion(total.minorUnits, weights: values)
            return zip(participants, zip(values, amounts)).map {
                SplitShare(personID: $0, input: $1.0, share: Money(minorUnits: $1.1, currency: currency))
            }
        }
    }

    /// Splits `total` in proportion to `weights`: floor each part, then give the leftover units to the
    /// largest remainders (ties in list order). The parts add up to `total` exactly.
    public static func apportion(_ total: Int64, weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(Int64(0), +)
        guard sum > 0, total >= 0 else { return weights.map { _ in 0 } }
        var parts: [Int64] = []
        var remainders: [(index: Int, remainder: Int64)] = []
        for (index, weight) in weights.enumerated() {
            let product = total.multipliedFullWidth(by: weight)
            let (quotient, remainder) = sum.dividingFullWidth(product)
            parts.append(quotient)
            remainders.append((index, remainder))
        }
        var leftover = total - parts.reduce(0, +)
        for entry in remainders.sorted(by: { $0.remainder != $1.remainder ? $0.remainder > $1.remainder : $0.index < $1.index }) {
            guard leftover > 0 else { break }
            parts[entry.index] += 1
            leftover -= 1
        }
        return parts
    }

    /// Who owes whom from one split. For an expense, each person owes each payer their share times
    /// that payer's part of the total; for income the receiver owes everyone else their share.
    /// Each payer's receivables add up exactly (largest remainder). Self-debts are dropped.
    public static func debts(_ split: Split, isIncome: Bool) -> [Debt] {
        let weights = split.shares.map(\.share.minorUnits)
        var result: [Debt] = []
        for payer in split.payers {
            let parts = apportion(payer.amount.minorUnits, weights: weights)
            for (share, part) in zip(split.shares, parts) where share.personID != payer.personID && part > 0 {
                let amount = Money(minorUnits: part, currency: payer.amount.currency)
                result.append(isIncome ? Debt(debtor: payer.personID, creditor: share.personID, amount: amount)
                                       : Debt(debtor: share.personID, creditor: payer.personID, amount: amount))
            }
        }
        return result
    }

    private static func sumChecked(_ values: [Int64]) -> (Int64, Bool) {
        var total: Int64 = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            if overflow { return (0, true) }
            total = next
        }
        return (total, false)
    }
}
