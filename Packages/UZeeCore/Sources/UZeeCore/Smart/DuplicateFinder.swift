import Foundation

/// Spots statement rows that are already in UZee (IMP-03): same account, same amount and direction,
/// dated the same day or one day apart (banks often post a day late). Each saved transaction matches one row at most.
public enum DuplicateFinder {
    public struct Candidate: Sendable {
        public var date: LocalDate
        /// Signed: negative = money left the account.
        public var amount: Money

        public init(date: LocalDate, amount: Money) {
            self.date = date
            self.amount = amount
        }
    }

    /// Row index → the matching saved transaction.
    public static func matches(_ candidates: [Candidate], accountID: UUID, in transactions: [MoneyTransaction]) -> [Int: UUID] {
        var pool: [(id: UUID, date: LocalDate, amount: Money)] = []
        for transaction in transactions where transaction.deletedAt == nil {
            for leg in transaction.legs where leg.accountID == accountID {
                pool.append((transaction.id, transaction.localDate, leg.amount))
            }
        }
        var used = Set<Int>()
        var result: [Int: UUID] = [:]
        // Exact days first, then one day apart.
        for tolerance in 0...1 {
            for (index, candidate) in candidates.enumerated() where result[index] == nil {
                guard let match = pool.indices.first(where: { position in
                    !used.contains(position) && pool[position].amount == candidate.amount
                        && abs(pool[position].date.days(to: candidate.date)) == tolerance
                }) else { continue }
                used.insert(match)
                result[index] = pool[match].id
            }
        }
        return result
    }
}
