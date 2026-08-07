import XCTest
@testable import ChequebookCore

private let cal = Calendar(identifier: .gregorian)

final class DateParsingTests: XCTestCase {

    func testSlashFormats() {
        XCTAssertEqual(DateParsing.parse("2/5/13", order: .monthFirst, calendar: cal), day(2013, 2, 5))
        XCTAssertEqual(DateParsing.parse("2/5/13", order: .dayFirst, calendar: cal), day(2013, 5, 2))
        XCTAssertEqual(DateParsing.parse("02/08/2013", order: .monthFirst, calendar: cal), day(2013, 2, 8))
        XCTAssertEqual(DateParsing.parse("12/31/26", order: .monthFirst, calendar: cal), day(2026, 12, 31))
        // Impossible month flips regardless of preference.
        XCTAssertEqual(DateParsing.parse("25/12/13", order: .monthFirst, calendar: cal), day(2013, 12, 25))
    }

    func testISOAndMonthNames() {
        XCTAssertEqual(DateParsing.parse("2013-02-05", calendar: cal), day(2013, 2, 5))
        XCTAssertEqual(DateParsing.parse("5 Feb 2013", calendar: cal), day(2013, 2, 5))
        XCTAssertEqual(DateParsing.parse("Feb 5, 2013", calendar: cal), day(2013, 2, 5))
    }

    func testNonDates() {
        XCTAssertNil(DateParsing.parse("In-process", calendar: cal))
        XCTAssertNil(DateParsing.parse("Pending", calendar: cal))
        XCTAssertNil(DateParsing.parse("Description", calendar: cal))
        XCTAssertNil(DateParsing.parse("", calendar: cal))
    }
}

final class AmountParsingTests: XCTestCase {

    func testFormats() {
        XCTAssertEqual(AmountParsing.parse("-45.00"), dec("-45"))
        XCTAssertEqual(AmountParsing.parse("$1,234.56"), dec("1234.56"))
        XCTAssertEqual(AmountParsing.parse("(45.00)"), dec("-45"))
        XCTAssertEqual(AmountParsing.parse("£75.50"), dec("75.50"))
        XCTAssertEqual(AmountParsing.parse("+20"), dec("20"))
        XCTAssertEqual(AmountParsing.parse("250"), dec("250"))
    }

    func testNonAmounts() {
        XCTAssertNil(AmountParsing.parse("CHECK: 231"))
        XCTAssertNil(AmountParsing.parse("abc"))
        XCTAssertNil(AmountParsing.parse(""))
        XCTAssertNil(AmountParsing.parse("$"))
    }
}

final class QIFTests: XCTestCase {

    func testBasicBankRecord() {
        let qif = """
        !Type:Bank
        D2/8/2013
        T-45.00
        N231
        PCHECK
        MFebruary rent check
        ^
        D2/10/2013
        T-4.50
        PCARD CBTAO JUICE
        ^
        """
        let result = QIFParser.parse(qif)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].date, day(2013, 2, 8))
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
        XCTAssertEqual(result.transactions[0].checkNumber, "231")
        XCTAssertEqual(result.transactions[0].name, "CHECK")
        XCTAssertEqual(result.transactions[0].memo, "February rent check")
        XCTAssertEqual(result.transactions[1].amount, dec("-4.50"))
        XCTAssertEqual(result.skippedLines, 0)
    }

    func testQuirkyQuickenDateAndMissingTrailingCaret() {
        let qif = """
        !Type:Bank
        D2/ 5'13
        T1,075.00
        PACH CREDIT PAYROLL
        """
        let result = QIFParser.parse(qif)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].date, day(2013, 2, 5))
        XCTAssertEqual(result.transactions[0].amount, dec("1075"))
    }
}

final class CSVTests: XCTestCase {

    func testQuotedFieldsAndEscapes() {
        let rows = CSVParser.rows(from: "a,\"b, with comma\",\"say \"\"hi\"\"\"\r\nc,d,e\n")
        XCTAssertEqual(rows, [["a", "b, with comma", "say \"hi\""], ["c", "d", "e"]])
    }

