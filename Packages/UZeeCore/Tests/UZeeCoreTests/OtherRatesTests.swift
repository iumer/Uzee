import Foundation
import Testing
@testable import UZeeCore

/// Owner, 2026-10-15: the Google (market) rate and services like Western Union next to Wise's rate.
@Suite("Other exchange rates")
struct OtherRatesTests {
    @Test("Market rate from either source's reply")
    func market() {
        let first = Data(#"{"result":"success","base_code":"USD","rates":{"USD":1,"PKR":281.25,"EUR":0.92}}"#.utf8)
        #expect(MarketRates.parse(first, source: .usd, target: .pkr) == Decimal(string: "281.25"))
        let second = Data(#"{"date":"2026-10-15","eur":{"pkr":305.4,"usd":1.08}}"#.utf8)
        #expect(MarketRates.parse(second, source: .eur, target: .pkr) == Decimal(string: "305.4"))
        #expect(MarketRates.parse(Data("<html>".utf8), source: .usd, target: .pkr) == nil)
        #expect(MarketRates.parse(Data(#"{"rates":{"PKR":0}}"#.utf8), source: .usd, target: .pkr) == nil)
    }

    @Test("Western Union: the best fx_rate in its price list")
    func westernUnion() {
        let reply = Data(#"{"services_groups":[{"pay_groups":[{"fx_rate":278.5},{"fx_rate":"279.1"}]},{"pay_groups":[{"fx_rate":0}]}]}"#.utf8)
        #expect(WesternUnionRates.parse(reply) == Decimal(string: "279.1"))
        #expect(WesternUnionRates.parse(Data(#"{"error":"blocked"}"#.utf8)) == nil)
        #expect(!WesternUnionRates.body(.usd, .pkr).isEmpty)
    }

    @Test("Services found in account names")
    func detected() {
        #expect(RateProvider.detected(in: ["Western Union USD", "HBL", "payoneer"]) == [.westernUnion, .payoneer])
        #expect(RateProvider.detected(in: ["Cash", "Meezan"]).isEmpty)
    }
}
