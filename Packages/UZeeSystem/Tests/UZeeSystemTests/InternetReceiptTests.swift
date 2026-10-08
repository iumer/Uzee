import Foundation
import Testing
import UZeeCore
@testable import UZeeSystem

/// AI-02 on real printed receipts from the internet: the public ICDAR 2019 SROIE receipts (scanned shop slips,
/// each labelled with its total, date and shop) are downloaded while the test runs (nothing is stored in the repo),
/// read with Vision like a scan, then parsed. Needs the internet; skipped offline.
@Suite("Receipts from the internet", .serialized)
struct InternetReceiptTests {
    struct Label: Decodable {
        let company: String?
        let date: String?
        let total: String?
    }

    static let base = "https://raw.githubusercontent.com/zzzDavid/ICDAR-2019-SROIE/master/data"
    static let count = 30

    static func fetch(_ url: String) async -> Data? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    @Test("Totals on 30 SROIE receipts")
    func sroieTotals() async throws {
        guard await Self.fetch("\(Self.base)/key/000.json") != nil else {
            print("Internet receipts: offline, skipped")
            return
        }
        let today = LocalDate(year: 2019, month: 6, day: 30)  // the receipts are from 2017–2018
        var tried = 0, totals = 0, dates = 0, shops = 0
        var misses: [String] = []
        for index in 0..<Self.count {
            let name = String(format: "%03d", index)
            guard let keyData = await Self.fetch("\(Self.base)/key/\(name).json"),
                  let label = try? JSONDecoder().decode(Label.self, from: keyData),
                  let total = label.total.flatMap({ Decimal(string: $0.replacingOccurrences(of: ",", with: "")) }),
                  let image = await Self.fetch("\(Self.base)/img/\(name).jpg") else { continue }
            tried += 1
            let pieces = try ReceiptTextReader.pieces(from: image)
            let reading = ReceiptParser.read(pieces: pieces, currency: .usd, today: today)
            let expected = try Money.fromMajor(total, .usd)
            if reading.amount == expected {
                totals += 1
            } else {
                misses.append("\(name): read \(reading.amount.map { "\($0.minorUnits)" } ?? "nothing"), printed \(expected.minorUnits)")
            }
            if let printed = label.date, let read = reading.date, Self.sameDay(printed, read) { dates += 1 }
            if let company = label.company, let merchant = reading.merchant,
               company.lowercased().contains(merchant.lowercased().prefix(6)) { shops += 1 }
        }
        print("Internet receipts: totals \(totals)/\(tried), dates \(dates)/\(tried), shops \(shops)/\(tried)")
        for miss in misses { print("  total miss \(miss)") }
        #expect(tried >= 20, "Couldn't download enough receipts")
        // Printed totals must be read right on at least 4 in 5 of these real-world scans.
        #expect(totals * 5 >= tried * 4, "Totals right on \(totals) of \(tried)")
    }

    /// "25/12/2018" (day first, as SROIE prints it) or "2018-12-25" against what the parser read.
    static func sameDay(_ printed: String, _ read: LocalDate) -> Bool {
        let numbers = printed.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 3 else { return false }
        if numbers[0] > 31 { return numbers[0] == read.year && numbers[1] == read.month && numbers[2] == read.day }
        let year = numbers[2] < 100 ? 2000 + numbers[2] : numbers[2]
        return year == read.year && numbers[1] == read.month && numbers[0] == read.day
    }
}
