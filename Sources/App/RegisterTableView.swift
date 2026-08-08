import AppKit
import SwiftUI

/// The register table — an NSTableView, because the original's interaction
/// model (inline cell editing, draggable/resizable columns, a New Entry row)
/// is native NSTableView territory.
struct RegisterTableView: NSViewRepresentable {
    @ObservedObject var document: RegisterDocument
    let accountID: UUID
    @Binding var sortAscending: Bool
    @Binding var selectedRowID: UUID?
    let undoManager: UndoManager?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.rowHeight = 20
        table.gridStyleMask = []
        table.style = .fullWidth
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        context.coordinator.table = table
        context.coordinator.configureColumns(for: accountType)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }

    private var accountType: AccountType {
        document.file.account(id: accountID)?.type ?? .deposit
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: RegisterTableView
        weak var table: NSTableView?
        private var rows: [RegisterRow] = []
        private var configuredType: AccountType?

        init(_ parent: RegisterTableView) {
            self.parent = parent
        }

        // MARK: Columns

        enum ColumnID: String, CaseIterable {
            case date, check, name, out, `in`, balance, memo
        }

        func configureColumns(for type: AccountType) {
            guard let table else { return }
            configuredType = type
            for column in table.tableColumns {
                table.removeTableColumn(column)
            }
            let specs: [(ColumnID, String, CGFloat, NSTextAlignment)] = [
                (.date, "Date", 76, .left),
                (.check, "Chk#", 48, .left),
                (.name, "Transaction Name", 240, .left),
                (.out, type == .deposit ? "Withdraw" : "Charge", 90, .right),
                (.in, type == .deposit ? "Deposit" : "Payment", 90, .right),
                (.balance, "Balance", 100, .right),
                (.memo, "Memo", 160, .left),
            ]
            for (id, title, width, alignment) in specs {
                let column = NSTableColumn(identifier: .init(id.rawValue))
                column.title = title
                column.width = width
                column.minWidth = 40
                if id == .name || id == .memo { column.maxWidth = 10_000 }
                column.headerCell.alignment = alignment
                table.addTableColumn(column)
            }
            // Date header shows a sort arrow; clicking toggles.
            updateSortIndicator()
        }

        private func updateSortIndicator() {
            guard let table else { return }
            for column in table.tableColumns {
                let image = column.identifier.rawValue == ColumnID.date.rawValue
                    ? NSImage(named: parent.sortAscending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator")
                    : nil
                table.setIndicatorImage(image, in: column)
            }
        }

        // MARK: Data

        func reload() {
            guard let table else { return }
            let account = parent.document.file.account(id: parent.accountID)
            if let type = account?.type, type != configuredType {
                configureColumns(for: type)
            }
            var computed = RegisterEngine.rows(for: parent.accountID, in: parent.document.file)
            if !parent.sortAscending { computed.reverse() }
            rows = computed
            let selectedID = parent.selectedRowID
            table.reloadData()
            if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
            updateSortIndicator()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count + 1 // trailing New Entry row
        }

        private func isNewEntryRow(_ row: Int) -> Bool { row == rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let columnID = tableColumn.flatMap({ ColumnID(rawValue: $0.identifier.rawValue) }) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("cell." + columnID.rawValue)
            let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
                field = reused
            } else {
                field = NSTextField()
                field.identifier = identifier
                field.isBordered = false
                field.drawsBackground = false
                field.font = .systemFont(ofSize: 12)
                field.lineBreakMode = .byTruncatingTail
                field.delegate = self
            }

            let theme = Theme.current
            let account = parent.document.file.account(id: parent.accountID)
            let type = account?.type ?? .deposit
            field.isEditable = columnID != .balance
            field.alignment = [.out, .in, .balance].contains(columnID) ? .right : .left
            field.textColor = theme.regularText
            field.placeholderString = nil

            if isNewEntryRow(row) {
                field.stringValue = ""
                if columnID == .name {
                    field.placeholderString = "New Entry"
                }
                if columnID == .date {
                    field.placeholderString = Format.date(Date())
                }
                field.tag = tagFor(row: row, column: columnID)
                return field
            }

            let rowData = rows[row]
            switch columnID {
            case .date:
                field.stringValue = Format.date(rowData.date)
            case .check:
                field.stringValue = rowData.checkNumber
            case .name:
                field.stringValue = rowData.displayName
                field.isEditable = !rowData.isTransferMirror // rename transfers on their source side
            case .out:
                field.stringValue = rowData.amount < 0 ? Format.magnitude(rowData.amount) : ""
                field.textColor = theme.regularText
            case .in:
                field.stringValue = rowData.amount > 0 ? Format.magnitude(rowData.amount) : ""
            case .balance:
                field.stringValue = Format.money(rowData.balance)
                field.textColor = type == .credit ? theme.creditBalance : theme.regularText
            case .memo:
                field.stringValue = rowData.memo
            }
            field.tag = tagFor(row: row, column: columnID)
            return field
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table else { return }
            let row = table.selectedRow
            parent.selectedRowID = (row >= 0 && row < rows.count) ? rows[row].id : nil
        }

        func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
            guard tableColumn.identifier.rawValue == ColumnID.date.rawValue else { return }
            parent.sortAscending.toggle()
            reload()
        }

        // MARK: Name autocomplete ("learned" suggestions, like the original)

        private var isCompleting = false
        private var lastEditedLength = 0

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let (_, column) = rowAndColumn(fromTag: field.tag)
            guard column == .name, !isCompleting else { return }
            let text = field.stringValue
            let previous = lastEditedLength
            lastEditedLength = text.count
            // Only pop suggestions on a single typed character — never on
            // deletes, and never re-open right after a completion is accepted.
            guard text.count == previous + 1, !text.isEmpty else { return }
            guard let editor = field.currentEditor() as? NSTextView else { return }
            isCompleting = true
            editor.complete(nil)
            isCompleting = false
        }

        func control(
            _ control: NSControl, textView: NSTextView, completions words: [String],
            forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>
        ) -> [String] {
            let (_, column) = rowAndColumn(fromTag: control.tag)
            guard column == .name else { return [] }
            index.pointee = -1

            let full = textView.string
            let suggestions = NameSuggestions.suggestions(
                forPrefix: full, accountID: parent.accountID, in: parent.document.file
            )
            // The completion replaces only charRange (the trailing partial
            // word). Every suggestion starts with the whole typed text, so
            // strip whatever sits before charRange from each suggestion.
            let ns = full as NSString
            let head = ns.substring(to: min(charRange.location, ns.length)).lowercased()
            return suggestions.compactMap { suggestion in
                let lower = suggestion.lowercased()
                guard lower.hasPrefix(head) else { return nil }
                let tail = String(suggestion.dropFirst(head.count))
                return tail.isEmpty ? nil : tail
            }
        }

        // MARK: Editing

        private func tagFor(row: Int, column: ColumnID) -> Int {
            let columnIndex = ColumnID.allCases.firstIndex(of: column) ?? 0
            return row * 100 + columnIndex
        }

        private func rowAndColumn(fromTag tag: Int) -> (row: Int, column: ColumnID) {
            let columnIndex = tag % 100
            let row = tag / 100
            let column = ColumnID.allCases[min(columnIndex, ColumnID.allCases.count - 1)]
            return (row, column)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let (row, column) = rowAndColumn(fromTag: field.tag)
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)

            if isNewEntryRow(row) {
                guard !text.isEmpty else { return }
                createTransaction(fromNewEntryColumn: column, text: text)
                return
            }
            guard row < rows.count else { return }
            applyEdit(text, to: rows[row], column: column)
        }

        private func createTransaction(fromNewEntryColumn column: ColumnID, text: String) {
            let accountID = parent.accountID
            var tx = Transaction(date: Date())
            switch column {
            case .date:
                if let date = DateParsing.parse(text, order: AppSettings.dateOrder) { tx.date = date }
            case .check:
                tx.checkNumber = text
            case .name:
                applyName(text, to: &tx, accountID: accountID)
            case .out:
                if let amount = AmountParsing.parse(text) { tx.amount = -abs(amount) }
            case .in:
                if let amount = AmountParsing.parse(text) { tx.amount = abs(amount) }
            case .memo:
                tx.memo = text
            case .balance:
                return
            }
            parent.document.mutate("Add Entry", undoManager: parent.undoManager) { file in
                guard let index = file.accounts.firstIndex(where: { $0.id == accountID }) else { return }
                file.accounts[index].transactions.append(tx)
            }
            parent.selectedRowID = tx.id
            reload()
        }

        private func applyName(_ text: String, to tx: inout Transaction, accountID: UUID) {
            if let resolution = TransferParsing.resolve(
                typedName: text, currentAccountID: accountID, in: parent.document.file
            ) {
                tx.transfer = resolution.target
                tx.name = ""
            } else {
                tx.transfer = nil
                tx.name = text
            }
        }

        private func applyEdit(_ text: String, to row: RegisterRow, column: ColumnID) {
            let document = parent.document
            let displayedAccountID = parent.accountID
            let mirror = row.isTransferMirror

            document.mutate("Edit Entry", undoManager: parent.undoManager) { file in
                guard let accountIndex = file.accounts.firstIndex(where: { $0.id == row.ownerAccountID }),
                      let txIndex = file.accounts[accountIndex].transactions.firstIndex(where: { $0.id == row.id })
                else { return }
                var tx = file.accounts[accountIndex].transactions[txIndex]

                switch column {
                case .date:
                    if let date = DateParsing.parse(text, order: AppSettings.dateOrder) { tx.date = date }
                case .check:
                    tx.checkNumber = text
                case .name:
                    guard !mirror else { break }
                    var copy = tx
                    // Resolve transfers against the file inside the mutation.
                    if let resolution = TransferParsing.resolve(
                        typedName: text, currentAccountID: row.ownerAccountID, in: file
                    ) {
                        copy.transfer = resolution.target
                        copy.name = ""
                    } else {
                        copy.transfer = nil
                        copy.name = text
                    }
                    tx = copy
                case .out:
                    if text.isEmpty {
                        if displayedPerspectiveAmount(tx, mirror: mirror) < 0 { tx = settingDisplayedAmount(tx, 0, mirror: mirror) }
                    } else if let amount = AmountParsing.parse(text) {
                        tx = settingDisplayedAmount(tx, -abs(amount), mirror: mirror)
                    }
                case .in:
                    if text.isEmpty {
                        if displayedPerspectiveAmount(tx, mirror: mirror) > 0 { tx = settingDisplayedAmount(tx, 0, mirror: mirror) }
                    } else if let amount = AmountParsing.parse(text) {
                        tx = settingDisplayedAmount(tx, abs(amount), mirror: mirror)
                    }
                case .memo:
                    tx.memo = text
                case .balance:
                    break
                }
                file.accounts[accountIndex].transactions[txIndex] = tx
            }
            _ = displayedAccountID
            reload()
        }

        /// The transaction's amount as seen from the displayed register.
        private func displayedPerspectiveAmount(_ tx: Transaction, mirror: Bool) -> Decimal {
            mirror ? -tx.amount : tx.amount
        }

        /// Store a displayed-perspective amount back onto the transaction.
        private func settingDisplayedAmount(_ tx: Transaction, _ displayed: Decimal, mirror: Bool) -> Transaction {
            var copy = tx
            copy.amount = mirror ? -displayed : displayed
            return copy
        }
    }
}
