import XCTest
@testable import ChequebookCore

private let cal = Calendar(identifier: .gregorian)

func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d))!
}

func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

/// A fixture mirroring the original app's sample register:
/// MyChecking ($), MySavings ($), MyCreditline (%), MyLoan (%).
func sampleFile() -> (file: RegisterFile, checking: UUID, savings: UUID, creditline: UUID) {
    var checking = Account(name: "MyChecking", type: .deposit, startingBalance: dec("3000"))
    let savings = Account(name: "MySavings", type: .deposit, startingBalance: dec("5300"))
    var creditline = Account(name: "MyCreditline", type: .credit, creditLimit: dec("5000"), startingBalance: dec("1000"))

    checking.transactions = [
        Transaction(date: day(2026, 1, 8), checkNumber: "230", name: "CHECK", amount: dec("-45")),
        Transaction(date: day(2026, 1, 10), name: "CARD JUICE", amount: dec("-4.50")),
        Transaction(date: day(2026, 2, 5), name: "ACH CREDIT PAYROLL", amount: dec("1075")),
    ]
    // Transfer checking -> creditline: pay 100 toward the card.
    checking.transactions.append(
        Transaction(date: day(2026, 1, 21), amount: dec("-100"),
                    transfer: TransferTarget(accountID: creditline.id))
    )
    creditline.transactions = [
        Transaction(date: day(2026, 1, 1), name: "Sample Interest Charge", amount: dec("-45")),
    ]

    let file = RegisterFile(accounts: [checking, savings, creditline])
    return (file, checking.id, savings.id, creditline.id)
}

final class EngineTests: XCTestCase {

    func testRunningBalanceDepositAccount() {
        let (file, checking, _, _) = sampleFile()
        let rows = RegisterEngine.rows(for: checking, in: file)
        XCTAssertEqual(rows.count, 4)
        // Chronological: 1/8 -45, 1/10 -4.50, 1/21 -100 (transfer), 2/5 +1075
        XCTAssertEqual(rows.map(\.balance), [
            dec("2955"), dec("2950.50"), dec("2850.50"), dec("3925.50"),
        ])
    }

    func testCreditAccountBalanceIsOwedAndMirrorsIncomingPayment() {
        let (file, _, _, creditline) = sampleFile()
        let rows = RegisterEngine.rows(for: creditline, in: file)
        XCTAssertEqual(rows.count, 2)
        // 1/1: charge 45 -> owed 1045. 1/21 mirror of checking payment +100 in
        // cash-flow -> owed 945.
        XCTAssertEqual(rows[0].balance, dec("1045"))
        XCTAssertEqual(rows[1].balance, dec("945"))
        XCTAssertTrue(rows[1].isTransferMirror)
        XCTAssertEqual(rows[1].displayName, "@MyChecking")
        XCTAssertEqual(rows[1].amount, dec("100"))
    }

    func testTransferDisplayNameOnSourceSide() {
        let (file, checking, _, _) = sampleFile()
        let rows = RegisterEngine.rows(for: checking, in: file)
        let transferRow = rows.first { $0.isTransfer && !$0.isTransferMirror }
        XCTAssertEqual(transferRow?.displayName, "@MyCreditline")
        XCTAssertEqual(transferRow?.amount, dec("-100"))
    }

    func testTotalsStrip() {
        let (file, _, _, _) = sampleFile()
        let totals = RegisterEngine.totals(in: file)
        // Deposits: checking 3925.50 + savings 5300 = 9225.50. Credit owed: 945.
        XCTAssertEqual(totals.depositTotal, dec("9225.50"))
        XCTAssertEqual(totals.creditTotal, dec("945"))
        XCTAssertEqual(totals.total, dec("8280.50"))
    }

    func testAvailableCredit() {
        let (file, _, _, creditline) = sampleFile()
        let account = file.account(id: creditline)!
        XCTAssertEqual(RegisterEngine.availableCredit(for: account, in: file), dec("4055"))
    }

    func testBalanceVsProjectedSplitsOnToday() {
        let (file, checking, _, _) = sampleFile()
        let today = day(2026, 1, 15)
        let pair = RegisterEngine.balanceAndProjected(for: checking, in: file, today: today, calendar: cal)
        XCTAssertEqual(pair.balance, dec("2950.50"))   // through 1/15
        XCTAssertEqual(pair.projected, dec("3925.50")) // everything
    }

    func testSubaccountBalancesAndPrincipalRemainder() {
        var (file, checking, _, _) = sampleFile()
        var account = file.account(id: checking)!
        let auto = Subaccount(name: "Auto")
        account.subaccounts = [auto]
        // Assign the -4.50 card row to Auto.
        account.transactions[1].subaccountID = auto.id
        file.accounts[0] = account

        let autoBalance = RegisterEngine.subaccountBalance(accountID: checking, subaccountID: auto.id, in: file)
        XCTAssertEqual(autoBalance, dec("-4.50"))
        let principal = RegisterEngine.subaccountBalance(accountID: checking, subaccountID: nil, in: file)
        // principal = everything else: 3000 - 45 - 100 + 1075 = 3930
        XCTAssertEqual(principal, dec("3930"))
        // Subaccounts + principal = account balance.
        let total = RegisterEngine.balance(for: checking, in: file)
        XCTAssertEqual(autoBalance + principal, total)
    }

    func testDocumentRoundTrip() throws {
        let (file, _, _, _) = sampleFile()
        let data = try file.encoded()
        let decoded = try RegisterFile.decode(from: data)
        XCTAssertEqual(decoded, file)
    }
}

