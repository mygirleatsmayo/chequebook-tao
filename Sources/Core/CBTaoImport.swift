import Foundation

/// Imports the original Checkbook Tao's native `.CBTao` register files.
///
/// Format (reverse-engineered from a real register):
/// - `"CoreData"` magic — the old app used a Core Data **atomic binary store**.
/// - Inside: an NSKeyedArchiver bplist under `$top.mapData`, holding
///   `NSStoreMapNode` objects keyed by primary key. Each node carries
///   `NSEntityName`, `NSPrimaryKey64`, `NSAttributeValues` (an ORDERED array —
///   attribute names live in the app's model, not the file), and
///   `NSRelatedNodes` (relationship name → primary-key list).
/// - A second, small bplist holds store metadata (ignored).
///
/// Entities and the value-array slots we rely on (verified against a CSV
/// export of the same account, so each position is ground-truthed):
///
///   GLAccount     [active, balance, projected, sortIndex, ?, ?, 0, name, ...]
///                 Ghost placeholder accounts named "23456789" carry
///                 active == 0 and a negative sortIndex — skipped.
///   GLSubAccount  [0, 0, balance, projected, 0, name, ...]; every account has
///                 a "principalAcct" subaccount (maps to our derived principal).
///   GLEntry       [adj, balance, projected, ?, ?, ?, sequence, deposit, date,
///                  withdraw, memo, name, ...]
///                 `sequence` is a file-global entry counter — the tiebreaker
///                 for same-day ordering. `deposit`/`withdraw` are doubles.
///   GLEntryList   the app's per-file "learned" transaction-name list
///                 (name + use frequency). Not imported: our autocomplete
///                 derives frequencies from the entries themselves.
///
/// Amounts are stored as doubles in the original; they are rounded to 2
/// decimal places on the way into `Decimal`.
public enum CBTaoImporter {

    public struct ImportReport: Sendable {
        public var accountCount: Int
        public var entryCount: Int
        public var skippedGhostAccounts: Int
        /// Entries present in the store but attached to no subaccount —
        /// residue of accounts deleted in the original app. The original
        /// doesn't display them either, so they are skipped (stored account
        /// balances validate without them).
        public var orphanedEntries: Int
        /// Accounts whose recomputed final balance disagrees with the balance
        /// stored in the file (name, stored, computed). Empty = perfect import.
        public var balanceMismatches: [(name: String, stored: Decimal, computed: Decimal)]
    }

    public struct ImportError: Error {
        public var message: String
    }

    public static func isCBTaoFile(_ data: Data) -> Bool {
        data.count > 8 && data.prefix(8).elementsEqual("CoreData".utf8)
    }

