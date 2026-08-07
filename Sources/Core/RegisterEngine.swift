import Foundation

// MARK: - Register rows

/// One visible row in a register table. A row is either a transaction owned by
/// the displayed account, or the mirror of a transfer entered on another account.
public struct RegisterRow: Identifiable, Equatable, Sendable {
    /// The underlying transaction's ID. Mirrors share the ID of their source
    /// transaction, so `id` is unique *within one account's register*.
    public var id: UUID
    /// The account that OWNS the underlying transaction (where it is stored).
    public var ownerAccountID: UUID
    /// True when this row is the mirrored side of a transfer.
    public var isTransferMirror: Bool
    public var date: Date
    public var checkNumber: String
    /// Rendered name. Transfers render as "@Target" / "@Target.Subaccount".
    public var displayName: String
    public var memo: String
    /// Signed cash flow from the DISPLAYED account's point of view.
    /// Positive -> Deposit/Payment column. Negative -> Withdraw/Charge column.
    public var amount: Decimal
    /// Running displayed balance after this row (chronological order).
    public var balance: Decimal
    /// Subaccount assignment on the DISPLAYED side (mirrors use the transfer
    /// target's subaccount).
    public var subaccountID: UUID?
    public var cleared: Bool
    public var adjustment: Bool
    public var isTransfer: Bool

    public init(
        id: UUID, ownerAccountID: UUID, isTransferMirror: Bool, date: Date,
        checkNumber: String, displayName: String, memo: String, amount: Decimal,
        balance: Decimal, subaccountID: UUID?, cleared: Bool, adjustment: Bool,
        isTransfer: Bool
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.isTransferMirror = isTransferMirror
        self.date = date
        self.checkNumber = checkNumber
        self.displayName = displayName
        self.memo = memo
        self.amount = amount
        self.balance = balance
        self.subaccountID = subaccountID
        self.cleared = cleared
        self.adjustment = adjustment
        self.isTransfer = isTransfer
    }
}

// MARK: - Engine

/// Pure functions over a `RegisterFile`. No UI, no AppKit — unit-testable anywhere.
public enum RegisterEngine {

    // MARK: Row projection

    /// All rows for one account's register, in chronological order, with the
    /// running displayed balance computed. Includes mirrors of transfers that
    /// other accounts entered against this account.
    public static func rows(for accountID: UUID, in file: RegisterFile) -> [RegisterRow] {
        guard let account = file.account(id: accountID) else { return [] }

        var rows: [(sortKey: (Date, Int), row: RegisterRow)] = []
        var order = 0

        // Own transactions.
        for tx in account.transactions {
            let name: String
            var subID = tx.subaccountID
            if let transfer = tx.transfer {
                name = transferDisplayName(target: transfer, in: file)
                subID = tx.subaccountID
            } else {
                name = tx.name
            }
            let row = RegisterRow(
                id: tx.id, ownerAccountID: account.id, isTransferMirror: false,
                date: tx.date, checkNumber: tx.checkNumber, displayName: name,
                memo: tx.memo, amount: tx.amount, balance: 0, subaccountID: subID,
                cleared: tx.cleared, adjustment: tx.adjustment,
                isTransfer: tx.transfer != nil
            )
            rows.append(((tx.date, order), row))
            order += 1
        }

        // Mirrors: transfers on other accounts that target this account.
        for other in file.accounts where other.id != account.id {
            for tx in other.transactions {
                guard let transfer = tx.transfer, transfer.accountID == account.id else { continue }
                let sourceName = "@" + other.name + subaccountSuffix(tx.subaccountID, in: other)
                let row = RegisterRow(
                    id: tx.id, ownerAccountID: other.id, isTransferMirror: true,
                    date: tx.date, checkNumber: tx.checkNumber, displayName: sourceName,
                    memo: tx.memo, amount: -tx.amount, balance: 0,
                    subaccountID: transfer.subaccountID,
                    cleared: tx.cleared, adjustment: tx.adjustment, isTransfer: true
                )
                rows.append(((tx.date, order), row))
                order += 1
            }
        }

        rows.sort { lhs, rhs in
            if lhs.sortKey.0 != rhs.sortKey.0 { return lhs.sortKey.0 < rhs.sortKey.0 }
            return lhs.sortKey.1 < rhs.sortKey.1
        }

        // Running displayed balance.
        var balance = account.startingBalance
        var result: [RegisterRow] = []
        result.reserveCapacity(rows.count)
        for (_, var row) in rows {
            balance += displayedDelta(cashFlow: row.amount, accountType: account.type)
            row.balance = balance
            result.append(row)
        }
        return result
    }

