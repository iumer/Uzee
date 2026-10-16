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

    @Test("To receive adds to what you have; done ones don't count")
    func totalsWithIncoming() {
        let todos = [
            PaymentTodo(name: "Rent", amount: rs(30_000)),
            PaymentTodo(direction: .receive, name: "Salary", amount: rs(150_000)),
            PaymentTodo(direction: .receive, name: "Ali owes", amount: rs(10_000), paid: rs(4_000)),
            PaymentTodo(direction: .receive, name: "Old refund", amount: rs(5_000), doneAt: Date()),
        ]
        let result = PaymentTodo.totals(todos, have: rs(20_000), rates: [:])
        #expect(result.toPay == rs(30_000))
        #expect(result.toReceive == rs(156_000))
        #expect(result.left == rs(20_000 + 156_000 - 30_000))
        #expect(PaymentTodo.summary(todos, have: rs(20_000), rates: [:]).left == result.left)
    }
}
