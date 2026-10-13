import Foundation
import Testing
@testable import UZeeCore

private func day(_ d: Int) -> LocalDate { LocalDate(year: 2026, month: 10, day: d) }
private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }

/// BUG-022: money moved between your own accounts is one transfer, not spending plus income. Synthetic rows
/// only (the repo is public): "Test User" stands in for the owner, "Other Person" for someone else.
@Suite("Transfer matcher")
struct TransferMatcherTests {
    let meezan = UUID(), nayapay = UUID(), hbl = UUID(), easypaisa = UUID()
    var names: [UUID: String] { [meezan: "Meezan Bank", nayapay: "NayaPay", hbl: "HBL", easypaisa: "Easypaisa"] }

    func entry(_ account: UUID, _ date: Int, _ amount: Int64, _ text: String) -> TransferMatcher.Entry {
        TransferMatcher.Entry(id: UUID(), accountID: account, date: day(date), amount: rs(amount), text: text)
    }

    @Test("A transfer naming the other bank on both sides is a sure pair")
    func bankNames() {
        let out = entry(hbl, 3, -5_000, "Funds Transfer to NAYAPAY 0300xxxx")
        let into = entry(nayapay, 3, 5_000, "Incoming fund transfer from HBL")
        let pairs = TransferMatcher.pairs([out, into], accountNames: names, ownerWords: [])
        #expect(pairs == [TransferMatcher.Pair(out: out, into: into, isSure: true)])
    }

    @Test("Your own name on both sides is learned and pairs them, one or two days apart")
    func ownerName() {
        let rows = [entry(meezan, 4, -12_000, "Raast P2P to TEST USER"), entry(easypaisa, 5, 12_000, "Money received from Test User"),
                    entry(meezan, 9, -3_000, "Raast P2P to TEST USER"), entry(nayapay, 11, 3_000, "Raast In Incoming fund transfer from TEST USER MEZ")]
        let owner = TransferMatcher.likelyOwnerWords(rows, accountNames: names)
        #expect(owner.contains("test"))
        #expect(owner.contains("user"))
        let pairs = TransferMatcher.pairs(rows, accountNames: names, ownerWords: owner)
        #expect(pairs.count == 2)
        #expect(pairs.allSatisfy(\.isSure))
    }

    @Test("Someone else's name on one side never makes a sure pair; an ATM withdrawal never pairs")
    func falseMatches() {
        let owner = ["test", "user"]
        // The owner's two false matches: cash out of an ATM, and money sent to another person.
        let atm = entry(meezan, 6, -10_000, "ATM Cash Withdrawal 1234")
        let raastIn = entry(nayapay, 6, 10_000, "Raast In Incoming fund transfer from Test User")
        let toOther = entry(nayapay, 8, -7_000, "Outgoing fund transfer to Other Person")
        let fromOwner = entry(meezan, 8, 7_000, "Raast P2P from Test User")
        let pairs = TransferMatcher.pairs([atm, raastIn, toOther, fromOwner], accountNames: names, ownerWords: owner)
        #expect(!pairs.contains { $0.out == atm })
        #expect(pairs.allSatisfy { !$0.isSure })
        #expect(TransferMatcher.likelyOwnerWords([toOther, fromOwner], accountNames: names).isEmpty)
    }

    @Test("Different amounts, the same account, or more than two days apart don't pair")
    func limits() {
        let rows = [entry(hbl, 1, -2_000, "Transfer to NayaPay"), entry(nayapay, 1, 2_001, "From HBL"),
                    entry(hbl, 2, -900, "Transfer to NayaPay"), entry(hbl, 2, 900, "From HBL"),
                    entry(hbl, 10, -4_000, "Transfer to NayaPay"), entry(nayapay, 13, 4_000, "From HBL")]
        #expect(TransferMatcher.pairs(rows, accountNames: names, ownerWords: []).isEmpty)
    }

    @Test("Each row is used once and the closest date wins")
    func onceEach() {
        let out = entry(meezan, 5, -1_500, "Transfer to Easypaisa")
        let near = entry(easypaisa, 5, 1_500, "Received from Meezan")
        let far = entry(easypaisa, 7, 1_500, "Received from Meezan")
        let pairs = TransferMatcher.pairs([out, far, near], accountNames: names, ownerWords: [])
        #expect(pairs.count == 1)
        #expect(pairs.first?.into == near)
    }

    @Test("Names match with one letter off or cut short, and a shared first name alone isn't you")
    func fuzzyNames() {
        #expect(TransferMatcher.sameWord("mohammad", "muhammad"))
        #expect(TransferMatcher.sameWord("muhamm", "muhammad"))
        #expect(!TransferMatcher.sameWord("ali", "alia"))
        #expect(TransferMatcher.namesOwner("to MOHAMMAD TESTER", ["muhammad", "tester"]))
        #expect(!TransferMatcher.namesOwner("to Muhammad Other", ["muhammad", "tester"]))
    }

    @Test("Bank aliases count: MEZ for Meezan, TMFB for Easypaisa, HABB for HBL")
    func aliases() {
        #expect(TransferMatcher.namesAccount("IBFT from MEZ 0123", "Meezan Bank"))
        #expect(TransferMatcher.namesAccount("Raast In TMFB", "Easypaisa"))
        #expect(TransferMatcher.namesAccount("HABB/IBFT", "HBL"))
        #expect(!TransferMatcher.namesAccount("Grocer Mart", "HBL"))
    }
}
