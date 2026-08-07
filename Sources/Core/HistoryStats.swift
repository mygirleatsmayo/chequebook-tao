import Foundation

/// The Transaction History panel: select a row, see stats for every
/// transaction in the account that shares its name.
public enum HistoryStats {

    public struct Entry: Equatable, Sendable {
        public var date: Date
        public var amount: Decimal
    }

    public struct Summary: Equatable, Sendable {
        public var name: String
        public var count: Int
        public var total: Decimal
        public var average: Decimal
        public var thisMonth: Decimal
        public var lastMonth: Decimal
        public var thisYear: Decimal
        public var lastYear: Decimal
        public var entries: [Entry]
    }

    /// Stats for all rows in `accountID`'s register whose display name matches
    /// `name` (case-insensitive, trimmed).
    public static func summary(
        forName name: String,
        accountID: UUID,
        in file: RegisterFile,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let needle = name.trimmingCharacters(in: .whitespaces)
        let rows = RegisterEngine.rows(for: accountID, in: file).filter {
            $0.displayName.trimmingCharacters(in: .whitespaces)
                .compare(needle, options: [.caseInsensitive]) == .orderedSame
        }

        let thisMonthComps = calendar.dateComponents([.year, .month], from: today)
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let lastMonthComps = calendar.dateComponents([.year, .month], from: lastMonthDate)
        let thisYear = calendar.component(.year, from: today)

        var total: Decimal = 0
        var thisMonthTotal: Decimal = 0
        var lastMonthTotal: Decimal = 0
        var thisYearTotal: Decimal = 0
        var lastYearTotal: Decimal = 0
        var entries: [Entry] = []

        for row in rows {
            total += row.amount
            entries.append(Entry(date: row.date, amount: row.amount))
            let comps = calendar.dateComponents([.year, .month], from: row.date)
            if comps.year == thisMonthComps.year && comps.month == thisMonthComps.month {
                thisMonthTotal += row.amount
            }
            if comps.year == lastMonthComps.year && comps.month == lastMonthComps.month {
                lastMonthTotal += row.amount
            }
            if comps.year == thisYear { thisYearTotal += row.amount }
            if comps.year == thisYear - 1 { lastYearTotal += row.amount }
        }

        let average: Decimal
        if rows.isEmpty {
            average = 0
        } else {
            average = total / Decimal(rows.count)
        }

        return Summary(
            name: needle, count: rows.count, total: total, average: average,
            thisMonth: thisMonthTotal, lastMonth: lastMonthTotal,
            thisYear: thisYearTotal, lastYear: lastYearTotal, entries: entries
        )
    }
}
