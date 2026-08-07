import Foundation

/// Reconcile-mode math, matching the original app's bottom bar:
///
///   Statement Balance:  entered by the user from the bank statement
///   Projected Balance:  the account's displayed balance from the register
///   Adjustments:        sum of the displayed deltas of rows marked "X"
///                       (items NOT on the current statement)
///   Difference:         Statement - (Projected - Adjustments)
///
/// Verified against the original's screenshot:
///   Statement 3,705.00 | Projected 2,896.00 | Adjustments (880.00) | Difference (71.00)
///   3705 - (2896 - (-880)) = 3705 - 3776 = -71  ✓
///
/// A Difference of 0.00 means the account reconciles. The check column ("✓")
/// is a visual tick-off aid for matching statement lines; it does not enter
/// the arithmetic.
public enum ReconcileMath {

    public struct Summary: Equatable, Sendable {
        public var statementBalance: Decimal
        public var projectedBalance: Decimal
        public var adjustments: Decimal
        public var difference: Decimal
    }

    public static func summary(
        statementBalance: Decimal,
        accountID: UUID,
        in file: RegisterFile
    ) -> Summary {
        guard let account = file.account(id: accountID) else {
            return Summary(statementBalance: statementBalance, projectedBalance: 0,
                           adjustments: 0, difference: statementBalance)
        }
        let rows = RegisterEngine.rows(for: accountID, in: file)
        let projected = rows.last?.balance ?? account.startingBalance
        var adjustments: Decimal = 0
        for row in rows where row.adjustment {
            adjustments += RegisterEngine.displayedDelta(cashFlow: row.amount, accountType: account.type)
        }
        let difference = statementBalance - (projected - adjustments)
        return Summary(
            statementBalance: statementBalance,
            projectedBalance: projected,
            adjustments: adjustments,
            difference: difference
        )
    }
}
