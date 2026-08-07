import Foundation

// MARK: - Account

public enum AccountType: String, Codable, Sendable {
    /// Checking / savings. Register columns: Withdraw | Deposit.
    case deposit
    /// Credit card / credit line / loan. Register columns: Charge | Payment.
    /// Displayed balance is the amount OWED (shown in red).
    case credit
}

public struct Subaccount: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var type: AccountType
    /// Credit accounts only: the credit limit. `Available = limit - owed`.
    public var creditLimit: Decimal?
    /// For deposit accounts: starting balance.
    /// For credit accounts: starting amount owed.
    public var startingBalance: Decimal
    /// Subaccounts (envelopes). The unallocated remainder is the implicit
    /// "principalAcct" — it is not stored, it is derived.
    public var subaccounts: [Subaccount]
    public var transactions: [Transaction]

    public init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        creditLimit: Decimal? = nil,
        startingBalance: Decimal = 0,
        subaccounts: [Subaccount] = [],
        transactions: [Transaction] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.creditLimit = creditLimit
        self.startingBalance = startingBalance
        self.subaccounts = subaccounts
        self.transactions = transactions
    }
}

// MARK: - Transaction

/// The far side of a transfer. A transfer is stored ONCE, on the account that
/// entered it, and is mirrored into the target account's register at render time.
public struct TransferTarget: Codable, Equatable, Sendable {
    public var accountID: UUID
    /// Optional subaccount on the TARGET side (`@Account.Subaccount`).
    public var subaccountID: UUID?

    public init(accountID: UUID, subaccountID: UUID? = nil) {
        self.accountID = accountID
        self.subaccountID = subaccountID
    }
}

public struct Transaction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// Check number. Free text ("230").
    public var checkNumber: String
    /// Transaction name / payee. Empty when `transfer` is set — transfer rows
    /// render their name from the target ("@MySavings").
    public var name: String
    public var memo: String
    /// Signed CASH FLOW from the owning account's point of view.
    /// Positive = cash into the account (Deposit / Payment column).
    /// Negative = cash out of the account (Withdraw / Charge column).
    ///
    /// Effect on the DISPLAYED balance:
    ///   deposit account: balance += amount
    ///   credit account:  owed    -= amount   (a charge is cash out -> owed goes up)
    ///
    /// A transfer mirror row always shows `-amount` on the other side.
    public var amount: Decimal
    /// Subaccount assignment on the OWNING account (nil = principal).
    public var subaccountID: UUID?
    /// Set when this transaction is a transfer to another account.
    public var transfer: TransferTarget?
    /// Reconcile: item is ticked as seen on the bank statement.
    public var cleared: Bool
    /// Reconcile: item is NOT on the current statement (adjustment column).
    public var adjustment: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        checkNumber: String = "",
        name: String = "",
        memo: String = "",
        amount: Decimal = 0,
        subaccountID: UUID? = nil,
        transfer: TransferTarget? = nil,
        cleared: Bool = false,
        adjustment: Bool = false
    ) {
        self.id = id
        self.date = date
        self.checkNumber = checkNumber
        self.name = name
        self.memo = memo
        self.amount = amount
        self.subaccountID = subaccountID
        self.transfer = transfer
        self.cleared = cleared
        self.adjustment = adjustment
    }
}

// MARK: - Document root

/// The on-disk document: one register file holds many accounts.
public struct RegisterFile: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var accounts: [Account]

    public init(formatVersion: Int = 1, accounts: [Account] = []) {
        self.formatVersion = formatVersion
        self.accounts = accounts
    }

    public static let currentFormatVersion = 1

    public func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    public func account(named name: String) -> Account? {
        accounts.first { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }
    }

    // MARK: Codable round-trip

    public static func decode(from data: Data) throws -> RegisterFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RegisterFile.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
