import Foundation
import Testing
@testable import UZeeCore

private let today = LocalDate(year: 2026, month: 10, day: 6)
private let vocabulary = VoiceVocabulary(
    people: ["Usama", "Ammi", "Bilal", "Office partner"],
    accounts: ["HBL", "Meezan", "Cash", "Easypaisa", "Wise", "HBL card"],
    categories: ["Groceries", "Fuel", "Dining out", "Food", "Electricity", "Streaming"])

private func parse(_ text: String) -> VoiceCommand {
    VoiceRuleParser.parse(text, vocabulary: vocabulary, today: today)
}

@Suite("Voice amounts")
struct AmountPhraseTests {
    // VOX-011
    @Test("Spoken amount phrases", arguments: [
        ("20k", "20000", nil),
        ("I sent 20k PKR to a friend", "20000", "PKR"),
        ("1.5 lakh", "150000", nil),
        ("$20", "20", "USD"),
        ("twenty dollars", "20", "USD"),
        ("two thousand five hundred", "2500", nil),
        ("twenty five thousand", "25000", nil),
        ("Rs 5,000", "5000", "PKR"),
        ("5000 rupees", "5000", "PKR"),
        ("a thousand", "1000", nil),
        ("2 crore", "20000000", nil)
    ] as [(String, String, String?)])
    func phrases(text: String, value: String, currency: String?) {
        let found = AmountPhrase.find(in: text)
        #expect(found?.value == Decimal(string: value))
        #expect(found?.currency?.code == currency)
    }

    @Test("Days and ordinals are not amounts; the marked amount wins")
    func notDays() {
        #expect(AmountPhrase.find(in: "on 5 October") == nil)
        #expect(AmountPhrase.find(in: "on the 5th") == nil)
        #expect(AmountPhrase.find(in: "lent a friend money") == nil)
        #expect(AmountPhrase.find(in: "On 5 October I paid 3000")?.value == 3000)
        #expect(AmountPhrase.find(in: "2 pizzas for Rs 1,800")?.value == 1800)
    }
}

@Suite("Voice understanding")
struct VoiceRuleParserTests {
    // VOX-007: the PRD example needs the name as a follow-up.
    @Test("Lend to a friend, then the name")
    func lendFlow() {
        let first = parse("I sent 20k PKR to a friend, they'll return it later")
        #expect(first.action == .lend)
        #expect(first.amount?.value == 20_000)
        #expect(first.person == nil)
        #expect(VoiceDialog.need(first) == .person)
        #expect(VoiceDialog.prompt(.person, for: first) == "Who did you lend it to?")
        let second = VoiceDialog.apply("Usama", to: first, need: .person, vocabulary: vocabulary)
        #expect(second.person == "Usama")
        #expect(VoiceDialog.need(second) == nil)
    }

    // VOX-008: a new person is kept as said.
    @Test("Unknown names are kept for the card")
    func newPerson() {
        let command = parse("Lent 5000 to Hamza from Easypaisa")
        #expect(command.action == .lend)
        #expect(command.person == "Hamza")
        #expect(command.account == "Easypaisa")
        let answer = VoiceDialog.apply("his name is hamza", to: VoiceCommand(action: .lend), need: .person, vocabulary: vocabulary)
        #expect(answer.person == "Hamza")
    }

    @Test("Loans and repayments")
    func loans() {
        #expect(parse("I borrowed 10,000 from Bilal").action == .borrow)
        #expect(parse("I borrowed 10,000 from Bilal").person == "Bilal")
        #expect(parse("Bilal lent me 5000").action == .borrow)
        #expect(parse("Usama paid me back 5000").action == .repaidToMe)
        #expect(parse("Usama paid me back 5000").person == "Usama")
        #expect(parse("I got 5000 back from Usama").action == .repaidToMe)
        #expect(parse("I paid back Ammi 25000").action == .repaidByMe)
        #expect(parse("I paid back Ammi 25000").person == "Ammi")
    }

    @Test("Expenses with category, payee, account and date")
    func expenses() {
        let groceries = parse("Spent 2,500 on groceries at Imtiaz yesterday with cash")
        #expect(groceries.action == .expense)
        #expect(groceries.amount?.value == 2_500)
        #expect(groceries.category == "Groceries")
        #expect(groceries.payee == "Imtiaz")
        #expect(groceries.account == "Cash")
        #expect(groceries.date == LocalDate(year: 2026, month: 10, day: 5))

        let netflix = parse("Paid 1100 for Netflix from HBL card")
        #expect(netflix.action == .expense)
        #expect(netflix.payee == "Netflix")
        #expect(netflix.account == "HBL card")

        let noAmount = parse("I bought fuel")
        #expect(noAmount.action == .expense)
        #expect(VoiceDialog.need(noAmount) == .amount)
        #expect(VoiceDialog.apply("about 3k", to: noAmount, need: .amount, vocabulary: vocabulary).amount?.value == 3_000)
    }

    @Test("Income and transfers")
    func incomeAndTransfers() {
        let salary = parse("Received salary of 560,000 in Meezan")
        #expect(salary.action == .income)
        #expect(salary.account == "Meezan")
        let transfer = parse("Transfer 500 dollars from Wise to HBL")
        #expect(transfer.action == .transfer)
        #expect(transfer.account == "Wise")
        #expect(transfer.toAccount == "HBL")
        #expect(transfer.amount?.currency == .usd)
        let reversed = parse("Move 10k to Cash from Meezan")
        #expect(reversed.account == "Meezan")
        #expect(reversed.toAccount == "Cash")
    }

    // VOX-001…006 (understanding part; the numbers come from the same calculators as the screens).
    @Test("Questions")
    func questions() {
        #expect(parse("How much do I owe my mother?").question == .iOwe(person: "Ammi"))
        #expect(parse("How much does Usama owe me").question == .owesMe(person: "Usama"))
        #expect(parse("Who owes me money?").question == .owesMe(person: nil))
        #expect(parse("What's my next bill?").question == .nextBill)
        #expect(parse("How much are my subscriptions this month?").question == .subscriptions)
        #expect(parse("How much budget is left?").question == .budgetLeft)
        #expect(parse("How much did I spend on food this month?").question == .spent(category: "Food", period: .thisMonth))
        #expect(parse("What did I spend last month").question == .spent(category: nil, period: .lastMonth))
        #expect(parse("What's my HBL balance").question == .balance(account: "HBL"))
        #expect(parse("What's due before salary?").question == .dueBeforeSalary)
        #expect(parse("How much do I owe my mother?").action == .question)
    }

    @Test("Nothing understood")
    func unknown() {
        #expect(parse("Hello there").action == .unknown)
        #expect(VoiceDialog.need(parse("Hello there")) == nil)
    }
}
