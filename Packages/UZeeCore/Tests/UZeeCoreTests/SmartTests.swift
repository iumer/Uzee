import Foundation
import Testing
@testable import UZeeCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }
private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

/// AI-02 receipt reading, IMP-001…009 statement reading (synthesised layouts; real bank samples are added as IMP-008x).
@Suite("Text scanning")
struct TextScanTests {
    @Test("Amounts with grouping, decimals, markers and signs")
    func amounts() {
        let found = TextScan.amounts(in: "Rs 1,250.00 and (500) and 2,000.00 CR and -75 and 12,50,000")
        #expect(found.map(\.value) == [1250, 500, 2000, 75, 1_250_000])
        #expect(found[0].currencyMarker == "rs" && found[0].hasDecimals && found[0].hasGrouping)
        #expect(found[1].isNegative)
        #expect(found[2].creditDebit == "cr")
        #expect(found[3].isNegative)
    }

    @Test("Dates, times, phone numbers and references are not amounts")
    func notAmounts() {
        #expect(TextScan.amounts(in: "06/10/2026 12:45 Tel 03001234567 INV1234 5th").isEmpty)
        #expect(TextScan.amounts(in: "Rs1500").map(\.value) == [1500])
    }

    @Test("Numeric and named dates, day first")
    func dates() {
        #expect(TextScan.dates(in: "Date: 06/10/2026").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "6-10-26").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "2026-10-06").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "06 Oct 2026").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "06-OCT-26 POS").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "Oct 6, 2026").map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "12/31/2026").map(\.date) == [day(2026, 12, 31)])
        #expect(TextScan.dates(in: "06 Oct", defaultYear: 2026).map(\.date) == [day(2026, 10, 6)])
        #expect(TextScan.dates(in: "06 Oct").isEmpty)
        #expect(TextScan.dates(in: "31/02/2026").isEmpty)
    }
}

@Suite("Receipt reading")
struct ReceiptReadingTests {
    let today = day(2026, 10, 6)

    // UI-034 (unit part): amount, date and merchant from a typical till slip.
    @Test("Grand total, date and shop name")
    func tillSlip() {
        let lines = ["*** IMTIAZ SUPER MARKET ***", "Gulberg III, Lahore", "NTN 1234567-8", "Date: 05/10/2026  Time 18:42",
                     "Milk 1L        2 x 280     560.00", "Bread                      190.00", "Sub Total               2,350.00",
                     "GST 18%                     423.00", "Grand Total             2,773.00", "Cash                    3,000.00",
                     "Change                    227.00"]
        let reading = ReceiptParser.read(lines, currency: .pkr, today: today)
        #expect(reading.amount == Money(major: 2_773, .pkr))
        #expect(reading.date == day(2026, 10, 5))
        #expect(reading.merchant == "Imtiaz Super Market")
    }

    @Test("Total on the next line, and no total line at all")
    func totals() {
        let split = ReceiptParser.read(["Kababjees", "TOTAL", "Rs 3,450"], currency: .pkr, today: today)
        #expect(split.amount == Money(major: 3_450, .pkr))
        let none = ReceiptParser.read(["Shell Gulberg", "Super 95  50.2 L", "Rs 14,517.00"], currency: .pkr, today: today)
        #expect(none.amount == Money(major: 14_517, .pkr))
        #expect(none.merchant == "Shell Gulberg")
    }