    public static func importFile(_ data: Data) throws -> (file: RegisterFile, report: ImportReport) {
        guard isCBTaoFile(data) else {
            throw ImportError(message: "Not a Checkbook Tao register (missing CoreData header).")
        }

        // Find the archive whose $top has mapData.
        var mapData: BinaryPlist.Value?
        var objects: [BinaryPlist.Value] = []
        for plist in BinaryPlist.embeddedPlists(in: data) {
            guard let objs = plist["$objects"]?.arrayValue,
                  let top = plist["$top"],
                  let mapRef = top["mapData"]
            else { continue }
            objects = objs
            mapData = resolve(mapRef, in: objs)
            break
        }
        guard let map = mapData, let mapPairs = keyedArchiveDictionary(map, in: objects) else {
            throw ImportError(message: "No register data found in file.")
        }

        // First pass: bucket nodes by entity.
        struct Node {
            var entity: String
            var pk: Int64
            var values: [BinaryPlist.Value]
            var related: [String: [Int64]]
        }
        var nodes: [Int64: Node] = [:]
        for (_, rawNode) in mapPairs {
            guard let node = resolve(rawNode, in: objects) else { continue }
            guard let entity = resolve(node["NSEntityName"], in: objects)?.stringValue,
                  let pk = resolve(node["NSPrimaryKey64"], in: objects)?.intValue
            else { continue }
            let values = keyedArchiveArray(resolve(node["NSAttributeValues"], in: objects), in: objects) ?? []
            var related: [String: [Int64]] = [:]
            if let rel = resolve(node["NSRelatedNodes"], in: objects),
               let relPairs = keyedArchiveDictionary(rel, in: objects) {
                for (k, v) in relPairs {
                    guard let name = k.stringValue else { continue }
                    let pks = (keyedArchiveArray(v, in: objects) ?? [v]).compactMap { $0.intValue }
                    related[name] = pks
                }
            }
            nodes[pk] = Node(entity: entity, pk: pk, values: values, related: related)
        }

        // Helpers to read slots tolerantly.
        func slotString(_ values: [BinaryPlist.Value], _ index: Int) -> String? {
            guard index < values.count else { return nil }
            let v = values[index]
            if let s = v.stringValue { return s == "$null" ? nil : s }
            return nil
        }
        func slotDouble(_ values: [BinaryPlist.Value], _ index: Int) -> Double? {
            guard index < values.count else { return nil }
            return values[index].doubleValue
        }
        func slotDate(_ values: [BinaryPlist.Value], _ index: Int) -> Date? {
            guard index < values.count else { return nil }
            switch values[index] {
            case .date(let secs):
                return Date(timeIntervalSinceReferenceDate: secs)
            case .dictionary:
                if let secs = values[index]["NS.time"]?.doubleValue {
                    return Date(timeIntervalSinceReferenceDate: secs)
                }
                return nil
            default:
                return nil
            }
        }
        func money(_ double: Double?) -> Decimal? {
            guard let double else { return nil }
            // Old app stored doubles; snap to pennies.
            let cents = (double * 100).rounded()
            return Decimal(Int64(cents)) / 100
        }

        // Build accounts in the original's sort order.
        struct AccountSeed {
            var pk: Int64
            var sort: Int64
            var name: String
            var storedBalance: Decimal
        }
        var seeds: [AccountSeed] = []
        var ghosts = 0
        for node in nodes.values where node.entity == "GLAccount" {
            let name = slotString(node.values, 7) ?? "Account \(node.pk)"
            let sort = (node.values.count > 3 ? node.values[3].intValue : nil) ?? 0
            let active = (node.values.first?.intValue ?? 0) != 0
            if !active || sort < 0 || name == "23456789" {
                ghosts += 1
                continue
            }
            seeds.append(AccountSeed(
                pk: node.pk, sort: sort, name: name,
                storedBalance: money(slotDouble(node.values, 1)) ?? 0
            ))
        }
        seeds.sort { $0.sort < $1.sort }

        // Subaccounts grouped by owning account (via rs_account back-reference).
        var subsByAccount: [Int64: [Node]] = [:]
        for node in nodes.values where node.entity == "GLSubAccount" {
            for accountPK in node.related["rs_account"] ?? [] {
                subsByAccount[accountPK, default: []].append(node)
            }
        }

        var accounts: [Account] = []
        var totalEntries = 0
        var importedEntryPKs = Set<Int64>()
        var mismatches: [(name: String, stored: Decimal, computed: Decimal)] = []

        for seed in seeds {
            var account = Account(name: uniqueName(seed.name, existing: accounts.map(\.name)), type: .deposit)
            var pending: [(seq: Int64, tx: Transaction)] = []

            for subNode in subsByAccount[seed.pk] ?? [] {
                let subName = slotString(subNode.values, 5) ?? "subaccount"
                var subID: UUID? = nil
                if subName != "principalAcct" {
                    let sub = Subaccount(name: subName)
                    account.subaccounts.append(sub)
                    subID = sub.id
                }
                for entryPK in subNode.related["rs_entry"] ?? [] {
                    guard let entry = nodes[entryPK], entry.entity == "GLEntry" else { continue }
                    importedEntryPKs.insert(entryPK)
                    guard let date = slotDate(entry.values, 8) else { continue }
                    let deposit = money(slotDouble(entry.values, 7))
                    let withdraw = money(slotDouble(entry.values, 9))
                    let seq = (entry.values.count > 6 ? entry.values[6].intValue : nil) ?? 0
                    var amount: Decimal = 0
                    if let deposit { amount += deposit }
                    if let withdraw { amount -= withdraw }
                    let tx = Transaction(
                        date: date,
                        checkNumber: slotString(entry.values, 3) ?? slotString(entry.values, 4) ?? "",
                        name: slotString(entry.values, 11) ?? "",
                        memo: slotString(entry.values, 10) ?? "",
                        amount: amount,
                        subaccountID: subID
                    )
                    pending.append((seq, tx))
                }
            }

            // Original orders by date, then by its global sequence counter.
            pending.sort {
                if $0.tx.date != $1.tx.date { return $0.tx.date < $1.tx.date }
                return $0.seq < $1.seq
            }
            account.transactions = pending.map(\.tx)
            totalEntries += pending.count
            accounts.append(account)
        }

        let file = RegisterFile(accounts: accounts)

        // Validation: recomputed balances should match the stored ones.
        for (index, seed) in seeds.enumerated() {
            let computed = RegisterEngine.balance(for: accounts[index].id, in: file)
            if computed != seed.storedBalance {
                mismatches.append((accounts[index].name, seed.storedBalance, computed))
            }
        }

        let allEntryPKs = Set(nodes.values.filter { $0.entity == "GLEntry" }.map(\.pk))
        let report = ImportReport(
            accountCount: accounts.count,
            entryCount: totalEntries,
            skippedGhostAccounts: ghosts,
            orphanedEntries: allEntryPKs.subtracting(importedEntryPKs).count,
            balanceMismatches: mismatches
        )
        return (file, report)
    }