    func testBankHeaderWithSignedAmount() {
        let csv = """
        Date,Description,Type,Status,Amount,Available Balance
        02/08/2013,CHECK: 231,Check,Posted,-45.00,254.50
        02/10/2013,CARD PURCHASE CBTAO JUICE,Card,Posted,-4.50,250.00
        02/11/2013,ACH CREDIT PAYROLL,ACH,Posted,1075.00,1325.00
        """
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.transactions.count, 3)
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
        XCTAssertEqual(result.transactions[0].checkNumber, "")
        XCTAssertEqual(result.transactions[2].amount, dec("1075"))
        XCTAssertEqual(result.skippedLines, 0)
    }

    func testUKStyleMoneyInMoneyOutColumns() {
        let csv = """
        Date,Narrative,Paid Out,Paid In,Balance
        05/02/2013,COFFEE SHOP,4.50,,995.50
        06/02/2013,SALARY,,1075.00,2070.50
        """
        let result = CSVParser.parse(csv, dateOrder: .dayFirst)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].date, day(2013, 2, 5))
        XCTAssertEqual(result.transactions[0].amount, dec("-4.50"))
        XCTAssertEqual(result.transactions[1].amount, dec("1075"))
    }

    func testHeadlessCSVFallsBackToRowScan() {
        let csv = """
        02/08/2013,CHECK: 231,-45.00,254.50
        02/10/2013,CARD PURCHASE,-4.50,250.00
        """
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
        XCTAssertEqual(result.transactions[0].checkNumber, "231")
    }
}

final class BankPasteTests: XCTestCase {

    func testTabSeparatedBankRows() {
        let paste = "02/08/2013\tCHECK: 231\tCheck\tPosted\t-45.00\t254.50\n" +
                    "02/10/2013\tCARD PURCHASE CBTAO JUICE\tCard\tPosted\t-4.50\t250.00\n"
        let result = BankPasteParser.parse(paste)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].date, day(2013, 2, 8))
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
        XCTAssertEqual(result.transactions[0].checkNumber, "231")
        XCTAssertEqual(result.transactions[1].name, "CARD PURCHASE CBTAO JUICE")
    }

    func testSpaceRunSeparatedRowsAndSkipsJunk() {
        let paste = """
        Date          Description                 Amount    Available Balance
        02/08/2013    CHECK: 231                  -45.00    254.50
        In-process    CARD PURCHASE CBTAO JUICE   -4.50     250.00
        """
        let result = BankPasteParser.parse(paste)
        // Header line and the "In-process" line (no date) are skipped.
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
        XCTAssertEqual(result.skippedLines, 2)
    }

    func testTrailingBalanceColumnIsNotTheAmount() {
        let paste = "02/08/2013\tGROCERY\t-45.00\t1254.50\n"
        let result = BankPasteParser.parse(paste)
        XCTAssertEqual(result.transactions[0].amount, dec("-45"))
    }
}

final class ExportAndDuplicateTests: XCTestCase {

    func testCSVExportRoundTripsThroughImporter() {
        let (file, checking, _, _) = sampleFile()
        let rows = RegisterEngine.rows(for: checking, in: file)
        let csv = CSVExporter.export(rows: rows, accountType: .deposit, calendar: cal)
        XCTAssertTrue(csv.hasPrefix("Date,Chk#,Transaction Name,Withdraw,Deposit,Balance,Memo"))

        let reimported = CSVParser.parse(csv)
        XCTAssertEqual(reimported.transactions.count, rows.count)
        XCTAssertEqual(reimported.transactions[0].amount, rows[0].amount)
        XCTAssertEqual(reimported.transactions[3].amount, dec("1075"))
    }

    func testDuplicateDetection() {
        let (file, checking, _, _) = sampleFile()
        let rows = RegisterEngine.rows(for: checking, in: file)
        let dupe = ImportedTransaction(date: day(2026, 1, 8), name: "check", amount: dec("-45"))
        XCTAssertEqual(DuplicateDetection.duplicates(of: dupe, in: rows, calendar: cal).count, 1)
        let fresh = ImportedTransaction(date: day(2026, 1, 9), name: "check", amount: dec("-45"))
        XCTAssertTrue(DuplicateDetection.duplicates(of: fresh, in: rows, calendar: cal).isEmpty)
    }
}
