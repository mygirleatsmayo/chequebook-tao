import AppKit
import Foundation

/// Display formatting. Follows the Mac's language & region settings — the
/// original hardcoded US formats; this is the one deliberate modernization.
enum Format {

    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    /// "1,234.56" style, no symbol — used for editing fields.
    static let plainNumber: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = .current
        return f
    }()

    static func money(_ value: Decimal) -> String {
        currency.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Money in the original's combined-column style: negatives as ($45.00).
    static func moneyParens(_ value: Decimal) -> String {
        if value < 0 {
            return "(" + money(-value) + ")"
        }
        return money(value)
    }

    /// Positive magnitude for the split Withdraw/Deposit columns.
    static func magnitude(_ value: Decimal) -> String {
        money(value < 0 ? -value : value)
    }

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        f.locale = .current
        return f
    }()

    static func date(_ date: Date) -> String {
        shortDate.string(from: date)
    }
}

/// Colors used by the register. v0.4 turns this into a full theme system;
/// keeping the type in place now so views never hardcode colors.
struct Theme {
    var negativeAmount: NSColor = .systemRed
    var creditBalance: NSColor = .systemRed
    var regularText: NSColor = .labelColor
    var newEntryText: NSColor = .tertiaryLabelColor

    static let current = Theme()
}
