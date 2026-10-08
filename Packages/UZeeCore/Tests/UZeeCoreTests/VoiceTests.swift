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

@Suite("UZee helper replies")
struct AssistantReplyTests {
    @Test("Short yes and no answer the card; longer sentences are edits")
    func confirmOrCancel() {
        #expect(AssistantReply.intent("Yes, save it") == .confirm)
        #expect(AssistantReply.intent("haan theek hai") == .confirm)
        #expect(AssistantReply.intent("No") == .cancel)
        #expect(AssistantReply.intent("cancel that") == .cancel)
        #expect(AssistantReply.intent("No, make it 3,000 from Meezan instead") == nil)
        #expect(AssistantReply.intent("Spent 2,500 on groceries") == nil)
    }

    @Test("Goodbyes end a hands-free conversation")
    func goodbye() {
        #expect(AssistantReply.isGoodbye("Thanks, bye"))
        #expect(AssistantReply.isGoodbye("that's all"))
        #expect(!AssistantReply.isGoodbye("How much did I spend on fuel this month?"))
    }
}

@Suite("Reminder phrases")
struct ReminderPhraseTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)  // a Thursday

    @Test("Future dates as people say them")
    func dates() {
        #expect(ReminderPhrase.date("tomorrow", today: today) == LocalDate(year: 2026, month: 10, day: 9))
        #expect(ReminderPhrase.date("day after tomorrow", today: today) == LocalDate(year: 2026, month: 10, day: 10))
        #expect(ReminderPhrase.date("on Friday", today: today) == LocalDate(year: 2026, month: 10, day: 9))
        #expect(ReminderPhrase.date("Thursday", today: today) == LocalDate(year: 2026, month: 10, day: 15))
        #expect(ReminderPhrase.date("in 3 days", today: today) == LocalDate(year: 2026, month: 10, day: 11))
        #expect(ReminderPhrase.date("next week", today: today) == LocalDate(year: 2026, month: 10, day: 15))
        #expect(ReminderPhrase.date("on the 5th", today: today) == LocalDate(year: 2026, month: 11, day: 5))
        #expect(ReminderPhrase.date("20 October", today: today) == LocalDate(year: 2026, month: 10, day: 20))
        #expect(ReminderPhrase.date("whenever", today: today) == nil)
    }

    @Test("Times: 5 pm, 5:30, at 5, evening; not '3 days'")
    func times() {
        #expect(ReminderPhrase.minuteOfDay("at 5 pm") == 17 * 60)
        #expect(ReminderPhrase.minuteOfDay("5:30 am") == 5 * 60 + 30)
        #expect(ReminderPhrase.minuteOfDay("at 5") == 17 * 60)
        #expect(ReminderPhrase.minuteOfDay("at 10") == 10 * 60)
        #expect(ReminderPhrase.minuteOfDay("in the evening") == 18 * 60)
        #expect(ReminderPhrase.minuteOfDay("in 3 days") == nil)
    }

    @Test("VOX-004 'Remind me to …' becomes a reminder with day, time and amount")
    func request() throws {
        let request = try #require(ReminderPhrase.request("Remind me to pay the plumber 5,000 on Friday at 5 pm", today: today, currency: .pkr))
        #expect(request.title == "Pay the plumber 5,000")
        #expect(request.date == LocalDate(year: 2026, month: 10, day: 9))
        #expect(request.minuteOfDay == 17 * 60)
        #expect(request.amount == Money(major: 5_000, .pkr))
        #expect(ReminderPhrase.request("Remind me about car tuning tomorrow", today: today, currency: .pkr)?.title == "Car tuning")
        #expect(ReminderPhrase.request("Remind me to call Ammi", today: today, currency: .pkr) == nil)
        #expect(ReminderPhrase.request("How much did I spend", today: today, currency: .pkr) == nil)
    }
}

@Suite("Voice review fixes")
struct VoiceReviewTests {
    @Test("Only a plain yes or no answers the card")
    func plainYesNo() {
        #expect(AssistantReply.intent("No, make it 3000") == nil)
        #expect(AssistantReply.intent("no, HBL") == nil)
        #expect(AssistantReply.intent("yes from Meezan") == nil)
        #expect(AssistantReply.intent("ok wait") == nil)
        #expect(AssistantReply.intent("yes please") == .confirm)
        #expect(AssistantReply.intent("that's right") == .confirm)
        #expect(AssistantReply.intent("no thanks") == .cancel)
        #expect(AssistantReply.intent("never mind") == .cancel)
        #expect(AssistantReply.saysYes("yes, from Meezan"))
        #expect(!AssistantReply.saysYes("no, don't save it"))
    }

    @Test("An entry ending in thanks isn't a goodbye")
    func thanksEntry() {
        #expect(!AssistantReply.isGoodbye("Paid 2000 for petrol thanks"))
        #expect(AssistantReply.isGoodbye("ok thanks"))
    }

    @Test("Money in or out from the words around it")
    func direction() {
        #expect(parse("Paid maid salary 15000").action == .expense)
        #expect(parse("Got a haircut for 800").action == .expense)
        #expect(parse("Ali sent me 5000").action == .income)
        #expect(parse("Ammi gave me 2000").action == .income)
        #expect(parse("Got paid 150000 salary").action == .income)
        #expect(parse("Spent 500 on groceries").action == .expense)
    }

    @Test("The amount isn't a count, a date or a time")
    func amountChoice() {
        #expect(AmountPhrase.find(in: "Bought 2 pizzas for 1500")?.value == 1500)
        #expect(AmountPhrase.find(in: "On 5/10 paid 300")?.value == 300)
        #expect(AmountPhrase.find(in: "1.5k")?.value == 1500)
        #expect(AmountPhrase.find(in: "500 rupay") == SpokenAmount(value: 500, currency: .pkr))
        #expect(AmountPhrase.find(in: "Rs.1,50,000")?.value == 150_000)
        #expect(AmountPhrase.find(in: "do sau")?.value == 200)
        #expect(AmountPhrase.find(in: "paanch hazaar")?.value == 5000)
        #expect(AmountPhrase.find(in: "do it now") == nil)
        #expect(AmountPhrase.find(in: "two point two five dollars")?.value == Decimal(string: "2.25"))
    }

    @Test("Last Friday is the Friday before today")
    func pastWeekday() {
        // 6 Oct 2026 is a Tuesday.
        #expect(parse("Spent 500 on fuel last friday").date == LocalDate(year: 2026, month: 10, day: 2))
        #expect(parse("Spent 500 on fuel on tuesday").date == LocalDate(year: 2026, month: 9, day: 29))
    }

    @Test("A spending question keeps the category word it doesn't know")
    func unknownCategory() {
        #expect(parse("How much did I spend on biryani this month?").question == .spent(category: "biryani", period: .thisMonth))
        #expect(parse("How much did I spend this month?").question == .spent(category: nil, period: .thisMonth))
    }
}
