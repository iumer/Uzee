import Foundation

/// Transactions as a CSV file for Numbers, Excel or Google Sheets (EXP-01). One row per account leg, so a
/// transfer shows money leaving one account and arriving in the other; amounts are signed for that account.
public enum CSVExport {
    public static let header = ["Date", "Type", "Account", "Amount", "Currency", "Category", "Payee", "Note", "Status"]

    public static func transactions(_ transactions: [MoneyTransaction], ledger: LedgerSnapshot) -> String {
        var lines = [header.joined(separator: ",")]
        let rows = transactions.filter { $0.deletedAt == nil }
            .sorted { ($0.localDate, $0.occurredAt) < ($1.localDate, $1.occurredAt) }
        for transaction in rows {
            for leg in transaction.legs {
                let fields = [
                    transaction.localDate.description,
                    transaction.kind.name,
                    ledger.account(leg.accountID)?.name ?? "",
                    "\(leg.amount.decimalValue)",
                    leg.amount.currency.code,
                    ledger.categoryPath(transaction.categoryID) ?? "",
                    transaction.payeeName ?? "",
                    transaction.note ?? "",
                    transaction.status == .pending ? "Pending" : "Posted"
                ]
                lines.append(fields.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when it holds a comma, quote or line break; a leading = + - @ is guarded so a
    /// spreadsheet doesn't run it as a formula (amounts are numbers and stay as they are).
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+@".contains(first) || (first == "-" && Decimal(string: value) == nil) {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
