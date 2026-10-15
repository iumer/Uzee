import Foundation
import Testing
@testable import UZeeCore

/// Owner, 2026-10-15: a to-do list of payments, paid in full or in parts, with what's left after them.
@Suite("Payments to do")
struct PaymentTodoTests {
    func rs(_ major: Int64) -> Money { Money(minorUnits: major * 100, currency: .pkr) }

    @Test("Kameti 20k: pay 10k, 10k left; pay the rest and it's done")
    func partial() throws {
        let kameti = PaymentTodo(name: "Kameti", amount: rs(20_000))
        let half = try kameti.paying(rs(10_000))
        #expect(half.remaining == rs(10_000))
        #expect(!half.isDone)
        #expect(throws: PaymentTodo.Problem.moreThanLeft(rs(10_000))) { try half.paying(rs(15_000)) }
        let done = try half.paying(rs(10_000))
        #expect(done.isDone)
        #expect(done.doneAt != nil)
    }

    @Test("Have, to pay, left; done items and other currencies")
    func summary() throws {
        let todos = [
            PaymentTodo(name: "Kameti", amount: rs(20_000), paid: rs(5_000)),
            PaymentTodo(name: "Car fuel", amount: rs(40_000)),
            PaymentTodo(name: "Rent", amount: rs(30_000), doneAt: Date()),
            PaymentTodo(name: "Saving", amount: Money(minorUnits: 200_00, currency: .usd)),
        ]
        let result = PaymentTodo.summary(todos, have: rs(100_000), rates: ["USD": 280])
        #expect(result.toPay == rs(15_000 + 40_000 + 56_000))
        #expect(result.left == rs(100_000 - 111_000))
        #expect(throws: PaymentTodo.Problem.emptyName) { try PaymentTodo(name: " ", amount: rs(1)).validate() }
    }
}
