import Foundation

/// Export an account's register (complete or filtered) as CSV — same purpose
/// as the original's "Export Account Transaction Lists as a CSV File".
public enum CSVExporter {

    public static func export(
        rows: [RegisterRow],
        accountType: AccountType,
        calendar: Calendar = .current
    ) -> String {
        let outColumn = accountType == .deposit ? "Withdraw" : "Charge"
        let inColumn = accountType == .deposit ? "Deposit" : "Payment"
        var lines: [String] = []
        lines.append(["Date", "Chk#", "Transaction Name", outColumn, inColumn, "Balance", "Memo"]
            .map(quote).joined(separator: ","))

        for row in rows {
            let comps = calendar.dateComponents([.year, .month, .day], from: row.date)
            let date = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            let outAmount = row.amount < 0 ? plain(-row.amount) : ""
            let inAmount = row.amount >= 0 && row.amount != 0 ? plain(row.amount) : ""
            lines.append([
                date, row.checkNumber, row.displayName, outAmount, inAmount,
                plain(row.balance), row.memo
            ].map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func plain(_ value: Decimal) -> String {
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 2, .bankers)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func quote(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
