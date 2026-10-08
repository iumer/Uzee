import Foundation
import Testing
@testable import UZeeCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }
private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

/// Statement layouts of Pakistani banks and wallets (IMP-001, IMP-009). Every name, number and amount
/// here is made up; only the shape of each line copies the bank's real statement.
@Suite("Statement layouts")
struct StatementLayoutTests {
    @Test("MCB PDF: Dr/Cr amounts, reference numbers, wrapped descriptions, newest first")
    func mcbPDF() {
        let lines = [
            "Account Statement",
            "0123456789012345 | AYESHA KHAN",
            "Opening Balance : 1,000.00",
            "Closing Balance : 2,465.00",
            "Currency : PKR",
            "Date                Description                                     Reference Number     Amount         Balance",
            "05 Oct 2026         IBFT SENDING-MCB LIVE - ALI RAZA -              1000000011        5,000.00Dr       2,465.00",
            "                    11112222333344 - MEEZAN BANK LTD - Originator : -",
            "                    AYESHA KHAN - 0123456789012345",
            "05 Oct 2026         IBFT SENDING FEE-MCB LIVE - - - - Originator : - -   1000000012      15.00Dr      7,465.00",
            "03 Oct 2026         INTERBANK FUNDS RECEIVING - AYESHA KHAN - - MCB - Originator : - BILAL AHMED   1000000013   6,480.00Cr   7,480.00"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .mcb)
        #expect(reading.currencyCode == "PKR")
        #expect(reading.rows.map(\.amount) == [dec("-5000"), dec("-15"), dec("6480")])
        #expect(reading.rows.map(\.date) == [day(2026, 10, 5), day(2026, 10, 5), day(2026, 10, 3)])
        #expect(reading.openingBalance == 1_000)
        #expect(reading.rows[0].description.contains("MEEZAN BANK LTD"))
        #expect(reading.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "IBFT Sending Fee", "Bilal Ahmed"])
    }

    @Test("HBL PDF: value dates, debit or credit then balance, POS merchant on the last lines")
    func hblPDF() {
        let lines = [
            "Account Activity generated through HBL Mobile",
            "IBAN: PK00HABB0000000000000001",
            " Transaction",
            " Date              Value Date        Description                                        Debit               Credit                  Balance",
            " 30-06-2026        30-06-2026        Funds Transfer SM00000000A0TEST TO                          4,200.00                                        10,000.00",
            "                                     SARA KHAN IBAN XXXX-0001 Thru",
            "                                     Raast MBMB00000000000000001",
            " 30-06-2026        30-06-2026        Debit Card/POS 111111111111                                 2,600.00                                        14,200.00",
            "                                     1234567+++++0000 30/06 222222222222 PKR",
            "                                     2600.00 333333 0106 1234567 FOOD PANDA",
            "                                     KARACHI",
            " 29-06-2026        29-06-2026        Funds Transfer 4444444444444444 FRM MEZ                                             6,800.00                16,800.00",
            "                                     TEST USERX",
            " 28-06-2026        28-06-2026        ATM Cash Paid 5555555555555555                                500.00                                        10,000.00"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .hbl)
        #expect(reading.signSource == .balance)
        #expect(reading.rows.map(\.amount) == [dec("-4200"), dec("-2600"), dec("6800"), dec("-500")])
        #expect(reading.rows[1].description.hasSuffix("FOOD PANDA KARACHI"))
        #expect(StatementParser.payee(from: reading.rows[0].description) == "Sara Khan")
        #expect(StatementParser.payee(from: reading.rows[1].description) == "Food Panda Karachi")
    }

