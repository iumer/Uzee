import Foundation

/// A payment still to make, on Plan › To pay (owner, 2026-10-15): "Kameti, Rs 20,000", paid in one go or in parts
/// ("paid 10k, 10k left"). Not tied to a month or a date: it stays on the list until it's paid.
public struct PaymentTodo: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var amount: Money
    /// Paid so far, in the same currency.
    public var paid: Money
    public var createdAt: Date
    /// Set when it was marked paid in full.
    public var doneAt: Date?

    public init(id: UUID = UUID(), name: String, amount: Money, paid: Money? = nil, createdAt: Date = Date(), doneAt: Date? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.paid = paid ?? .zero(amount.currency)
        self.createdAt = createdAt
        self.doneAt = doneAt
    }

    /// What's still to pay, never below zero.
    public var remaining: Money {
        Money(minorUnits: max(0, amount.minorUnits - paid.minorUnits), currency: amount.currency)
    }

    public var isDone: Bool { doneAt != nil || remaining.minorUnits == 0 }

    public enum Problem: Error, Equatable, Sendable {
        case emptyName
        case invalidAmount
        case moreThanLeft(Money)
    }

    public func validate() throws(Problem) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyName }
        guard amount.minorUnits > 0, paid.minorUnits >= 0, paid.currency == amount.currency else { throw .invalidAmount }
    }

    /// After paying `part`: more than what's left is refused; paying all of it marks it done.
    public func paying(_ part: Money, at time: Date = Date()) throws(Problem) -> PaymentTodo {
        guard part.minorUnits > 0, part.currency == amount.currency else { throw .invalidAmount }
        guard part.minorUnits <= remaining.minorUnits else { throw .moreThanLeft(remaining) }
        var next = self
        next.paid = Money(minorUnits: paid.minorUnits + part.minorUnits, currency: amount.currency)
        if next.remaining.minorUnits == 0 { next.doneAt = time }
        return next
    }

    /// What you have, what's still to pay on the open items (in base), and what's left after paying them all.
    public static func summary(_ todos: [PaymentTodo], have: Money, rates: [String: Decimal]) -> (toPay: Money, left: Money) {
        var toPay = Money.zero(have.currency)
        for todo in todos where !todo.isDone {
            guard let inBase = try? RateTable.toBase(todo.remaining, base: have.currency, rates: rates) else { continue }
            toPay = Money(minorUnits: toPay.minorUnits + inBase.minorUnits, currency: have.currency)
        }
        return (toPay, Money(minorUnits: have.minorUnits - toPay.minorUnits, currency: have.currency))
    }
}
