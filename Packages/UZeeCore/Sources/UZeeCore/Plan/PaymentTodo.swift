import Foundation

/// A payment still to make, on Plan › To pay (owner, 2026-10-15): "Kameti, Rs 20,000", paid in one go or in parts
/// ("paid 10k, 10k left"). Not tied to a month or a date: it stays on the list until it's paid.
/// Plan › To receive (owner, 2026-10-16) uses the same list for money coming in: next salary, what Ali owes.
public struct PaymentTodo: Hashable, Sendable, Identifiable {
    public enum Direction: String, Hashable, Sendable, CaseIterable {
        case pay, receive
    }

    public var id: UUID
    /// Paying it out, or receiving it.
    public var direction: Direction
    public var name: String
    public var amount: Money
    /// Paid so far, in the same currency.
    public var paid: Money
    public var createdAt: Date
    /// Set when it was marked paid in full.
    public var doneAt: Date?
    /// Optional date by which the payment is due.
    public var dueDate: Date?
    /// If set, a local notification fires at this exact time.
    public var reminderAt: Date?

    public init(id: UUID = UUID(), direction: Direction = .pay, name: String, amount: Money, paid: Money? = nil, createdAt: Date = Date(),
                doneAt: Date? = nil, dueDate: Date? = nil, reminderAt: Date? = nil) {
        self.id = id
        self.direction = direction
        self.name = name
        self.amount = amount
        self.paid = paid ?? .zero(amount.currency)
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.dueDate = dueDate
        self.reminderAt = reminderAt
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
        // Edited down below what was already paid (owner, 2026-10-20): refused, not saved as "paid more than it was".
        guard paid.minorUnits <= amount.minorUnits else { throw .moreThanLeft(amount) }
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
        let totals = totals(todos, have: have, rates: rates)
        return (totals.toPay, totals.left)
    }

    /// What you have, plus what's still to come in, minus what's still to pay: what's left once it all happens.
    public static func totals(_ todos: [PaymentTodo], have: Money, rates: [String: Decimal]) -> (toPay: Money, toReceive: Money, left: Money) {
        var toPay: Int64 = 0
        var toReceive: Int64 = 0
        for todo in todos where !todo.isDone {
            guard let inBase = try? RateTable.toBase(todo.remaining, base: have.currency, rates: rates) else { continue }
            switch todo.direction {
            case .pay: toPay += inBase.minorUnits
            case .receive: toReceive += inBase.minorUnits
            }
        }
        return (Money(minorUnits: toPay, currency: have.currency), Money(minorUnits: toReceive, currency: have.currency),
                Money(minorUnits: have.minorUnits + toReceive - toPay, currency: have.currency))
    }
}
