import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our document type: a JSON register file with the .chq extension.
    /// (Deliberately NOT .CBTao so the old app keeps owning its own files.)
    static let chequebookRegister = UTType(exportedAs: "com.chequebooktao.register")
}

/// The document: a reference type so one instance is shared by the whole
/// window, with snapshot-based undo (the files are small).
final class RegisterDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = RegisterFile

    static var readableContentTypes: [UTType] { [.chequebookRegister] }

    @Published var file: RegisterFile

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
        self.file = try RegisterFile.decode(from: data)
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