    // A tilted photo of a courier parcel label: the table puts "Amount:" and its value in different cells, and
    // the address holds a number that looks like money. Made-up details in the label's layout.
    @Test("Courier label: amount next to its label, shipper as the shop, category from the items")
    func courierLabel() {
        let pieces = [
            ReceiptPiece(text: "PostEx", x: 0.08, y: 0.80, width: 0.12, height: 0.04),
            ReceiptPiece(text: "LHE", x: 0.88, y: 0.84, width: 0.05, height: 0.03),
            ReceiptPiece(text: "#12345", x: 0.35, y: 0.79, width: 0.08, height: 0.03),
            ReceiptPiece(text: "Consignee Information", x: 0.13, y: 0.72, width: 0.2, height: 0.03),
            ReceiptPiece(text: "Order Information", x: 0.65, y: 0.74, width: 0.15, height: 0.03),
            ReceiptPiece(text: "Name:", x: 0.08, y: 0.67, width: 0.06, height: 0.03),
            ReceiptPiece(text: "Test Customer", x: 0.18, y: 0.67, width: 0.14, height: 0.03),
            ReceiptPiece(text: "Tracking No:", x: 0.37, y: 0.62, width: 0.1, height: 0.03),
            ReceiptPiece(text: "98765432101234", x: 0.46, y: 0.625, width: 0.16, height: 0.03),
            ReceiptPiece(text: "House 123,456 Block C-1 Test Town", x: 0.18, y: 0.58, width: 0.22, height: 0.03),
            ReceiptPiece(text: "Shipper Information", x: 0.16, y: 0.51, width: 0.18, height: 0.03),
            ReceiptPiece(text: "Name:", x: 0.08, y: 0.455, width: 0.06, height: 0.03),
            ReceiptPiece(text: "TEST MOTORS", x: 0.18, y: 0.46, width: 0.14, height: 0.03),
            ReceiptPiece(text: "Amount:", x: 0.63, y: 0.49, width: 0.07, height: 0.03),
            ReceiptPiece(text: "1529.50/-", x: 0.71, y: 0.497, width: 0.09, height: 0.03),
            ReceiptPiece(text: "Date:", x: 0.63, y: 0.43, width: 0.05, height: 0.03),
            ReceiptPiece(text: "1/10/2026", x: 0.71, y: 0.437, width: 0.09, height: 0.03),
            ReceiptPiece(text: "Order Details:", x: 0.08, y: 0.3, width: 0.12, height: 0.03),
            ReceiptPiece(text: "[ 1 x CERAMIC COATING WAX 200g 1 Wax - ]", x: 0.2, y: 0.305, width: 0.4, height: 0.03)
        ]
        let reading = ReceiptParser.read(pieces: pieces, currency: .pkr, today: today)
        #expect(reading.amount == Money(minorUnits: 152_950, currency: .pkr))
        #expect(reading.date == day(2026, 10, 1))
        #expect(reading.merchant == "Test Motors")
        #expect(reading.categoryKey == "transport.car_maintenance")
    }

    @Test("Without positions: the label's value on a merged line; never an address number")
    func mergedCells() {
        let lines = ["PostEx", "House 123,456 Block C-1", "Amount", "Shipper Information   Destination:   Lahore   1529.50/-"]
        #expect(ReceiptParser.read(lines, currency: .pkr, today: today).amount == Money(minorUnits: 152_950, currency: .pkr))
        let noLabel = ["Test Store", "House 123,456 Block C-1", "Rs 1,830/-"]
        #expect(ReceiptParser.read(noLabel, currency: .pkr, today: today).amount == Money(major: 1_830, .pkr))
        #expect(TextScan.amounts(in: "1,830/-").first?.value == 1_830)
    }

    @Test("Category from the shop or the items")
    func categoryHints() {
        #expect(CategorySuggester.systemKey(inText: ["DVAGO Pharmacy", "Panadol tablets"]) == "health.medicine")
        #expect(CategorySuggester.systemKey(inText: ["Medical Store"]) == "health.medicine")
        #expect(CategorySuggester.systemKey(inText: ["Kababjees", "Chicken Karahi"]) == "food.dining_out")
        #expect(CategorySuggester.systemKey(inText: ["Al-Fatah", "Milk 1L"]) == "food.groceries")
        #expect(CategorySuggester.systemKey(inText: ["Shell Gulberg", "Super 95 50.2 L"]) == "transport.fuel")
        #expect(CategorySuggester.systemKey(inText: ["Thank you"]) == nil)
    }

    @Test("Future and very old dates are ignored; empty text reads nothing")
    func implausible() {
        let reading = ReceiptParser.read(["Cafe", "Valid till 06/12/2026", "Opened 01/01/2020"], currency: .pkr, today: today)
        #expect(reading.date == nil)
        #expect(ReceiptParser.read([], currency: .pkr, today: today).isEmpty)
    }
}

