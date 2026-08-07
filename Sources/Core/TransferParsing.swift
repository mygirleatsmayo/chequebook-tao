import Foundation

/// Typing "@" plus an account name in the Transaction Name column creates a
/// transfer — the original app's syntax:
///   @MySavings            transfer to/from account MySavings
///   @MyChecking.Auto      transfer to/from subaccount Auto of MyChecking
public enum TransferParsing {

    public struct Resolution: Equatable, Sendable {
        public var target: TransferTarget
        public var displayName: String
    }

    /// Resolve a typed name. Returns nil when the text is not an @-transfer or
    /// names an unknown account/subaccount.
    public static func resolve(
        typedName: String,
        currentAccountID: UUID,
        in file: RegisterFile
    ) -> Resolution? {
        let trimmed = typedName.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@"), trimmed.count > 1 else { return nil }
        let body = String(trimmed.dropFirst())

        // Try the longest account-name match first so account names containing
        // dots keep working; fall back to splitting on the last dot.
        if let account = file.account(named: body) {
            guard account.id != currentAccountID else { return nil }
            return Resolution(
                target: TransferTarget(accountID: account.id),
                displayName: "@" + account.name
            )
        }

        guard let dotIndex = body.lastIndex(of: ".") else { return nil }
        let accountName = String(body[..<dotIndex])
        let subName = String(body[body.index(after: dotIndex)...])
        guard let account = file.account(named: accountName), account.id != currentAccountID else { return nil }
        guard let sub = account.subaccounts.first(where: {
            $0.name.compare(subName, options: [.caseInsensitive]) == .orderedSame
        }) else { return nil }
        return Resolution(
            target: TransferTarget(accountID: account.id, subaccountID: sub.id),
            displayName: "@" + account.name + "." + sub.name
        )
    }

    /// Autocomplete candidates for a partial "@..." entry.
    public static func completions(
        forPrefix typed: String,
        currentAccountID: UUID,
        in file: RegisterFile
    ) -> [String] {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return [] }
        let body = String(trimmed.dropFirst()).lowercased()

        var options: [String] = []
        for account in file.accounts where account.id != currentAccountID {
            options.append("@" + account.name)
            for sub in account.subaccounts {
                options.append("@" + account.name + "." + sub.name)
            }
        }
        guard !body.isEmpty else { return options }
        return options.filter { $0.dropFirst().lowercased().hasPrefix(body) }
    }
}
