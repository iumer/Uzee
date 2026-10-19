import Foundation
import Testing
@testable import UZeeCore

@Suite("Rate services")
struct RateServiceTests {
    @Test("Where a service's rate comes from, by its name")
    func sources() {
        #expect(RateService.source(for: "Google") == .market)
        #expect(RateService.source(for: "Wise") == .wise)
        #expect(RateService.source(for: "Western Union") == .westernUnion)
        #expect(RateService.source(for: "western union") == .westernUnion)
        #expect(RateService.source(for: "SadaPay") == .typed)
        #expect(RateService.source(for: "Wisewood Exchange") == .wise)
    }

    @Test("Google first, then the services already shown")
    func starting() {
        let list = RateService.starting(with: [.nayaPay, .westernUnion])
        #expect(list.map(\.name) == ["Google", "NayaPay", "Western Union"])
        #expect(list.map(\.source) == [.market, .typed, .westernUnion])
    }

    @Test("Default pairs: every foreign account currency into the base, USD and EUR always")
    func pairs() {
        let pairs = RatePair.defaults(accountCurrencies: [.pkr, .usd, .gbp], base: .pkr)
        #expect(pairs.map(\.id) == ["USD>PKR", "EUR>PKR", "GBP>PKR"])
        #expect(RatePair(from: .sar, to: .pkr).id == "SAR>PKR")
    }
}