@Suite("Statement reading")
struct StatementReadingTests {
    // IMP-001 (generic layout): date, description, debit/credit by running balance, oldest first.
    @Test("Rows with running balance, oldest first")
    func balanceOldestFirst() {
        let lines = [
            "Account Statement  Period 01/09/2026 to 30/09/2026",
            "Date        Description                       Amount        Balance",
            "Opening Balance                                             100,000.00",
            "01/09/2026  POS PURCHASE FOODPANDA LHR 4411    1,250.00      98,750.00",
            "            ORDER 99812",
            "05/09/2026  SALARY SEPTEMBER                 560,000.00     658,750.00",
            "06/09/2026  IBFT TO MEEZAN 0021              50,000.00      608,750.00",
            "Closing Balance                                             608,750.00"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.signSource == .balance)
        #expect(reading.rows.map(\.amount) == [dec("-1250"), dec("560000"), dec("-50000")])
        #expect(reading.rows.map(\.date) == [day(2026, 9, 1), day(2026, 9, 5), day(2026, 9, 6)])
        #expect(reading.rows[0].description == "POS PURCHASE FOODPANDA LHR 4411 ORDER 99812")
        #expect(reading.openingBalance == 100_000)
        #expect(reading.closingBalance == dec("608750"))
        #expect(reading.first == day(2026, 9, 1) && reading.last == day(2026, 9, 6))
    }

    @Test("Newest first, with debit, credit and balance columns")
    func newestFirstColumns() {
        let lines = [
            "Txn Date   Value Date  Particulars              Debit       Credit       Balance",
            "06-Oct-26  06-Oct-26   Netflix.com              1,100.00    0.00         45,000.00",
            "05-Oct-26  05-Oct-26   Cash deposit             0.00        20,000.00    46,100.00",
            "04-Oct-26  04-Oct-26   ATM withdrawal           5,000.00    0.00         26,100.00"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.rows.map(\.amount) == [dec("-1100"), dec("20000"), dec("-5000")])
        #expect(reading.rows[0].description == "Netflix.com")
    }

    @Test("CR/DR markers and words decide direction without a balance")
    func markers() {
        let reading = StatementParser.read(lines: ["01/10/2026 Funds received from Ali 5,000.00 CR",
                                                   "02/10/2026 Bill payment K-Electric 3,200.00 DR",
                                                   "03/10/2026 Salary October 250,000.00"])
        #expect(reading.rows.map(\.amount) == [dec("5000"), dec("-3200"), dec("250000")])
    }

    // IMP-006: nothing that looks like a statement.
    @Test("Text without rows reads nothing")
    func unsupported() {
        #expect(StatementParser.read(lines: ["Dear customer", "Thank you for banking with us"]).rows.isEmpty)
    }

    @Test("Short payees from statement descriptions")
    func payees() {
        #expect(StatementParser.payee(from: "POS PURCHASE FOODPANDA LHR 4411") == "Foodpanda")
        #expect(StatementParser.payee(from: "Netflix.com") == "Netflix.com")
        #expect(StatementParser.payee(from: "IBFT 00123456") == "IBFT 00123456")
    }

    // IMP-009 (unit part): CSV columns by name.
    @Test("CSV with debit and credit columns, quoted fields")
    func csv() {
        let text = """
        Date,Description,Debit,Credit,Balance
        2026-10-01,"Daraz, order 55",6200.00,,93800.00
        2026-10-02,Salary,,560000.00,653800.00
        """
        let reading = StatementParser.read(csv: text)
        #expect(reading?.rows.map(\.amount) == [dec("-6200"), dec("560000")])
        #expect(reading?.rows.first?.description == "Daraz, order 55")
        #expect(StatementParser.read(csv: "name,phone\nAli,0300") == nil)
    }

    @Test("CSV with one signed amount column")
    func csvSigned() {
        let reading = StatementParser.read(csv: "Date,Title,Amount\n06/10/2026,Careem,-850\n07/10/2026,Refund,300\n")
        #expect(reading?.rows.map(\.amount) == [dec("-850"), dec("300")])
    }

    @Test("CSV reader handles quotes and blank lines")
    func csvReader() {
        #expect(CSVReader.rows("a,\"b \"\"x\"\"\",c\r\n\r\n1,2,3") == [["a", "b \"x\"", "c"], ["1", "2", "3"]])
    }
}

