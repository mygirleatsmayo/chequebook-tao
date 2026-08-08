import XCTest
@testable import ChequebookCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// A tiny synthetic .CBTao register generated from the reverse-engineered
/// format spec (see CBTaoImport.swift). Two live accounts + one ghost:
///   Rent  (sort 1): start +4000 on 1 Aug 2026, "council tax" -12.50 on 2 Aug (memo "monthly")
///   Pub   (sort 2): start +100 on 1 Aug 2026, "pint" -4.00 on 3 Aug in subaccount "darts"
///   ghost "23456789" (inactive, sort -1) must be skipped.
private let fixtureBase64 =
    "Q29yZURhdGEAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGJwbGlzdDAw" +
    "1AABAAIAAwAEAAUABgFZAVxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKvELgA" +
    "BwAIAA4AEgAWABkAGgAaABkAGQAbABwAHQAcAB4AHgAZAB8AHwAbABsAGQAcACAAHAAeAB4AHgAcABwAIQAeAB4AHAAiABwA" +
    "HgAeACMAHgAoACgAHgAZACgAKQAeAB4AHgAeACoAKwAsADEAOABHAFEAHgAaABoAHgAbAFMAVABVAB4AHgAeAB4AKgArAFYA" +
    "WQBeAG0AcQAeAHIAcgAeAHMAcgApAB4AHgAeAB4AKgB0AHUAeAB9AIsAjwAeAB8AHwAeAJEAkgCTAJQAHgAeAB4AHgAqAJUA" +
    "lgCZAJ4ArQAeAB4AGgAaAB4AsQCyABkAswC2AE8AbwC3ALsAwgDKAB4AHgByAHIAHgCxALIAGwDOALYAjQDRANQA2wDjAB4A" +
    "HgDmAOYAHgDnALIAGwDoALYArwDrAO4A9QD9AQAAKwEBAQQBCQEWAQAAdACVARoBHgEjATABMwFAABkAGwBzACsAdACVAE8A" +
    "bwCNAK8BQlUkbnVsbNIACQAKAAsADFgkY2xhc3Nlc1okY2xhc3NuYW1logAMAA1WTlNEYXRlWE5TT2JqZWN00gAJAAoADwAQ" +
    "owAQABEADV8QE05TTXV0YWJsZURpY3Rpb25hcnlcTlNEaWN0aW9uYXJ50gAJAAoAEwAUowAUABUADV5OU011dGFibGVBcnJh" +
    "eVdOU0FycmF50gAJAAoAFwAYogAYAA1eTlNTdG9yZU1hcE5vZGUQASNArycAAAAAABACIwAAAAAAAAAAVFJlbnQQACNAWAAA" +
    "AAAAAFNQdWIT//////////9YMjM0NTY3ODnSACQAJQAmACdWJGNsYXNzV05TLnRpbWWAASNByA8LoAAAACNAr0AAAAAAAFVz" +
    "dGFydF1yZV9zdWJhY2NvdW50EArSACQALQAuAC9aTlMub2JqZWN0c4ADoQAwgDPTACQAMgAtADMANAA2V05TLmtleXOAAqEA" +
    "NYAyoQA3gDTSACQALQAuADmvEBQAOgA7ADwAPQA9AD4APwBAAEEAPQA9AEIAQwBEAEUARgA9AD0APQA9gCeAKIApgACAKoAr" +
    "gCyAJoAtgC6AL4AwgDHVACQASABJAEoASwBMAE0ATgBPAFBfEBFOU0F0dHJpYnV0ZVZhbHVlc1xOU0VudGl0eU5hbWVeTlNQ" +
    "cmltYXJ5S2V5NjReTlNSZWxhdGVkTm9kZXOABIA2V0dMRW50cnkQZIA10gAkACUAJgBSI0HID7RgAAAAI0ApAAAAAAAAV21v" +
    "bnRobHlbY291bmNpbCB0YXjSACQALQAuAFehAFiARtMAJAAyAC0AMwBaAFyhAFuARaEAXYBH0gAkAC0ALgBfrxAUAGAAYQBi" +
    "AD0APQBjAGQAPQBlAGYAZwBoAGkAagBrAGwAPQA9AD0APYA5gDqAO4A8gD2AOIA+gD+AQIBBgEKAQ4BE1QAkAEgASQBKAEsA" +
    "TABuAE4AbwBwgEkQZYBI0gAkACUAJgAnI0BZAAAAAAAAEAMQC9IAJAAtAC4AdqEAd4BY0wAkADIALQAzAHkAe6EAeoBXoQB8" +
    "gFnSACQALQAuAH6vEBQAfwCAAIEAPQA9AIIAgwCEAIUAPQA9AIYAhwCIAIkAigA9AD0APQA9gEyATYBOgE+AUIBRgEuAUoBT" +
    "gFSAVYBW1QAkAEgASQBKAEsATACMAE4AjQCOgFsQZoBa0gAkACUAJgCQI0HIEF0gAAAAEAQjQBAAAAAAAABSeHhUcGludBAM" +
    "0gAkAC0ALgCXoQCYgGvTACQAMgAtADMAmgCcoQCbgGqhAJ2AbNIAJAAtAC4An68QFACgAKEAogA9AD0AowCkAD0ApQCmAKcA" +
    "qACpAKoAqwCsAD0APQA9AD2AXoBfgGCAYYBigF2AY4BkgGWAZoBngGiAadUAJABIAEkASgBLAEwArgBOAK8AsIBuEGeAbV1w" +
    "cmluY2lwYWxBY2N0WnJzX2FjY291bnTSACQALQAuALShALWAd1hyc19lbnRyedIAJAAtAC4AuKIAuQC6gHqAe9MAJAAyAC0A" +
    "MwC8AL+iAL0AvoB2gHmiAMAAwYB4gHzSACQALQAuAMOpAMQAxQDGAMcAyADJAD0APQA9gHCAcYBygHOAdIB11QAkAEgASQBK" +
    "AEsATADLAMwAKwDNgH5cR0xTdWJBY2NvdW50gH3SACQALQAuAM+hANCAh9IAJAAtAC4A0qEA04CK0wAkADIALQAzANUA2KIA" +
    "1gDXgIaAiaIA2QDagIiAi9IAJAAtAC4A3KkA3QDeAN8A4ADhAOIAPQA9AD2AgICBgIKAg4CEgIXVACQASABJAEoASwBMAOQA" +
    "zAB0AOWAjYCMI8AQAAAAAAAAVWRhcnRz0gAkAC0ALgDpoQDqgJbSACQALQAuAOyhAO2AmdMAJAAyAC0AMwDvAPKiAPAA8YCV" +
    "gJiiAPMA9ICXgJrSACQALQAuAPapAPcA+AD5APoA+wD8AD0APQA9gI+AkICRgJKAk4CU1QAkAEgASQBKAEsATAD+AMwAlQD/" +
    "gJyAm1xyX3N1YmFjY291bnTSACQALQAuAQKhAQOAn9MAJAAyAC0AMwEFAQehAQaAnqEBCICg0gAkAC0ALgEKrgELAQwBDQEO" +
    "AQ8BEAERARIBEwEUARUAPQA9AD2ABYAGgAeACIAJgAqAC4AMgA2ADoAP1QAkAEgASQBKAEsATAEXARgAGQEZgKJZR0xBY2Nv" +
    "dW50gKHSACQALQAuARuiARwBHYClgKbTACQAMgAtADMBHwEhoQEggKShASKAp9IAJAAtAC4BJK4BJQEmAScBKAEpASoBKwEs" +
    "AS0BLgEvAD0APQA9gBCAEYASgBOAFIAVgBaAF4AYgBmAGtUAJABIAEkASgBLAEwBMQEYABsBMoCpgKjSACQALQAuATSuATUB" +
    "NgE3ATgBOQE6ATsBPAE9AT4BPwA9AD0APYAbgByAHYAegB+AIIAhgCKAI4AkgCXUACQASABJAEoATAFBARgAc4Cr0wAkADIA" +
    "LQAzAUMBTqoBRAFFAUYBRwFIAUkBSgFLAUwBTYCtgK6Ar4CwgLGAsoCzgLSAtYC2qgFPAVABUQFSAVMBVAFVAVYBVwFYgKOA" +
    "qoCsgH+AjoCdgDeASoBcgG/RAVoBW1dtYXBEYXRhgLcSAAGGoAAIABkAIwAsADEAOgBMAb8BxQHOAdcB4gHnAe4B9wIAAgcC" +
    "HQIqAjMCOgJJAlECWgJfAm4CcAJ5AnsChAKJAosClAKYAqECqgKzAroCwgLEAs0C1gLcAuoC7AL1AwADAgMFAwcDFAMcAx4D" +
    "IQMjAyYDKAMxA1wDXgNgA2IDZANmA2gDagNsA24DcANyA3QDdgOLA58DrAO7A8oDzAPOA9YD2APaA+MD7AP1A/0ECQQSBBUE" +
    "FwQkBCcEKQQsBC4ENwRiBGQEZgRoBGoEbARuBHAEcgR0BHYEeAR6BHwEkQSTBJUElwSgBKkEqwStBLYEuQS7BMgEywTNBNAE" +
    "0gTbBQYFCAUKBQwFDgUQBRIFFAUWBRgFGgUcBR4FMwU1BTcFOQVCBUsFTQVWBVkFXgVgBWkFbAVuBXsFfgWABYMFhQWOBbkF" +
    "uwW9Bb8FwQXDBcUFxwXJBcsFzQXPBdEF0wXoBeoF7AXuBfwGBwYQBhMGFQYeBicGLAYuBjAGPQZCBkQGRgZLBk0GTwZYBmsG" +
    "bQZvBnEGcwZ1BncGjAaOBpsGnQamBqkGqwa0BrcGuQbGBssGzQbPBtQG1gbYBuEG9Ab2BvgG+gb8Bv4HAAcVBxcHGQciBygH" +
    "MQc0BzYHPwdCB0QHUQdWB1gHWgdfB2EHYwdsB38HgQeDB4UHhweJB4sHoAeiB6QHsQe6B70HvwfMB88H0QfUB9YH3wf8B/4I" +
    "AAgCCAQIBggICAoIDAgOCBAIEggnCCkIMwg1CD4IQwhFCEcIVAhXCFkIXAheCGcIhAiGCIgIigiMCI4IkAiSCJQIlgiYCJoI" +
    "rwixCLMIvAjZCNsI3QjfCOEI4wjlCOcI6QjrCO0I7wkACQIJDwkkCSYJKAkqCSwJLgkwCTIJNAk2CTgJTQlPCVEJUwlVCVcJ" +
    "WQlbCV0JXwlhCWYJbglwAAAAAAAAAgIAAAAAAAABXQAAAAAAAAAAAAAAAAAACXVicGxpc3QwMNEBAlhtZXRhZGF0YdIDBAUG" +
    "W05TU3RvcmVUeXBlV2ZpeHR1cmVTWE1MCQgLFBklLTEAAAAAAAABAQAAAAAAAAAHAAAAAAAAAAAAAAAAAAAAMg=="