    // MARK: - Keyed-archive helpers

    /// Follow a UID to its object in $objects.
    static func resolve(_ value: BinaryPlist.Value?, in objects: [BinaryPlist.Value]) -> BinaryPlist.Value? {
        guard let value else { return nil }
        if let uid = value.uidValue {
            guard uid < objects.count else { return nil }
            return objects[uid]
        }
        return value
    }

    /// Unwrap an archived NSDictionary (NS.keys/NS.objects) into resolved pairs.
    static func keyedArchiveDictionary(
        _ value: BinaryPlist.Value?, in objects: [BinaryPlist.Value]
    ) -> [(BinaryPlist.Value, BinaryPlist.Value)]? {
        guard let value = resolve(value, in: objects) else { return nil }
        guard let keys = value["NS.keys"]?.arrayValue, let vals = value["NS.objects"]?.arrayValue,
              keys.count == vals.count
        else {
            // A plain (non-archived) dictionary.
            return value.dictionaryValue
        }
        var pairs: [(BinaryPlist.Value, BinaryPlist.Value)] = []
        for (k, v) in zip(keys, vals) {
            guard let rk = resolve(k, in: objects), let rv = resolve(v, in: objects) else { continue }
            pairs.append((rk, rv))
        }
        return pairs
    }

    /// Unwrap an archived NSArray (NS.objects) into resolved values.
    static func keyedArchiveArray(
        _ value: BinaryPlist.Value?, in objects: [BinaryPlist.Value]
    ) -> [BinaryPlist.Value]? {
        guard let value = resolve(value, in: objects) else { return nil }
        if let inner = value["NS.objects"]?.arrayValue {
            return inner.map { resolve($0, in: objects) ?? .null }
        }
        return value.arrayValue?.map { resolve($0, in: objects) ?? .null }
    }

    static func uniqueName(_ name: String, existing: [String]) -> String {
        guard existing.contains(where: { $0.compare(name, options: [.caseInsensitive]) == .orderedSame }) else {
            return name
        }
        var i = 2
        while existing.contains(where: { $0.compare("\(name) \(i)", options: [.caseInsensitive]) == .orderedSame }) {
            i += 1
        }
        return "\(name) \(i)"
    }
}
