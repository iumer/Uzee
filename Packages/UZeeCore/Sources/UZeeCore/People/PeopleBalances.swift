import Foundation

/// Amounts in several currencies kept apart (a group can mix PKR and USD) and converted only for display.
public struct MoneyBag: Hashable, Sendable {
    public private(set) var amounts: [String: Money] = [:]

    public init() {}

    public init(_ money: Money) { add(money) }

    public mutating func add(_ money: Money) {
        let current = amounts[money.currency.code]?.minorUnits ?? 0
        amounts[money.currency.code] = Money(minorUnits: current &+ money.minorUnits, currency: money.currency)
    }

    public mutating func subtract(_ money: Money) {
        add(Money(minorUnits: -money.minorUnits, currency: money.currency))
    }

    public mutating func add(_ other: MoneyBag) {
        for money in other.amounts.values { add(money) }
    }

    public var negated: MoneyBag {
        var bag = MoneyBag()
        for money in amounts.values { bag.subtract(money) }
        return bag
    }

    /// Non-zero parts, base currency first then by code.
    public func parts(base: Currency) -> [Money] {
        amounts.values.filter { !$0.isZero }.sorted {
            ($0.currency == base ? "" : $0.currency.code) < ($1.currency == base ? "" : $1.currency.code)
        }
    }

    /// The sum in `base` at the table rates, each currency converted once (DATA_MODEL §4).
    public func total(in base: Currency, rates: [String: Decimal]) -> Money {
        var total: Int64 = 0
        for money in amounts.values where !money.isZero {
            if let converted = try? RateTable.toBase(money, base: base, rates: rates) { total &+= converted.minorUnits }
        }
        return Money(minorUnits: total, currency: base)
    }

    public var isZero: Bool { amounts.values.allSatisfy(\.isZero) }
    public var currencies: Set<Currency> { Set(amounts.values.filter { !$0.isZero }.map(\.currency)) }
}

/// A settle-up payment between me and one person (SPL-08), read from a `.settlement` transaction.
public struct Settlement: Hashable, Sendable {
    public var transactionID: UUID
    public var personID: UUID
    public var groupID: UUID?
    /// Positive: I paid them. Negative: they paid me.
    public var amount: Money
    public var date: LocalDate

    public init(transactionID: UUID, personID: UUID, groupID: UUID?, amount: Money, date: LocalDate) {
        self.transactionID = transactionID
        self.personID = personID
        self.groupID = groupID
        self.amount = amount
        self.date = date
    }

    /// The settlement carried by `transaction`, if it is one. The account leg says who paid:
    /// money leaving my account means I paid them.
    public static func from(_ transaction: MoneyTransaction) -> Settlement? {
        guard transaction.kind == .settlement, transaction.isEffective, let person = transaction.counterpartyID else { return nil }
        let iPaid = (transaction.legs.first?.amount.minorUnits ?? -1) < 0
        let amount = iPaid ? transaction.amount : Money(minorUnits: -transaction.amount.minorUnits, currency: transaction.amount.currency)
        return Settlement(transactionID: transaction.id, personID: person, groupID: transaction.groupID, amount: amount,
                          date: transaction.localDate)
    }
}

/// One person's balance with me (SPL-01/07, LOAN-04). Positive = owes you, negative = you owe.
public struct PersonBalance: Hashable, Sendable {
    public var personID: UUID
    public var loans = MoneyBag()
    /// Shared expenses and income plus settlements.
    public var shared = MoneyBag()

    public init(personID: UUID) { self.personID = personID }

    public var net: MoneyBag {
        var bag = loans
        bag.add(shared)
        return bag
    }
}

/// My balance inside one group: what each member and I owe each other there, and every member's net
/// (paid − share) for Simplify debts (SPL-07, SPL-09).
public struct GroupBalance: Hashable, Sendable {
    public var groupID: UUID
    /// Per other member: + they owe me, − I owe them, from this group only.
    public var withMe: [UUID: MoneyBag] = [:]
    /// Per member including me: + is owed money by the group, − owes the group.
    public var nets: [UUID: MoneyBag] = [:]

    public init(groupID: UUID) { self.groupID = groupID }

    public var myNet: MoneyBag {
        var bag = MoneyBag()
        for value in withMe.values { bag.add(value) }
        return bag
    }
}

/// Every people figure is computed here from loans, splits and settlements; nothing is typed (SPL-07).
public struct PeopleLedger: Sendable {
    public let selfID: UUID
    public let base: Currency
    public let rates: [String: Decimal]
    public private(set) var people: [UUID: PersonBalance] = [:]
    public private(set) var groups: [UUID: GroupBalance] = [:]

