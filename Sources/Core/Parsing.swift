import Foundation

// MARK: - Date parsing

/// Which side of an ambiguous slash date is the day.
public enum DateOrder: String, Codable, Sendable {
    /// 2/5/13 = February 5 (the original app's behavior).
    case monthFirst
    /// 2/5/13 = 5 February (UK banks).
    case dayFirst
}

public enum DateParsing {

    /// Parse the date formats seen in bank exports, QIF files, and hand entry:
    /// `2/5/13`, `02/05/2013`, `2013-02-05`, `5 Feb 2013`, `Feb 5, 2013`.
    /// Returns nil for non-dates ("In-process", "Pending", header text).
    public static func parse(_ raw: String, order: DateOrder = .monthFirst, calendar: Calendar = .current) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // ISO 2013-02-05
        if let date = parseISO(s, calendar: calendar) { return date }

        // Slash / dash / dot numerics: 2/5/13, 02-05-2013, 2.5.13
        let separators = CharacterSet(charactersIn: "/-.")
        let parts = s.components(separatedBy: separators)
        if parts.count == 3,
           let a = Int(parts[0].trimmingCharacters(in: .whitespaces)),
           let b = Int(parts[1].trimmingCharacters(in: .whitespaces)),
           let c = Int(parts[2].trimmingCharacters(in: .whitespaces)) {
            return assembleNumeric(a, b, c, order: order, calendar: calendar)
        }

        // Month-name forms.
        if let date = parseMonthName(s, calendar: calendar) { return date }

        return nil
    }

    private static func parseISO(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.components(separatedBy: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func assembleNumeric(_ a: Int, _ b: Int, _ c: Int, order: DateOrder, calendar: Calendar) -> Date? {
        var year = c
        if year < 100 { year += year >= 70 ? 1900 : 2000 }
        var month: Int
        var day: Int
        switch order {
        case .monthFirst: month = a; day = b
        case .dayFirst: day = a; month = b
        }
        // Disambiguate impossible values regardless of the preferred order:
        // 25/12/13 is Dec 25 even in monthFirst mode.
        if month > 12 && day <= 12 { swap(&month, &day) }
        guard (1...12).contains(month), (1...31).contains(day), (1900...2200).contains(year) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static let monthNames: [String: Int] = {
        var map: [String: Int] = [:]
        let long = ["january", "february", "march", "april", "may", "june", "july",
                    "august", "september", "october", "november", "december"]
        for (index, name) in long.enumerated() {
            map[name] = index + 1
            map[String(name.prefix(3))] = index + 1
        }
        map["sept"] = 9
        return map
    }()

    private static func parseMonthName(_ s: String, calendar: Calendar) -> Date? {
        let cleaned = s.replacingOccurrences(of: ",", with: " ")
        let tokens = cleaned.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 2 && tokens.count <= 3 else { return nil }

        var month: Int?
        var day: Int?
        var year: Int?
        for token in tokens {
            let lower = token.lowercased()
            if let m = monthNames[lower] {
                month = m
            } else if let n = Int(token) {
                if n > 31 { year = n < 100 ? (n >= 70 ? n + 1900 : n + 2000) : n }
                else if day == nil { day = n }
                else if year == nil { year = n < 100 ? (n >= 70 ? n + 1900 : n + 2000) : n }
            } else {
                return nil
            }
        }
        guard let m = month, let d = day else { return nil }
        let y = year ?? calendar.component(.year, from: Date())
        guard (1...31).contains(d) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}

// MARK: - Amount parsing

public enum AmountParsing {

    /// Parse money strings from banks and hand entry:
    /// `-45.00`, `$1,234.56`, `(45.00)` (= negative), `£75.50`, `1 234,56` is NOT
    /// supported (continental format) — bank CSVs in scope use point decimals.
    /// Returns nil for non-amounts.
    public static func parse(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        if s.hasPrefix("-") {
            negative = true
            s = String(s.dropFirst())
        }
        if s.hasPrefix("+") { s = String(s.dropFirst()) }

        // Strip currency symbols and grouping.
        let symbols = CharacterSet(charactersIn: "$£€¥ ,")
        s = s.components(separatedBy: symbols).joined()
        guard !s.isEmpty else { return nil }

        // Must be digits with at most one decimal point.
        let pieces = s.components(separatedBy: ".")
        guard pieces.count <= 2, pieces.allSatisfy({ !$0.isEmpty || pieces.count == 2 }),
              s.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.").inverted) == nil,
              s.rangeOfCharacter(from: .decimalDigits) != nil
        else { return nil }

        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }
}