final class ReconcileTests: XCTestCase {

    func testDifferenceFormulaMatchesOriginalScreenshot() {
        // Reconstruct the original's documented numbers:
        // Statement 3705, Projected 2896, Adjustments -880 => Difference -71.
        var account = Account(name: "MyChecking", type: .deposit, startingBalance: dec("3776"))
        account.transactions = [
            Transaction(date: day(2026, 2, 6), name: "BANK MORTGAGE PAYMENT",
                        amount: dec("-880"), adjustment: true),
        ]
        let file = RegisterFile(accounts: [account])
        let summary = ReconcileMath.summary(statementBalance: dec("3705"), accountID: account.id, in: file)
        XCTAssertEqual(summary.projectedBalance, dec("2896"))
        XCTAssertEqual(summary.adjustments, dec("-880"))
        XCTAssertEqual(summary.difference, dec("-71"))
    }

    func testReconciledAccountShowsZeroDifference() {
        var account = Account(name: "A", type: .deposit, startingBalance: dec("100"))
        account.transactions = [
            Transaction(date: day(2026, 1, 5), name: "X", amount: dec("-40")),
        ]
        let file = RegisterFile(accounts: [account])
        let summary = ReconcileMath.summary(statementBalance: dec("60"), accountID: account.id, in: file)
        XCTAssertEqual(summary.difference, 0)
    }
}

final class FilterTests: XCTestCase {

    func makeRows() -> [RegisterRow] {
        let (file, checking, _, _) = sampleFile()
        return RegisterEngine.rows(for: checking, in: file)
    }

    func testHideTransfers() {
        let filter = RegisterFilter(hideTransfers: true)
        let visible = makeRows().filter { filter.matches($0, calendar: cal) }
        XCTAssertEqual(visible.count, 3)
        XCTAssertFalse(visible.contains { $0.isTransfer })
    }

    func testDateRange() {
        let filter = RegisterFilter(dateStart: day(2026, 1, 9), dateEnd: day(2026, 1, 31))
        let visible = makeRows().filter { filter.matches($0, calendar: cal) }
        XCTAssertEqual(visible.count, 2) // 1/10 and 1/21
    }

    func testAmountMagnitudeMatch() {
        let filter = RegisterFilter(amountStart: dec("45"))
        let visible = makeRows().filter { filter.matches($0, calendar: cal) }
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].checkNumber, "230")
    }

    func testNameSubstring() {
        let filter = RegisterFilter(nameContains: "juice")
        let visible = makeRows().filter { filter.matches($0, calendar: cal) }
        XCTAssertEqual(visible.count, 1)
    }
}

final class HistoryTests: XCTestCase {

    func testStatsGroupByName() {
        var account = Account(name: "A", type: .deposit, startingBalance: 0)
        account.transactions = [
            Transaction(date: day(2026, 7, 1), name: "CARD JUICE", amount: dec("-4.50")),
            Transaction(date: day(2026, 8, 2), name: "CARD JUICE", amount: dec("-4.50")),
            Transaction(date: day(2025, 5, 5), name: "card juice", amount: dec("-9")),
            Transaction(date: day(2026, 8, 3), name: "OTHER", amount: dec("-1")),
        ]
        let file = RegisterFile(accounts: [account])
        let summary = HistoryStats.summary(
            forName: "CARD JUICE", accountID: account.id, in: file,
            today: day(2026, 8, 7), calendar: cal
        )
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.total, dec("-18"))
        XCTAssertEqual(summary.average, dec("-6"))
        XCTAssertEqual(summary.thisMonth, dec("-4.50"))
        XCTAssertEqual(summary.lastMonth, dec("-4.50"))
        XCTAssertEqual(summary.thisYear, dec("-9"))
        XCTAssertEqual(summary.lastYear, dec("-9"))
    }
}

final class TransferParsingTests: XCTestCase {

    func testResolveAccountAndSubaccount() {
        var (file, checking, _, creditline) = sampleFile()
        var credit = file.account(id: creditline)!
        let sub = Subaccount(name: "Fees")
        credit.subaccounts = [sub]
        file.accounts[2] = credit

        let simple = TransferParsing.resolve(typedName: "@MyCreditline", currentAccountID: checking, in: file)
        XCTAssertEqual(simple?.target.accountID, creditline)
        XCTAssertNil(simple?.target.subaccountID)

        let dotted = TransferParsing.resolve(typedName: "@mycreditline.fees", currentAccountID: checking, in: file)
        XCTAssertEqual(dotted?.target.subaccountID, sub.id)
        XCTAssertEqual(dotted?.displayName, "@MyCreditline.Fees")

        // Cannot transfer to yourself; unknown names do not resolve.
        XCTAssertNil(TransferParsing.resolve(typedName: "@MyChecking", currentAccountID: checking, in: file))
        XCTAssertNil(TransferParsing.resolve(typedName: "@Nope", currentAccountID: checking, in: file))
        XCTAssertNil(TransferParsing.resolve(typedName: "Groceries", currentAccountID: checking, in: file))
    }

    func testCompletions() {
        let (file, checking, _, _) = sampleFile()
        let all = TransferParsing.completions(forPrefix: "@", currentAccountID: checking, in: file)
        XCTAssertEqual(Set(all), Set(["@MySavings", "@MyCreditline"]))
        let filtered = TransferParsing.completions(forPrefix: "@myc", currentAccountID: checking, in: file)
        XCTAssertEqual(filtered, ["@MyCreditline"])
    }
}