    /// `transactions` should be the live ones; deleted or pending rows are skipped.
    public init(selfID: UUID, transactions: [MoneyTransaction], splits: [Split], loans: [Loan], base: Currency,
                rates: [String: Decimal]) {
        self.selfID = selfID
        self.base = base
        self.rates = rates
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for loan in loans {
            guard let person = loan.personID else { continue }
            if let txn = loan.transactionID, byID[txn]?.isEffective != true { continue }
            let live = Loan(id: loan.id, direction: loan.direction, personID: person, principal: loan.principal,
                            startDate: loan.startDate, transactionID: loan.transactionID, writtenOffAt: loan.writtenOffAt,
                            payments: loan.payments.filter { payment in payment.transactionID.map { byID[$0]?.isEffective == true } ?? true })
            people[person, default: PersonBalance(personID: person)].loans.add(LoanCalculator.signedOutstanding(live))
        }
        for split in splits {
            guard let transaction = byID[split.transactionID], transaction.isEffective else { continue }
            let isIncome = SpendingRules.countsAsIncome(transaction.kind)
            for debt in SplitCalculator.debts(split, isIncome: isIncome) {
                if debt.creditor == selfID {
                    people[debt.debtor, default: PersonBalance(personID: debt.debtor)].shared.add(debt.amount)
                } else if debt.debtor == selfID {
                    people[debt.creditor, default: PersonBalance(personID: debt.creditor)].shared.subtract(debt.amount)
                }
            }
            if let groupID = split.groupID {
                var group = groups[groupID] ?? GroupBalance(groupID: groupID)
                for debt in SplitCalculator.debts(split, isIncome: isIncome) {
                    group.nets[debt.creditor, default: MoneyBag()].add(debt.amount)
                    group.nets[debt.debtor, default: MoneyBag()].subtract(debt.amount)
                    if debt.creditor == selfID { group.withMe[debt.debtor, default: MoneyBag()].add(debt.amount) }
                    if debt.debtor == selfID { group.withMe[debt.creditor, default: MoneyBag()].subtract(debt.amount) }
                }
                groups[groupID] = group
            }
        }
        for settlement in transactions.compactMap(Settlement.from) {
            people[settlement.personID, default: PersonBalance(personID: settlement.personID)].shared.add(settlement.amount)
            if let groupID = settlement.groupID {
                var group = groups[groupID] ?? GroupBalance(groupID: groupID)
                group.withMe[settlement.personID, default: MoneyBag()].add(settlement.amount)
                group.nets[selfID, default: MoneyBag()].add(settlement.amount)
                group.nets[settlement.personID, default: MoneyBag()].subtract(settlement.amount)
                groups[groupID] = group
            }
        }
    }

    public func balance(of person: UUID) -> PersonBalance { people[person] ?? PersonBalance(personID: person) }

    public func group(_ id: UUID) -> GroupBalance { groups[id] ?? GroupBalance(groupID: id) }

    /// Net with a person in the base currency at the table rate.
    public func net(of person: UUID) -> Money { balance(of: person).net.total(in: base, rates: rates) }

    /// "Owed to you" (Σ positive person balances) and "You owe" (Σ negative, as a positive amount).
    public var overall: (owedToYou: Money, youOwe: Money) {
        var owed: Int64 = 0
        var owe: Int64 = 0
        for person in people.keys where person != selfID {
            let value = net(of: person).minorUnits
            if value > 0 { owed &+= value } else { owe &+= -value }
        }
        return (Money(minorUnits: owed, currency: base), Money(minorUnits: owe, currency: base))
    }
}

/// Fewest payments to settle a group (SPL-09): repeatedly match the largest debtor with the largest
/// creditor (ties by member order). Suggestions only; net positions are preserved exactly.
public enum DebtSimplifier {
    public static func simplify(nets: [UUID: Money], order: [UUID]) -> [Debt] {
        guard let currency = nets.values.first?.currency else { return [] }
        func rank(_ id: UUID) -> Int { order.firstIndex(of: id) ?? Int.max }
        var balances = nets.mapValues(\.minorUnits)
        var result: [Debt] = []
        while true {
            let creditors = balances.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : rank($0.key) < rank($1.key) }
            let debtors = balances.filter { $0.value < 0 }.sorted { $0.value != $1.value ? $0.value < $1.value : rank($0.key) < rank($1.key) }
            guard let creditor = creditors.first, let debtor = debtors.first else { break }
            let amount = min(creditor.value, -debtor.value)
            result.append(Debt(debtor: debtor.key, creditor: creditor.key, amount: Money(minorUnits: amount, currency: currency)))
            balances[creditor.key] = creditor.value - amount
            balances[debtor.key] = debtor.value + amount
        }
        return result
    }
}