final class CBTaoImportTests: XCTestCase {

    func fixtureData() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: fixtureBase64))
    }

    func testMagicDetection() throws {
        XCTAssertTrue(CBTaoImporter.isCBTaoFile(try fixtureData()))
        XCTAssertFalse(CBTaoImporter.isCBTaoFile(Data("{}".utf8)))
    }

    func testImportsSyntheticRegister() throws {
        let (file, report) = try CBTaoImporter.importFile(try fixtureData())

        XCTAssertEqual(report.accountCount, 2)
        XCTAssertEqual(report.skippedGhostAccounts, 1)
        XCTAssertEqual(report.entryCount, 4)
        XCTAssertTrue(report.balanceMismatches.isEmpty,
                      "mismatches: \(report.balanceMismatches)")

        XCTAssertEqual(file.accounts.map(\.name), ["Rent", "Pub"])

        let rent = file.accounts[0]
        XCTAssertEqual(rent.transactions.count, 2)
        XCTAssertEqual(rent.transactions[0].name, "start")
        XCTAssertEqual(rent.transactions[0].amount, dec("4000"))
        XCTAssertEqual(rent.transactions[1].name, "council tax")
        XCTAssertEqual(rent.transactions[1].amount, dec("-12.50"))
        XCTAssertEqual(rent.transactions[1].memo, "monthly")
        let comps = utc.dateComponents([.year, .month, .day], from: rent.transactions[1].date)
        XCTAssertEqual([comps.year, comps.month, comps.day], [2026, 8, 2])
        XCTAssertEqual(RegisterEngine.balance(for: rent.id, in: file), dec("3987.50"))

        let pub = file.accounts[1]
        XCTAssertEqual(pub.subaccounts.map(\.name), ["darts"])
        let pint = try XCTUnwrap(pub.transactions.first { $0.name == "pint" })
        XCTAssertEqual(pint.subaccountID, pub.subaccounts[0].id)
        XCTAssertEqual(RegisterEngine.balance(for: pub.id, in: file), dec("96"))
    }

    /// Integration check against a real register from the original app, when
    /// present (private-repo fixture; skipped when absent). Validates the
    /// whole pipeline: every recomputed balance must equal the stored one.
    func testImportsRealRegisterWhenPresent() throws {
        let path = "docs/cheCKbook-tao-exports/DEC 2021 MASTER.CBTao"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("real register fixture not present")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let (file, report) = try CBTaoImporter.importFile(data)

        XCTAssertEqual(report.accountCount, 11)
        XCTAssertEqual(report.entryCount, 83) // 21 orphaned entries from deleted accounts are invisible in the original too
        XCTAssertEqual(report.orphanedEntries, 21)
        XCTAssertEqual(report.skippedGhostAccounts, 11)
        XCTAssertTrue(report.balanceMismatches.isEmpty,
                      "mismatches: \(report.balanceMismatches)")

        let names = file.accounts.map(\.name)
        XCTAssertTrue(names.contains("1. AD DUNCAN"))
        XCTAssertTrue(names.contains("CARRIED OVER"))

        let duncan = try XCTUnwrap(file.accounts.first { $0.name == "1. AD DUNCAN" })
        XCTAssertEqual(RegisterEngine.balance(for: duncan.id, in: file), dec("142"))
        let carried = try XCTUnwrap(file.accounts.first { $0.name == "CARRIED OVER" })
        XCTAssertEqual(RegisterEngine.balance(for: carried.id, in: file), dec("782"))
    }
}

