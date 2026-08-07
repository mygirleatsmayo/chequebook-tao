import SwiftUI

enum AccountSheetMode: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let account): return account.id.uuidString
        }
    }
}

/// Add/Edit Account sheet: name, type, starting balance, credit line.
struct AccountSheet: View {
    @ObservedObject var document: RegisterDocument
    let mode: AccountSheetMode
    var onDone: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var name = ""
    @State private var type: AccountType = .deposit
    @State private var startingBalanceText = "0.00"
    @State private var creditLimitText = ""
    @State private var validationMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit Account" : "Add Account")
                .font(.headline)

            Form {
                TextField("Account name:", text: $name)

                Picker("Type:", selection: $type) {
                    Text("Deposit ($) — checking, savings").tag(AccountType.deposit)
                    Text("Credit (%) — card, credit line, loan").tag(AccountType.credit)
                }
                .pickerStyle(.radioGroup)
                .disabled(isEditing) // matching the original: type is set at creation

                TextField(type == .credit ? "Starting amount owed:" : "Starting balance:",
                          text: $startingBalanceText)

                if type == .credit {
                    TextField("Credit line (optional):", text: $creditLimitText)
                }
            }

            if let message = validationMessage {
                Text(message).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: populate)
    }

    private func populate() {
        guard case .edit(let account) = mode else { return }
        name = account.name
        type = account.type
        startingBalanceText = Format.plainNumber.string(from: NSDecimalNumber(decimal: account.startingBalance)) ?? "0"
        if let limit = account.creditLimit {
            creditLimitText = Format.plainNumber.string(from: NSDecimalNumber(decimal: limit)) ?? ""
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard !trimmedName.hasPrefix("@") else {
            validationMessage = "Account names cannot start with @ (that means a transfer)."
            return
        }
        guard !trimmedName.contains(".") else {
            validationMessage = "Account names cannot contain a period — periods separate subaccount names in transfers."
            return
        }

        let editedID: UUID? = {
            if case .edit(let account) = mode { return account.id }
            return nil
        }()
        let clash = document.file.accounts.contains {
            $0.id != editedID && $0.name.compare(trimmedName, options: [.caseInsensitive]) == .orderedSame
        }
        guard !clash else {
            validationMessage = "There is already an account named “\(trimmedName)”."
            return
        }

        let startingBalance = AmountParsing.parse(startingBalanceText) ?? 0
        let creditLimit = creditLimitText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : AmountParsing.parse(creditLimitText)

        switch mode {
        case .add:
            let account = Account(
                name: trimmedName, type: type,
                creditLimit: type == .credit ? creditLimit : nil,
                startingBalance: startingBalance
            )
            document.mutate("Add Account", undoManager: undoManager) { file in
                file.accounts.append(account)
            }
            onDone(account.id)
        case .edit(let original):
            document.mutate("Edit Account", undoManager: undoManager) { file in
                guard let index = file.accounts.firstIndex(where: { $0.id == original.id }) else { return }
                file.accounts[index].name = trimmedName
                file.accounts[index].startingBalance = startingBalance
                file.accounts[index].creditLimit = file.accounts[index].type == .credit ? creditLimit : nil
            }
            onDone(nil)
        }
        dismiss()
    }
}
