import Foundation

/// Export an account's register as CSV in the ORIGINAL app's exact format
/// (verified against real exports):
///
///   SUB ACCOUNT,DATE,CHECK#,TRANSACTION NAME,WITHDRAW,DEPOSIT,BALANCE,MEMO
///   "principalAcct","26/06/20",,"start",,"£300.00","£300.00",
///
/// - Header row unquoted; data fields quoted (empty fields stay empty).
/// - Amounts carry the locale currency symbol.
/// - Dates use the locale's short format (day-first in the UK, like the
///   original on a UK Mac).
/// - Credit accounts substitute CHARGE/PAYMENT for WITHDRAW/DEPOSIT.
public enum CSVExporter {

    public static func export(
        rows: [RegisterRow],
        account: Account,
        locale: Locale = .current
    ) -> String {
        let money = NumberFormatter()
        money.numberStyle = .currency
        money.locale = locale

        let date = DateFormatter()
        date.locale = locale
        date.dateStyle = .short
        date.timeStyle = .none

        let outColumn = account.type == .deposit ? "WITHDRAW" : "CHARGE"
        let inColumn = account.type == .deposit ? "DEPOSIT" : "PAYMENT"

        var lines: [String] = []
        lines.append("SUB ACCOUNT,DATE,CHECK#,TRANSACTION NAME,\(outColumn),\(inColumn),BALANCE,MEMO")

        func subaccountName(_ id: UUID?) -> String {
            guard let id else { return "principalAcct" }
            return account.subaccounts.first { $0.id == id }?.name ?? "principalAcct"
        }
        func moneyString(_ value: Decimal) -> String {
            money.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        }

        for row in rows {
            let outAmount = row.amount < 0 ? moneyString(-row.amount) : ""
            let inAmount = row.amount > 0 ? moneyString(row.amount) : ""
            let fields = [
                subaccountName(row.subaccountID),
                date.string(from: row.date),
                row.checkNumber,
                row.displayName,
                outAmount,
                inAmount,
                moneyString(row.balance),
                row.memo,
            ]
            lines.append(fields.map(quoteUnlessEmpty).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The original quotes every non-empty field and leaves empty ones bare.
    static func quoteUnlessEmpty(_ field: String) -> String {
        guard !field.isEmpty else { return "" }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