final class NameSuggestionsTests: XCTestCase {

    func makeFile() -> (RegisterFile, UUID) {
        var account = Account(name: "Spending", type: .deposit)
        account.transactions = [
            Transaction(date: day(2026, 8, 1), name: "duncan", amount: dec("-4")),
            Transaction(date: day(2026, 8, 2), name: "duncan", amount: dec("-4")),
            Transaction(date: day(2026, 8, 3), name: "Duncan", amount: dec("-4")),
            Transaction(date: day(2026, 8, 2), name: "waitrose", amount: dec("-12")),
            Transaction(date: day(2026, 8, 4), name: "waterstones", amount: dec("-20")),
        ]
        let other = Account(name: "Savings", type: .deposit)
        return (RegisterFile(accounts: [account, other]), account.id)
    }

    func testFrequencyRanking() {
        let (file, id) = makeFile()
        let all = NameSuggestions.suggestions(forPrefix: "", accountID: id, in: file)
        XCTAssertEqual(all.first, "Duncan") // 3 uses; latest spelling wins display
        XCTAssertEqual(all.count, 3)
    }

    func testPrefixFilterAndRecencyTiebreak() {
        let (file, id) = makeFile()
        let ws = NameSuggestions.suggestions(forPrefix: "wa", accountID: id, in: file)
        XCTAssertEqual(ws, ["waterstones", "waitrose"]) // equal counts; newer first
    }

    func testExactMatchExcludedAndTransfersDelegate() {
        let (file, id) = makeFile()
        XCTAssertFalse(NameSuggestions.suggestions(forPrefix: "duncan", accountID: id, in: file)
            .contains { $0.lowercased() == "duncan" })
        let transfers = NameSuggestions.suggestions(forPrefix: "@sav", accountID: id, in: file)
        XCTAssertEqual(transfers, ["@Savings"])
    }
}
