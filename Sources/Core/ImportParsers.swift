import Foundation

// MARK: - Imported rows

/// One transaction parsed from a QIF file, a CSV file, or pasted bank rows —
/// not yet inserted into an account.
public struct ImportedTransaction: Equatable, Sendable {
    public var date: Date
    public var checkNumber: String
    public var name: String
    public var memo: String
    /// Signed cash flow: negative = money out (Withdraw/Charge).
    public var amount: Decimal

    public init(date: Date, checkNumber: String = "", name: String, memo: String = "", amount: Decimal) {
        self.date = date
        self.checkNumber = checkNumber
        self.name = name
        self.memo = memo
        self.amount = amount
    }
}

public struct ImportResult: Equatable, Sendable {
    public var transactions: [ImportedTransaction]
    /// Lines the parser skipped (headers, pending rows, junk).
    public var skippedLines: Int

    public init(transactions: [ImportedTransaction], skippedLines: Int = 0) {
        self.transactions = transactions
        self.skippedLines = skippedLines
    }
}

// MARK: - QIF

/// Quicken Interchange Format. Records separated by `^`, one field per line:
/// `D` date, `T`/`U` amount, `P` payee, `N` check number, `M` memo.
public enum QIFParser {

    public static func parse(_ text: String, dateOrder: DateOrder = .monthFirst) -> ImportResult {
        var transactions: [ImportedTransaction] = []
        var skipped = 0

        var date: Date?
        var amount: Decimal?
        var payee = ""
        var memo = ""
        var check = ""

        func flush() {
            defer { date = nil; amount = nil; payee = ""; memo = ""; check = "" }
            guard let d = date, let a = amount else {
                if date != nil || amount != nil || !payee.isEmpty { skipped += 1 }
                return
            }
            transactions.append(ImportedTransaction(
                date: d, checkNumber: check, name: payee, memo: memo, amount: a
            ))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let code = line.first!
            let value = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            switch code {
            case "!":
                continue // header, e.g. !Type:Bank
            case "^":
                flush()
            case "D":
                // QIF dates may use the D/M/Y quirk `2/ 5'13`.
                let normalized = value
                    .replacingOccurrences(of: "'", with: "/")
                    .replacingOccurrences(of: " ", with: "")
                date = DateParsing.parse(normalized, order: dateOrder)
            case "T", "U":
                amount = AmountParsing.parse(value)
            case "P":
                payee = value
            case "M":
                memo = value
            case "N":
                check = value
            case "C", "L", "A", "S", "E", "$":
                continue // cleared status, category, address, splits: ignored
            default:
                continue
            }
        }
        flush() // file may not end with ^
        return ImportResult(transactions: transactions, skippedLines: skipped)
    }
}

// MARK: - CSV

/// RFC-4180-ish CSV reader plus bank-flavored header detection.
public enum CSVParser {

