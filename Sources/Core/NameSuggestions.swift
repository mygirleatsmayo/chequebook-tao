import Foundation

/// The original app's "learned" transaction-name suggestions (it stored a
/// per-file name/frequency list; Nicky described the register offering names
/// "that it has learned"). We derive the same thing live from the entries:
/// names ranked by how often they're used, then by how recently.
public enum NameSuggestions {

    /// Suggestions for a partly-typed transaction name in one account's register.
    ///
    /// - Names are matched case-insensitively by prefix; an empty prefix
    ///   returns the overall most-used names.
    /// - Frequencies are counted across the WHOLE file (like the original's
    ///   per-file learned list), so a payee used in one account is offered in
    ///   another.
    /// - Typing "@" switches to transfer-target completions.
    public static func suggestions(
        forPrefix prefix: String,
        accountID: UUID,
        in file: RegisterFile,
        limit: Int = 8
    ) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") {
            return Array(TransferParsing.completions(
                forPrefix: trimmed, currentAccountID: accountID, in: file
            ).prefix(limit))
        }

        struct Stat {
            var display: String
            var count: Int
            var lastUsed: Date
        }
        var stats: [String: Stat] = [:]
        for account in file.accounts {
            for tx in account.transactions {
                let name = tx.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                if var s = stats[key] {
                    s.count += 1
                    if tx.date > s.lastUsed {
                        s.lastUsed = tx.date
                        s.display = name
                    }
                    stats[key] = s
                } else {
                    stats[key] = Stat(display: name, count: 1, lastUsed: tx.date)
                }
            }
        }

        let needle = trimmed.lowercased()
        let matches = stats.values.filter { stat in
            guard !needle.isEmpty else { return true }
            let key = stat.display.lowercased()
            return key.hasPrefix(needle) && key != needle
        }
        return matches
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
                return $0.display < $1.display
            }
            .prefix(limit)
            .map(\.display)
    }
}