@Suite("Duplicates")
struct DuplicateTests {
    // IMP-004 / IMP-005: same account, amount and direction, same day or one day apart; one match each.
    @Test("Matches by account, amount and date")
    func matches() {
        let hbl = UUID(), meezan = UUID()
        func txn(_ account: UUID, _ amount: Int64, _ date: LocalDate) -> MoneyTransaction {
            MoneyTransaction(kind: amount < 0 ? .expense : .income, occurredAt: date.startDate(in: TimeZone(identifier: "UTC")!), localDate: date,
                             timeZoneID: "GMT", amount: Money(major: abs(amount), .pkr),
                             legs: [TransactionLeg(accountID: account, amount: Money(major: amount, .pkr), role: .main)])
        }
        let saved = [txn(hbl, -1_250, day(2026, 9, 1)), txn(hbl, -1_250, day(2026, 9, 2)), txn(meezan, -500, day(2026, 9, 3))]
        let rows = [DuplicateFinder.Candidate(date: day(2026, 9, 1), amount: Money(major: -1_250, .pkr)),
                    DuplicateFinder.Candidate(date: day(2026, 9, 1), amount: Money(major: -1_250, .pkr)),
                    DuplicateFinder.Candidate(date: day(2026, 9, 1), amount: Money(major: -1_250, .pkr)),
                    DuplicateFinder.Candidate(date: day(2026, 9, 3), amount: Money(major: -500, .pkr)),
                    DuplicateFinder.Candidate(date: day(2026, 9, 1), amount: Money(major: 1_250, .pkr))]
        let found = DuplicateFinder.matches(rows, accountID: hbl, in: saved)
        #expect(found[0] == saved[0].id)
        #expect(found[1] == saved[1].id)
        #expect(found[2] == nil)
        #expect(found[3] == nil)
        #expect(found[4] == nil)
    }
}

@Suite("Receipt review fixes")
struct ReceiptReviewTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)

    func amount(_ lines: [String]) -> Money? { ReceiptParser.read(lines, currency: .pkr, today: today).amount }

    @Test("Cash paid and change aren't the total")
    func paidAmount() {
        #expect(amount(["Shop", "Total   2,773", "Paid Amount   3,000", "Change   227"]) == Money(minorUnits: 277_300, currency: .pkr))
    }

    @Test("The amount after discount wins")
    func netPayable() {
        #expect(amount(["Shop", "Total Amount   3,000", "Discount   -300", "Net Payable   2,700"]) == Money(minorUnits: 270_000, currency: .pkr))
    }

    @Test("Sub Total split into columns is still a subtotal")
    func splitSubTotal() {
        #expect(amount(["Shop", "Sub   Total   2,500", "GST   450", "Total   2,950"]) == Money(minorUnits: 295_000, currency: .pkr))
        let pieces = [
            ReceiptPiece(text: "Sub", x: 0.1, y: 0.50, width: 0.08, height: 0.02),
            ReceiptPiece(text: "Total", x: 0.19, y: 0.50, width: 0.1, height: 0.02),
            ReceiptPiece(text: "2,500", x: 0.7, y: 0.50, width: 0.1, height: 0.02),
            ReceiptPiece(text: "Total", x: 0.19, y: 0.40, width: 0.1, height: 0.02),
            ReceiptPiece(text: "2,950", x: 0.7, y: 0.40, width: 0.1, height: 0.02)
        ]
        #expect(ReceiptParser.labelledAmount(pieces) == 2950)
    }

    @Test("Letters read inside numbers become digits")
    func ocrDigits() {
        #expect(ReceiptParser.fixDigits("TOTAL 2,77O.00") == "TOTAL 2,770.00")
        #expect(ReceiptParser.fixDigits("Rs 1,25S") == "Rs 1,255")
        #expect(ReceiptParser.fixDigits("Organic Soap") == "Organic Soap")
        #expect(amount(["Shop", "TOTAL 2,77O.00"]) == Money(minorUnits: 277_000, currency: .pkr))
    }

    @Test("Pakistani date formats")
    func dates() {
        #expect(ReceiptParser.read(["Shop", "Date: 05-Oct-26"], currency: .pkr, today: today).date == LocalDate(year: 2026, month: 10, day: 5))
        #expect(ReceiptParser.read(["Shop", "05/10/26 14:32"], currency: .pkr, today: today).date == LocalDate(year: 2026, month: 10, day: 5))
    }
}

