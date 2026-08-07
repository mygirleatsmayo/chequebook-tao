import Foundation

/// The "Filter Register View" panel. All active criteria combine with AND.
public struct RegisterFilter: Equatable, Sendable {
    public var dateStart: Date?
    /// When set (and dateStart is set), match a span; otherwise match the single day.
    public var dateEnd: Date?
    public var checkNumberStart: String?
    public var checkNumberEnd: String?
    /// Substring match, case-insensitive.
    public var nameContains: String?
    public var hideTransfers: Bool
    public var amountStart: Decimal?
    public var amountEnd: Decimal?
    /// Substring match, case-insensitive.
    public var memoContains: String?

    public init(
        dateStart: Date? = nil, dateEnd: Date? = nil,
        checkNumberStart: String? = nil, checkNumberEnd: String? = nil,
        nameContains: String? = nil, hideTransfers: Bool = false,
        amountStart: Decimal? = nil, amountEnd: Decimal? = nil,
        memoContains: String? = nil
    ) {
        self.dateStart = dateStart
        self.dateEnd = dateEnd
        self.checkNumberStart = checkNumberStart
        self.checkNumberEnd = checkNumberEnd
        self.nameContains = nameContains
        self.hideTransfers = hideTransfers
        self.amountStart = amountStart
        self.amountEnd = amountEnd
        self.memoContains = memoContains
    }

    public var isEmpty: Bool {
        dateStart == nil && dateEnd == nil
            && checkNumberStart == nil && checkNumberEnd == nil
            && (nameContains ?? "").isEmpty && !hideTransfers
            && amountStart == nil && amountEnd == nil
            && (memoContains ?? "").isEmpty
    }

    public func matches(_ row: RegisterRow, calendar: Calendar = .current) -> Bool {
        if hideTransfers && row.isTransfer { return false }

        if let start = dateStart {
            let dayStart = calendar.startOfDay(for: start)
            if let end = dateEnd {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
                if row.date < dayStart || row.date >= dayEnd { return false }
            } else {
                if !calendar.isDate(row.date, inSameDayAs: start) { return false }
            }
        }

        if let start = checkNumberStart, !start.isEmpty {
            guard let rowNum = Int(row.checkNumber), let startNum = Int(start) else {
                // Non-numeric check filters fall back to exact match.
                if row.checkNumber != start { return false }
                return matchesRest(row)
            }
            if let end = checkNumberEnd, let endNum = Int(end) {
                if rowNum < startNum || rowNum > endNum { return false }
            } else if rowNum != startNum {
                return false
            }
        }

        return matchesRest(row)
    }

    private func matchesRest(_ row: RegisterRow) -> Bool {
        if let needle = nameContains, !needle.isEmpty {
            if !row.displayName.localizedCaseInsensitiveContains(needle) { return false }
        }
        if let needle = memoContains, !needle.isEmpty {
            if !row.memo.localizedCaseInsensitiveContains(needle) { return false }
        }
        if let start = amountStart {
            // Amount filtering compares magnitudes so "45" finds both a $45
            // withdrawal and a $45 deposit.
            let magnitude = abs(row.amount)
            if let end = amountEnd {
                let lo = min(abs(start), abs(end)), hi = max(abs(start), abs(end))
                if magnitude < lo || magnitude > hi { return false }
            } else if magnitude != abs(start) {
                return false
            }
        }
        return true
    }
}

public func abs(_ value: Decimal) -> Decimal {
    value < 0 ? -value : value
}