    /// Split CSV text into rows of fields, honoring quotes and escaped quotes.
    public static func rows(from text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"" where field.isEmpty: inQuotes = true
                case delimiter: endField()
                case "\r": if let next = iterator.next() { if next == "\n" { endRow() } else { endRow(); pending = next } } else { endRow() }
                case "\n": endRow()
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    struct ColumnMap {
        var date: Int?
        var name: Int?
        var memo: Int?
        var check: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
    }

    static func detectColumns(header: [String]) -> ColumnMap? {
        var map = ColumnMap()
        for (index, rawTitle) in header.enumerated() {
            let title = rawTitle.trimmingCharacters(in: .whitespaces).lowercased()
            switch true {
            case title.contains("date") && map.date == nil:
                map.date = index
            case (title.contains("description") || title.contains("payee")
                  || title.contains("transaction name") || title == "name" || title.contains("narrative")
                  || title.contains("details")) && map.name == nil:
                map.name = index
            case title.contains("memo") || title.contains("notes"):
                map.memo = index
            case title.contains("check") || title.contains("cheque") || title == "chk#" || title == "number":
                map.check = index
            case (title.contains("debit") || title.contains("withdraw") || title.contains("charge")
                  || title.contains("money out") || title.contains("paid out")) && map.debit == nil:
                map.debit = index
            case (title.contains("credit") || title.contains("deposit") || title.contains("payment")
                  || title.contains("money in") || title.contains("paid in")) && map.credit == nil:
                map.credit = index
            case title.contains("amount") && !title.contains("balance") && map.amount == nil:
                map.amount = index
            default:
                continue
            }
        }
        guard map.date != nil, map.amount != nil || map.debit != nil || map.credit != nil else { return nil }
        return map
    }

    /// Parse a bank/app CSV export into transactions.
    /// With a recognizable header row, columns are mapped by name. Without one,
    /// each row is scanned like a pasted bank row.
    public static func parse(_ text: String, dateOrder: DateOrder = .monthFirst) -> ImportResult {
        let delimiter: Character = text.contains("\t") && !text.contains(",") ? "\t" : ","
        let allRows = rows(from: text, delimiter: delimiter)
        guard !allRows.isEmpty else { return ImportResult(transactions: []) }

        var startIndex = 0
        var map: ColumnMap? = nil
        for candidate in 0..<min(3, allRows.count) {
            if let detected = detectColumns(header: allRows[candidate]) {
                map = detected
                startIndex = candidate + 1
                break
            }
        }

        guard let columns = map else {
            // No header — treat every row like a pasted line.
            var transactions: [ImportedTransaction] = []
            var skipped = 0
            for row in allRows {
                if let tx = BankPasteParser.parseFields(row, dateOrder: dateOrder) {
                    transactions.append(tx)
                } else {
                    skipped += 1
                }
            }
            return ImportResult(transactions: transactions, skippedLines: skipped)
        }

        var transactions: [ImportedTransaction] = []
        var skipped = 0
        for row in allRows.dropFirst(startIndex) {
            func field(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            guard let date = DateParsing.parse(field(columns.date), order: dateOrder) else {
                skipped += 1
                continue
            }
            var amount: Decimal?
            if let a = columns.amount, let value = AmountParsing.parse(field(a)) {
                amount = value
            } else {
                let debit = columns.debit.flatMap { i in AmountParsing.parse(field(i)) }
                let credit = columns.credit.flatMap { i in AmountParsing.parse(field(i)) }
                if let d = debit, d != 0 {
                    amount = -abs(d)
                } else if let c = credit {
                    amount = abs(c)
                } else if debit != nil {
                    amount = 0
                }
            }
            guard let cashFlow = amount else {
                skipped += 1
                continue
            }
            transactions.append(ImportedTransaction(
                date: date,
                checkNumber: field(columns.check),
                name: field(columns.name),
                memo: field(columns.memo),
                amount: cashFlow
            ))
        }
        return ImportResult(transactions: transactions, skippedLines: skipped)
    }
}

// MARK: - Pasted bank rows

/// Rows copied or dragged straight off an online-banking site. Arrive as
/// tab-separated lines (rich tables) or whitespace-separated text such as:
///
///   02/08/2013   CHECK: 231                -45.00    254.50
///   In-process   CARD PURCHASE CBTAO JUICE  -4.50    250.00
///
/// Heuristic per line: first date-ish token = date; first money-ish token
/// AFTER the description start = amount (last money token wins for the
/// trailing running-balance column being present: we take the FIRST amount and
/// ignore a trailing balance). Lines with no date and no amount are skipped.
public enum BankPasteParser {

    public static func parse(_ text: String, dateOrder: DateOrder = .monthFirst) -> ImportResult {
        var transactions: [ImportedTransaction] = []
        var skipped = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let fields: [String]
            if line.contains("\t") {
                fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                fields = splitOnRuns(line)
            }
            if let tx = parseFields(fields, dateOrder: dateOrder) {
                transactions.append(tx)
            } else {
                skipped += 1
            }
        }
        return ImportResult(transactions: transactions, skippedLines: skipped)
    }

    /// Split on runs of 2+ spaces, so single spaces inside descriptions survive.
    static func splitOnRuns(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var spaceRun = 0
        for ch in line {
            if ch == " " {
                spaceRun += 1
                if spaceRun == 1 { current.append(ch) }
                continue
            }
            if spaceRun >= 2 {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { fields.append(trimmed) }
                current = ""
            }
            spaceRun = 0
            current.append(ch)
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { fields.append(trimmed) }
        return fields
    }

    static func parseFields(_ fields: [String], dateOrder: DateOrder) -> ImportedTransaction? {
        guard !fields.isEmpty else { return nil }

        var date: Date?
        var dateIndex: Int?
        for (index, field) in fields.enumerated() {
            if let d = DateParsing.parse(field, order: dateOrder) {
                date = d
                dateIndex = index
                break
            }
        }
        guard let txDate = date, let dIndex = dateIndex else { return nil }

        // Amount: first money-looking field after the date that is not
        // immediately consumed as description. Bank rows put Amount before the
        // trailing Available Balance, so the FIRST parseable amount among the
        // trailing fields is the transaction amount.
        var amount: Decimal?
        var amountIndex: Int?
        for (index, field) in fields.enumerated() where index > dIndex {
            if looksLikeMoney(field), let value = AmountParsing.parse(field) {
                amount = value
                amountIndex = index
                break
            }
        }
        guard let cashFlow = amount, let aIndex = amountIndex else { return nil }

        // Description: the non-money fields between date and amount, else after amount.
        var descriptionParts: [String] = []
        for (index, field) in fields.enumerated() {
            guard index != dIndex, index != aIndex else { continue }
            if index > aIndex, looksLikeMoney(field) { continue } // trailing balance
            if index < dIndex { continue }
            if looksLikeStatus(field) { continue }
            descriptionParts.append(field)
        }
        let name = descriptionParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        // Pull "CHECK: 231" style check numbers out of the description.
        var check = ""
        if let range = name.range(of: "CHECK[:# ]*([0-9]+)", options: [.regularExpression, .caseInsensitive]) {
            let digits = name[range].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            check = digits
        }

        return ImportedTransaction(date: txDate, checkNumber: check, name: name, amount: cashFlow)
    }

    static func looksLikeMoney(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,()$£€¥+- ")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil else { return false }
        // Dates like 2/5/13 contain "/" and are already excluded by the set.
        return trimmed.contains(".") || trimmed.contains(",")
            || trimmed.count <= 8 // plain integers like "250"
    }

    static func looksLikeStatus(_ s: String) -> Bool {
        let lower = s.lowercased()
        return ["pending", "in-process", "posted", "cleared", "processed", "completed"].contains(lower)
    }
}

// MARK: - Duplicate detection

public enum DuplicateDetection {
    /// A candidate duplicates an existing row when date (same day), magnitude
    /// of amount, and normalized name all match.
    public static func duplicates(
        of candidate: ImportedTransaction,
        in rows: [RegisterRow],
        calendar: Calendar = .current
    ) -> [RegisterRow] {
        rows.filter { row in
            calendar.isDate(row.date, inSameDayAs: candidate.date)
                && abs(row.amount) == abs(candidate.amount)
                && row.displayName.trimmingCharacters(in: .whitespaces)
                    .compare(candidate.name.trimmingCharacters(in: .whitespaces),
                             options: [.caseInsensitive]) == .orderedSame
        }
    }
}