    @Test("Meezan PDF: + PKR and − PKR amounts glued to the currency")
    func meezanPDF() {
        let lines = [
            "Account Statement",
            "Account Title    Account Number    IBAN",
            "TEST USER        00000000000000    PK00MEZN0000000000000001",
            "Currency         From Date         To Date",
            "Pakistan Rupee(PKR)   08 Oct 2025   08 Oct 2026",
            "Opening Balance    Closing Balance",
            "PKR737.01          PKR194.01",
            "Booking Date   Description   Credit   Debit   Available Balance",
            "08 Oct 2025   Money Received from   + PKR42,500.00      PKR43,237.01",
            "               ALI RAZA HBL",
            "           XXXX0000000001 STAN(100001)",
            "08 Oct 2025   Charges Taxes Plus      - PKR43.00   PKR43,194.01",
            "               FED STAN(100002)",
            "08 Oct 2025   Money Transferred to    - PKR43,000.00    PKR194.01",
            "               ALI RAZA HBL"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .meezan)
        #expect(reading.currencyCode == "PKR")
        #expect(reading.rows.map(\.amount) == [dec("42500"), dec("-43"), dec("-43000")])
        #expect(StatementParser.payee(from: reading.rows[0].description) == "Ali Raza HBL")
    }

    @Test("NayaPay PDF: −Rs./+Rs. amounts, zero card holds skipped, wrapped details")
    func nayapayPDF() {
        let lines = [
            "Account Statement",
            "01 Jul 2025 - 30 Jun 2026",
            "NayaPay ID    01 Jul 2025    Total Income    30 Jun 2026",
            "Opening Balance   Total Spent   Closing Balance",
            "Rs. 128.15   Rs. 283.83   Rs. 844.32",
            "TIME   TYPE   DESCRIPTION   AMOUNT   BALANCE",
            "31 Jul 2025   Card   TEST SHOP LOS ANGELES US   -Rs. 0   Rs. 128.15",
            "05:53 PM      Authorization    Service Charges Rs. 0",
            "04 Sep 2025   Raast In   Incoming fund transfer from Ali Raza   +Rs. 1,000   Rs. 1,128.15",
            "03:22 PM                 SadaPay-0001",
            "                         Transaction ID",
            "04 Sep 2025   Online   Paid to Google One London GB   -Rs. 283.83   Rs. 844.32",
            "03:22 PM               Visa xxxx0000"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .nayapay)
        #expect(reading.rows.map(\.amount) == [dec("1000"), dec("-283.83")])
        #expect(!reading.rows[0].description.contains("03:22"))
        #expect(reading.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "Google One London"])
    }