@Suite("Receipt fixes from the Mac run")
struct ReceiptMacRunTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)

    @Test("Electricity bill: within due date, and the due date")
    func electricityBill() {
        let reading = ReceiptParser.read(["LESCO", "Bill Month SEP-2026", "Due Date: 15-OCT-2026",
                                          "Payable Within Due Date Rs 18,420", "Payable After Due Date Rs 20,262"],
                                         currency: .pkr, today: today)
        #expect(reading.amount == Money(minorUnits: 1_842_000, currency: .pkr))
        #expect(reading.date == LocalDate(year: 2026, month: 10, day: 15))
    }

    @Test("A seller name stops at the next label")
    func sellerName() {
        let reading = ReceiptParser.read(["PostEx", "Shipper", "Name: SAMPLE MOTORS Return City: Lahore", "COD Amount 1,829.96"],
                                         currency: .pkr, today: today)
        #expect(reading.merchant == "Sample Motors")
    }
}

/// Misses from 20 real shop receipts (public SROIE scans), rebuilt here as made-up slips with the same layouts.
@Suite("Receipt fixes from internet receipts")
struct ReceiptInternetFixTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)

    @Test("A tax percentage next to Total is not the amount")
    func percentNotAmount() {
        let reading = ReceiptParser.read(["SAMPLE TEA HOUSE", "Total Incl. GST @6%", "8.60", "Cash 10.00", "Change 1.40"],
                                         currency: .usd, today: today)
        #expect(reading.amount == Money(minorUnits: 860, currency: .usd))
        let sameLine = ReceiptParser.read(["SAMPLE HARDWARE", "Total (6% GST)   42.90"], currency: .usd, today: today)
        #expect(sameLine.amount == Money(minorUnits: 4_290, currency: .usd))
    }

    @Test("The rounded total wins over the total before rounding")
    func roundedTotal() {
        let labelled = ReceiptParser.read(["SAMPLE MART", "Total Incl. GST 60.31", "Rounding Adj -0.01", "Rounded Total (RM) 60.30",
                                           "Cash 100.00", "Change 39.70"], currency: .usd, today: today)
        #expect(labelled.amount == Money(minorUnits: 6_030, currency: .usd))
        let plainTotals = ReceiptParser.read(["SAMPLE MART", "Total 33.92", "Rounding -0.02", "Total 33.90", "Cash 50.00"],
                                             currency: .usd, today: today)
        #expect(plainTotals.amount == Money(minorUnits: 3_390, currency: .usd))
        // A rounding line alone never makes a smaller figure (tax, subtotal, the adjustment) the total.
        let withTax = ReceiptParser.read(["SAMPLE CAFE", "Total Amount 8.60", "Rounding Adj 0.48", "Total GST 0.49", "Cash 10.00"],
                                         currency: .usd, today: today)
        #expect(withTax.amount == Money(minorUnits: 860, currency: .usd))
    }

    @Test("The shop, not the cashier, the address or a misread logo")
    func shopName() {
        let cashier = ReceiptParser.read(["Cashier:", "TAN SAMPLE YEE", "SAMPLE BOOK STORE", "Total 9.00"], currency: .usd, today: today)
        #expect(cashier.merchant == "Sample Book Store")
        let address = ReceiptParser.read(["Lot 12, Jalan Sample 3", "81100 Johor Bahru", "SAMPLE TRADING SDN BHD", "Total 9.00"],
                                         currency: .usd, today: today)
        #expect(address.merchant == "Sample Trading Sdn Bhd")
        let logo = ReceiptParser.read(["FRwOnL", "Sample Kitchen", "Total 9.00"], currency: .usd, today: today)
        #expect(logo.merchant == "Sample Kitchen")
        let broadway = ReceiptParser.read(["Broadway Pizza", "Grand Total 2,450"], currency: .pkr, today: today)
        #expect(broadway.merchant == "Broadway Pizza")
    }

    @Test("Jumbled words")
    func jumbled() {
        #expect(ReceiptParser.isJumbled("FRwOnL"))
        #expect(ReceiptParser.isJumbled("RSk"))
        #expect(!ReceiptParser.isJumbled("McDonald"))
        #expect(!ReceiptParser.isJumbled("PostEx"))
        #expect(!ReceiptParser.isJumbled("KFC"))
        #expect(!ReceiptParser.isJumbled("Imtiaz"))
    }
}
