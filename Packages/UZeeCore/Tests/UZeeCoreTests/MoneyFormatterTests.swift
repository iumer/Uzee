import Foundation
import Testing
@testable import UZeeCore

/// UI-005 (formatting part) and DESIGN_SYSTEM §4. Values come from docs/mockup-dataset.md.
@Suite("MoneyFormatter")
struct MoneyFormatterTests {
    let rate: Decimal = 280

    @Test("PKR shows whole rupees with grouping")
    func pkr() {
        #expect(MoneyFormatter.string(Money(major: 182_400, .pkr)) == "Rs 182,400")
        #expect(MoneyFormatter.string(Money(major: 484_800, .pkr)) == "Rs 484,800")
        #expect(MoneyFormatter.string(Money(major: 0, .pkr)) == "Rs 0")
        #expect(MoneyFormatter.string(Money(major: 1_000_000, .pkr)) == "Rs 1,000,000")
    }

    @Test("PKR paisa round half up for display only")
    func pkrRounding() {
        #expect(MoneyFormatter.string(Money(minorUnits: 83_720, currency: .pkr)) == "Rs 837")
        #expect(MoneyFormatter.string(Money(minorUnits: 83_750, currency: .pkr)) == "Rs 838")
        #expect(MoneyFormatter.string(Money(minorUnits: 83_749, currency: .pkr)) == "Rs 837")
    }

    @Test("USD always shows two decimals")
    func usd() {
        #expect(MoneyFormatter.string(Money(minorUnits: 52_000, currency: .usd)) == "$520.00")
        #expect(MoneyFormatter.string(Money(minorUnits: 299, currency: .usd)) == "$2.99")
        #expect(MoneyFormatter.string(Money(minorUnits: 5, currency: .usd)) == "$0.05")
    }

    @Test("Signs use a true minus and a plus for inflow")
    func signs() {
        #expect(MoneyFormatter.string(Money(major: -1_600, .pkr)) == "\u{2212}Rs 1,600")
        #expect(MoneyFormatter.string(Money(minorUnits: 187_500, currency: .usd), sign: .always) == "+$1,875.00")
        #expect(MoneyFormatter.string(Money(major: -1_600, .pkr), sign: .none) == "Rs 1,600")
        #expect(MoneyFormatter.string(Money(major: 0, .pkr), sign: .always) == "Rs 0")
    }

    @Test("Foreign amounts get an approximate base line")
    func approximate() {
        #expect(MoneyFormatter.approximate(Money(minorUnits: 52_000, currency: .usd), in: .pkr, rate: rate) == "≈ Rs 145,600")
        #expect(MoneyFormatter.approximate(Money(minorUnits: 2_000, currency: .usd), in: .pkr, rate: rate) == "≈ Rs 5,600")
        #expect(MoneyFormatter.approximate(Money(minorUnits: 299, currency: .usd), in: .pkr, rate: rate) == "≈ Rs 837")
    }

    @Test("Conversion is exact in minor units")
    func conversion() {
        let converted = CurrencyConverter.convert(Money(minorUnits: 66_000, currency: .usd), to: .pkr, rate: rate)
        #expect(converted == Money(major: 184_800, .pkr))
        let real = CurrencyConverter.convert(Money(minorUnits: 50_000, currency: .usd), to: .pkr, rate: Decimal(string: "278.70")!)
        #expect(real == Money(major: 139_350, .pkr))
    }

    @Test("Hidden amounts keep the currency symbol")
    func hidden() {
        #expect(MoneyFormatter.hidden(.pkr) == "Rs •••••")
        #expect(MoneyFormatter.hidden(.usd) == "$•••••")
    }

    @Test("Spoken text uses words, never 'R S'")
    func spoken() {
        #expect(MoneyFormatter.spoken(Money(major: 25_000, .pkr)) == "25,000 rupees")
        #expect(MoneyFormatter.spoken(Money(major: 1, .pkr)) == "1 rupee")
        #expect(MoneyFormatter.spoken(Money(major: -1_600, .pkr)) == "minus 1,600 rupees")
        #expect(MoneyFormatter.spoken(Money(minorUnits: 299, currency: .usd)) == "2 US dollars 99 cents")
        #expect(MoneyFormatter.spoken(Money(minorUnits: 2_000, currency: .usd), base: .pkr, rate: rate)
                == "20 US dollars, about 5,600 rupees")
    }

    @Test("Extreme values do not overflow")
    func extremes() {
        let text = MoneyFormatter.string(Money(minorUnits: .min, currency: .usd))
        #expect(text.hasPrefix("\u{2212}$"))
    }
}

/// UI-007 (domain part): every top-level category has a name and a symbol.
@Suite("CategoryKind")
struct CategoryKindTests {
    @Test("Names and symbols are set and unique per name")
    func namesAndSymbols() {
        for kind in CategoryKind.allCases {
            #expect(!kind.name.isEmpty)
            #expect(!kind.symbolName.isEmpty)
        }
        #expect(Set(CategoryKind.allCases.map(\.name)).count == CategoryKind.allCases.count)
        #expect(CategoryKind.office.symbolName == "building.2.fill")
        #expect(CategoryKind.utilities.symbolName == "bolt.fill")
    }
}
