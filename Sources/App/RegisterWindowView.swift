import AppKit
import SwiftUI

/// The document window: credit pill on top (when a credit account is selected),
/// accounts pane on the left, register on the right, action buttons below —
/// the original's layout.
struct RegisterWindowView: View {
    @ObservedObject var document: RegisterDocument
    @Environment(\.undoManager) private var undoManager

    @State private var selectedAccountID: UUID?
    @State private var selectedRowID: UUID?
    @State private var sortAscending = true
    @State private var accountSheet: AccountSheetMode?

    // Layout preferences that survive closing and reopening files.
    @AppStorage("accountsPaneWidth") private var accountsPaneWidth = 380.0
    @AppStorage("accountColumns") private var accountColumns: TableColumnCustomization<AccountListRow>

    var body: some View {
        VStack(spacing: 0) {
            if let account = selectedAccount, account.type == .credit {
                creditPill(for: account)
            }

            HSplitView {
                accountsPane
                    .frame(minWidth: 200, idealWidth: accountsPaneWidth, maxWidth: 520)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        accountsPaneWidth = width
                    }
                registerPane
                    .frame(minWidth: 480, maxWidth: .infinity)
            }

            bottomBar
        }
        .frame(minWidth: 900, minHeight: 480)
        .onAppear {
            if selectedAccountID == nil { selectedAccountID = document.file.accounts.first?.id }
        }
        .sheet(item: $accountSheet) { mode in
            AccountSheet(document: document, mode: mode) { newID in
                if let newID { selectedAccountID = newID }
            }
        }
    }

    private var selectedAccount: Account? {
        guard let id = selectedAccountID else { return nil }
        return document.file.account(id: id)
    }

    // MARK: Credit pill

    private func creditPill(for account: Account) -> some View {
        HStack {
            let available = RegisterEngine.availableCredit(for: account, in: document.file)
            Text("Limit: \(Format.money(account.creditLimit ?? 0))")
            Text("Available: \(available.map(Format.money) ?? "—")")
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: Accounts pane

    private var accountsPane: some View {
        VStack(spacing: 0) {
            // Right-clicking the header toggles Balance/Projected visibility;
            // the choice persists app-wide via `accountColumns`.
            Table(of: AccountListRow.self, selection: $selectedAccountID, columnCustomization: $accountColumns) {
                TableColumn("Account") { row in
                    HStack(spacing: 6) {
                        Text(row.typeSymbol)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(row.name)
                    }
                }
                TableColumn("Balance") { row in
                    Text(Format.money(row.balance))
                        .foregroundStyle(row.isCredit ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .customizationID("balance")
                TableColumn("Projected") { row in
                    Text(Format.money(row.projected))
                        .foregroundStyle(row.isCredit ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .customizationID("projected")
            } rows: {
                ForEach(accountRows) { row in
                    TableRow(row)
                }
            }

            totalsStrip
        }
    }

    private var accountRows: [AccountListRow] {
        document.file.accounts.map { account in
            let pair = RegisterEngine.balanceAndProjected(for: account.id, in: document.file)
            return AccountListRow(
                id: account.id,
                name: account.name,
                typeSymbol: account.type == .deposit ? "$" : "%",
                isCredit: account.type == .credit,
                balance: pair.balance,
                projected: pair.projected
            )
        }
    }

    private var totalsStrip: some View {
        let totals = RegisterEngine.totals(in: document.file)
        // The per-type breakdown only means something once both types exist.
        let hasCreditAccounts = document.file.accounts.contains { $0.type == .credit }
        return HStack(spacing: 0) {
            if hasCreditAccounts {
                totalCell("Deposit Accts:", Format.money(totals.depositTotal), color: .primary)
                Divider().frame(height: 28)
                totalCell("Credit Accts:", Format.money(totals.creditTotal), color: .red)
                Divider().frame(height: 28)
            }
            totalCell("Total Balance:", Format.money(totals.total), color: .primary)
        }
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.4))
    }

    private func totalCell(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Register pane

    private var registerPane: some View {
        Group {
            if let account = selectedAccount {
                RegisterTableView(
                    document: document,
                    accountID: account.id,
                    sortAscending: $sortAscending,
                    selectedRowID: $selectedRowID,
                    undoManager: undoManager
                )
                .id(account.id) // rebuild the table when switching accounts
            } else {
                VStack(spacing: 8) {
                    Text("No account selected").font(.title3).foregroundStyle(.secondary)
                    Text("Add an account to start your register.").foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("Add Account") { accountSheet = .add }
            Menu {
                Button("Delete Account…", role: .destructive) { deleteSelectedAccount() }
                    .disabled(selectedAccount == nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            Button("Edit Account") {
                if let account = selectedAccount { accountSheet = .edit(account) }
            }
            .disabled(selectedAccount == nil)

            Spacer()

            Button("Add Entry") { addEntry() }
                .disabled(selectedAccount == nil)
            Button("Remove Entry") { removeSelectedEntry() }
                .disabled(selectedAccount == nil || selectedRowID == nil)
        }
        .padding(10)
    }

    private func addEntry() {
        guard let accountID = selectedAccountID else { return }
        document.mutate("Add Entry", undoManager: undoManager) { file in
            guard let index = file.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            file.accounts[index].transactions.append(Transaction(date: Date()))
        }
    }

    private func removeSelectedEntry() {
        guard let accountID = selectedAccountID, let rowID = selectedRowID else { return }
        document.mutate("Remove Entry", undoManager: undoManager) { file in
            // The row may live on another account (transfer mirror): remove the
            // underlying transaction wherever it is stored.
            for index in file.accounts.indices {
                if let txIndex = file.accounts[index].transactions.firstIndex(where: { $0.id == rowID }) {
                    file.accounts[index].transactions.remove(at: txIndex)
                    return
                }
            }
            _ = accountID // silence unused warning paths
        }
        selectedRowID = nil
    }

    private func deleteSelectedAccount() {
        guard let account = selectedAccount else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(account.name)”?"
        alert.informativeText = "This removes the account and all of its transactions. Transfers entered from other accounts are kept there."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        document.mutate("Delete Account", undoManager: undoManager) { file in
            file.accounts.removeAll { $0.id == account.id }
            // Orphan transfers pointing at the deleted account become plain entries.
            for index in file.accounts.indices {
                for txIndex in file.accounts[index].transactions.indices {
                    if file.accounts[index].transactions[txIndex].transfer?.accountID == account.id {
                        file.accounts[index].transactions[txIndex].transfer = nil
                        file.accounts[index].transactions[txIndex].name = "@" + account.name
                    }
                }
            }
        }
        selectedAccountID = document.file.accounts.first?.id
    }
}

struct AccountListRow: Identifiable {
    var id: UUID
    var name: String
    var typeSymbol: String
    var isCredit: Bool
    var balance: Decimal
    var projected: Decimal
}