    @Test("SadaPay PDF: blocks with the description around the date and a signed amount")
    func sadapayPDF() {
        let lines = [
            "Account Statement",
            "Name: Test User",
            "Account Currency: Pakistani rupee (PKR)",
            "IBAN: PK00 SADA 0000 0000 00000001",
            "    Total debit                Total credit",
            "    3305.65                  2000.00",
            "Account transactions from 1 October 2025 - 8 October 2026",
            "            Date                       Description                              Debit/Credit",
            "                                       From ALI RAZA (Meezan Bank",
            "     4 Oct, 2025                       (MBL))",
            "       09:28 PM",
            "                                                                               + 2,000.00",
            "                                       (Incoming transfer)",
            "                                       To SARA KHAN (Mobilink",
            "     4 Oct, 2025                       Microfinance Bank (MMBL))",
            "       09:29 PM",
            "                                                                                 - 2,400.00",
            "                                       (Outgoing transfer)",
            "Note: This is a system generated statement and does not require a signature.",
            "Generated on: 8 Oct, 2026 [2:06 AM (PKT)]                                          Page 1 of 2",
            "IBAN: PK00 SADA 0000 0000 00000001",
            "Account transactions from 1 October 2025 - 8 October 2026",
            "            Date                       Description                              Debit/Credit",
            "     5 Oct, 2025                       Netflix.com Los Gatos Sgp",
            "       03:37 AM                        (Card)                                    - 905.65"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .sadapay)
        #expect(reading.currencyCode == "PKR")
        #expect(reading.signSource == .columns)
        #expect(reading.rows.map(\.amount) == [dec("2000"), dec("-2400"), dec("-905.65")])
        #expect(reading.rows.map(\.date) == [day(2025, 10, 4), day(2025, 10, 4), day(2025, 10, 5)])
        #expect(reading.rows.map(\.description) == ["From ALI RAZA (Meezan Bank (MBL))", "To SARA KHAN (Mobilink Microfinance Bank (MMBL))",
                                                    "Netflix.com Los Gatos Sgp"])
        #expect(StatementParser.payee(from: reading.rows[0].description) == "Ali Raza")
        #expect(StatementParser.payee(from: reading.rows[1].description) == "Sara Khan")
    }

    @Test("Wise PDF: amounts on the description line, date below, one currency per statement")
    func wisePDF() {
        let lines = [
            "Wise Payments Ltd.",
            "USD statement",
            "1 January 2025 [GMT+05:00] - 31 December 2025 [GMT+05:00]",
            "USD on 31 December 2025 [GMT+05:00]                     149.70 USD",
            "Description                                   Incoming        Outgoing        Amount",
            "Received money from Ali Raza with reference          149.70                         149.70",
            "26 December 2025 | Transaction: TRANSFER-1000000001",
            "Sent money to Test User (fee: 12.07 USD)                          -2,041.93          0.00",
            "21 December 2025 | Transaction: TRANSFER-1000000002",
            "Wise Charges for: TRANSFER-1000000002                                 -12.07       2,041.93",
            "21 December 2025 | Transaction: FEE-TRANSFER-1000000002",
            "Converted 103.26 USD to 87.73 EUR                    2,054.00                       2,054.00",
            "19 December 2025 | Transaction: BALANCE-1"
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .wise)
        #expect(reading.currencyCode == "USD")
        #expect(reading.rows.map(\.amount) == [dec("149.70"), dec("-2041.93"), dec("-12.07"), dec("2054")])
        #expect(reading.rows.map(\.date) == [day(2025, 12, 26), day(2025, 12, 21), day(2025, 12, 21), day(2025, 12, 19)])
        #expect(reading.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "Test User", "Wise fees", "Currency conversion"])
    }

    @Test("An empty Wise statement reads no rows but is still recognised")
    func wiseEmpty() {
        let reading = StatementParser.read(lines: ["Wise Payments Ltd.", "PKR statement",
                                                   "PKR on 31 December 2025 [GMT+05:00]        0.00 PKR",
                                                   "Description        Incoming        Outgoing        Amount"])
        #expect(reading.rows.isEmpty)
        #expect(reading.source == .wise)
        #expect(reading.currencyCode == "PKR")
    }

    @Test("MCB CSV: separate Cr/Dr column")
    func mcbCSV() {
        let text = """
        0123456789012345,AYESHA KHAN
        Opening Balance,PKR 1000.00
        Closing Balance,PKR 2465.00
        Date,Description,Reference Number,Currency,Amount,Cr/Dr,Currency,Balance
        05 Oct 2026,IBFT SENDING-MCB LIVE - ALI RAZA - 11112222333344 - MEEZAN BANK LTD - Originator :  - AYESHA KHAN - 0123456789012345,1000000011,PKR,5000.00,Dr,PKR,2465.00
        05 Oct 2026,IBFT SENDING FEE-MCB LIVE -  -  -  - Originator :  -  - ,1000000012,PKR,15.00,Dr,PKR,7465.00
        03 Oct 2026,SALARY CREDIT -  -  -  - Originator :  -  - ,1000000013,PKR,6480.00,Cr,PKR,7480.00
        """
        let reading = StatementParser.read(csv: text)
        #expect(reading?.source == .mcb)
        #expect(reading?.currencyCode == "PKR")
        #expect(reading?.signSource == .balance)
        #expect(reading?.rows.map(\.amount) == [dec("-5000"), dec("-15"), dec("6480")])
        #expect(reading?.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "IBFT Sending Fee", "Salary Credit"])
    }

    @Test("NayaPay CSV: header block, TIMESTAMP column, signed amounts, details over several lines")
    func nayapayCSV() {
        let text = """
        Customer Name,Test User
        NayaPay ID,test
        ,
        Account Statement for:,from 01 Jul 2025 to 30 Jun 2026

        Opening Balance,128.15,Closing Balance,844.32,,Total Spent,"283.83",Total Income,"1,000.00"

        TIMESTAMP,TYPE,DESCRIPTION,AMOUNT,BALANCE
        31 Jul 2025 05:53 PM,Card Authorization,TEST SHOP LOS ANGELES US|null,-0,128.15
        04 Sep 2025 03:22 PM,Raast In,"Incoming fund transfer from Ali Raza
        SadaPay-0001|Transaction ID TESTPKKA000000000000000000000001","+1,000","1,128.15"
        04 Sep 2025 03:22 PM,Online,Paid to Google One London GB|Visa xxxx0000,-283.83,844.32
        """
        let reading = StatementParser.read(csv: text)
        #expect(reading?.source == .nayapay)
        #expect(reading?.rows.map(\.amount) == [dec("1000"), dec("-283.83")])
        #expect(reading?.rows.map(\.date) == [day(2025, 9, 4), day(2025, 9, 4)])
        #expect(reading?.rows.first?.description == "Incoming fund transfer from Ali Raza | SadaPay-0001")
        #expect(reading?.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "Google One London"])
        #expect(reading?.openingBalance == dec("128.15"))
        #expect(reading?.closingBalance == dec("844.32"))
    }

    @Test("MCB CSV header: opening and closing balance with a currency")
    func mcbCSVBalances() {
        let text = """
        Opening Balance,PKR 1000.00
        Closing Balance,PKR 2465.00
        Date,Description,Reference Number,Currency,Amount,Cr/Dr,Currency,Balance
        05 Oct 2026,IBFT RECEIVING,1234567890,PKR,1465.00,Cr,PKR,2465.00
        """
        let reading = StatementParser.read(csv: text)
        #expect(reading?.openingBalance == 1_000)
        #expect(reading?.closingBalance == 2_465)
    }

    @Test("NayaPay PDF in the PDF's own text order: each row stacked over several lines")
    func nayapayStacked() {
        let lines = [
            "Account Statement", "01 Jul 2025 - 30 Jun 2026", "NayaPay ID", "test@nayapay",
            "IBAN", "PK00NAYA0000000000000000",
            "Opening Balance", "Rs. 128.15",
            "TYPE", "DESCRIPTION", "AMOUNT", "BALANCE",
            "31 Jul 2025", "05:53 PM", "Card", "Authorization", "TEST SHOP LOS ANGELES US", "Service Charges Rs. 0", "-Rs. 0", "Rs. 128.15",
            "04 Sep 2025", "03:22 PM", "Raast In", "Incoming fund transfer from Ali Raza", "Service Charges Rs. 0", "+Rs. 1,000", "Rs. 1,128.15",
            "04 Sep 2025", "03:40 PM", "Online", "Paid to Google One London GB", "Service Charges Rs. 0", "-Rs. 283.83", "Rs. 844.32",
        ]
        let reading = StatementParser.read(lines: lines)
        #expect(reading.source == .nayapay)
        #expect(reading.rows.map(\.amount) == [dec("1000"), dec("-283.83")])
        #expect(reading.rows.map(\.balance) == [dec("1128.15"), dec("844.32")])
        #expect(reading.rows.map { StatementParser.payee(from: $0.description) } == ["Ali Raza", "Google One London"])
    }

    @Test("Two readings of one PDF: the one with more transactions wins")
    func bestVersion() {
        let garbled = ["R ce ved mon y", "2,04 . 3"]
        let clean = ["Statement 2025", "05 Oct 2025   Paid to Shop   -1,200.00   800.00", "06 Oct 2025   Salary   +5,000.00   5,800.00"]
        #expect(StatementParser.read(versions: [garbled, clean]).rows.count == 2)
        #expect(StatementParser.read(versions: [clean, garbled]).rows.count == 2)
    }

    @Test("Signs written before a currency: −Rs. 283.83, +Rs. 1,000, + PKR42,500.00")
    func signsBeforeCurrency() {
        let minus = TextScan.amounts(in: "-Rs. 283.83").first
        #expect(minus?.value == dec("283.83") && minus?.isNegative == true)
        let plus = TextScan.amounts(in: "+Rs. 1,000").first
        #expect(plus?.value == 1_000 && plus?.hasPlusSign == true && plus?.isNegative == false)
        #expect(TextScan.amounts(in: "+ PKR42,500.00").first?.hasPlusSign == true)
        #expect(TextScan.amounts(in: "- PKR43.00").first?.isNegative == true)
    }
}