    /// How a signed cash flow moves the DISPLAYED balance.
    /// Deposit accounts display cash; credit accounts display amount owed.
    public static func displayedDelta(cashFlow: Decimal, accountType: AccountType) -> Decimal {
        switch accountType {
        case .deposit: return cashFlow
        case .credit: return -cashFlow
        }
    }

    static func transferDisplayName(target: TransferTarget, in file: RegisterFile) -> String {
        guard let account = file.account(id: target.accountID) else { return "@?" }
        return "@" + account.name + subaccountSuffix(target.subaccountID, in: account)
    }

    static func subaccountSuffix(_ subID: UUID?, in account: Account) -> String {
        guard let subID, let sub = account.subaccounts.first(where: { $0.id == subID }) else { return "" }
        return "." + sub.name
    }

    // MARK: Balances

    /// Displayed balance through `asOf` (nil = all transactions = "Projected").
    public static func balance(for accountID: UUID, in file: RegisterFile, asOf: Date? = nil) -> Decimal {
        guard let account = file.account(id: accountID) else { return 0 }
        let all = rows(for: accountID, in: file)
        guard let asOf else { return all.last?.balance ?? account.startingBalance }
        var balance = account.startingBalance
        for row in all where row.date <= asOf { balance = row.balance }
        return balance
    }

    /// The pair shown in the accounts pane. `balance` counts rows dated through
    /// the end of `today`; `projected` counts everything including future-dated rows.
    public static func balanceAndProjected(
        for accountID: UUID, in file: RegisterFile, today: Date = Date(), calendar: Calendar = .current
    ) -> (balance: Decimal, projected: Decimal) {
        let endOfToday = calendar.endOfDay(for: today) ?? today
        let current = balance(for: accountID, in: file, asOf: endOfToday)
        let projected = balance(for: accountID, in: file, asOf: nil)
        return (current, projected)
    }

    /// Available credit for a credit account: `limit - owed` (projected owed).
    public static func availableCredit(for account: Account, in file: RegisterFile) -> Decimal? {
        guard account.type == .credit, let limit = account.creditLimit else { return nil }
        return limit - balance(for: account.id, in: file)
    }

    // MARK: Totals strip

    public struct Totals: Equatable, Sendable {
        public var depositTotal: Decimal
        public var creditTotal: Decimal
        /// Net worth shown as "Total Balance" = deposits - credit owed.
        public var total: Decimal
    }

    public static func totals(in file: RegisterFile) -> Totals {
        var deposit: Decimal = 0
        var credit: Decimal = 0
        for account in file.accounts {
            let projected = balance(for: account.id, in: file)
            switch account.type {
            case .deposit: deposit += projected
            case .credit: credit += projected
            }
        }
        return Totals(depositTotal: deposit, creditTotal: credit, total: deposit - credit)
    }

    // MARK: Subaccount balances

    /// Balance of one subaccount (nil = the implicit principal remainder).
    public static func subaccountBalance(
        accountID: UUID, subaccountID: UUID?, in file: RegisterFile, asOf: Date? = nil
    ) -> Decimal {
        guard let account = file.account(id: accountID) else { return 0 }
        let all = rows(for: accountID, in: file)
        var sum: Decimal = 0
        for row in all {
            if let asOf, row.date > asOf { continue }
            guard row.subaccountID == subaccountID else { continue }
            sum += displayedDelta(cashFlow: row.amount, accountType: account.type)
        }
        // The principal absorbs the starting balance.
        if subaccountID == nil { sum += account.startingBalance }
        return sum
    }
}

private extension Calendar {
    /// End of the given day (one second before the next day starts).
    func endOfDay(for today: Date) -> Date? {
        guard let nextDay = date(byAdding: .day, value: 1, to: startOfDay(for: today)) else { return nil }
        return nextDay.addingTimeInterval(-1)
    }
}
