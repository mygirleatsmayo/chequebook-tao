import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our document type: a JSON register file with the .chq extension.
    /// (Deliberately NOT .CBTao so the old app keeps owning its own files.)
    static let chequebookRegister = UTType(exportedAs: "com.chequebooktao.register")

    /// The ORIGINAL app's register files. We can open them directly — saving
    /// converts to .chq, so old files are never modified.
    static let legacyCBTao = UTType(importedAs: "com.jyxes.checkbooktao.register")
}

/// The document: a reference type so one instance is shared by the whole
/// window, with snapshot-based undo (the files are small).
final class RegisterDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = RegisterFile

    static var readableContentTypes: [UTType] {
        var types: [UTType] = [.chequebookRegister, .legacyCBTao]
        // When the ORIGINAL app is installed, its exported UTI owns the .CBTao
        // extension and outranks our imported declaration — the same file then
        // resolves to an identifier we can't know statically. Accept whatever
        // type the user's system actually assigns to the extension.
        if let resolved = UTType(filenameExtension: "cbtao"), !types.contains(resolved) {
            types.append(resolved)
        }
        return types
    }
    static var writableContentTypes: [UTType] { [.chequebookRegister] }

    @Published var file: RegisterFile

    /// Set when this document was opened from an original .CBTao register.
    /// Saving writes a fresh .chq; the old file stays untouched.
    private(set) var legacyImportReport: CBTaoImporter.ImportReport?

    init() {
        // A friendly starter document: one checking account, ready to type into.
        self.file = RegisterFile(accounts: [
            Account(name: "MyChecking", type: .deposit, startingBalance: 0),
        ])
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Sniff rather than trusting the UTI — old files can arrive with odd
        // type resolution, and .chq is always JSON while .CBTao always starts
        // with the CoreData magic.
        if CBTaoImporter.isCBTaoFile(data) {
            let (imported, report) = try CBTaoImporter.importFile(data)
            self.file = imported
            self.legacyImportReport = report
        } else {
            self.file = try RegisterFile.decode(from: data)
        }
    }

    func snapshot(contentType: UTType) throws -> RegisterFile { file }

    func fileWrapper(snapshot: RegisterFile, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }

    /// Perform a mutation with automatic undo/redo via whole-file snapshots.
    func mutate(_ actionName: String, undoManager: UndoManager?, _ body: (inout RegisterFile) -> Void) {
        let before = file
        var copy = file
        body(&copy)
        guard copy != before else { return }
        file = copy
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.mutate(actionName, undoManager: undoManager) { $0 = before }
        }
        undoManager?.setActionName(actionName)
    }
}
