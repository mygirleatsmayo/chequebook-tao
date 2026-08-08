# Chequebook Tao

A faithful, modern, native macOS rebuild of the abandoned *Checkbook Tao Register* —
the powerfully simple checkbook register. Free software.

- **Native Swift** (SwiftUI + AppKit register table). No Electron, no runtime deps.
- **Document-based**: each register is a portable `.chq` file (plain JSON) holding
  any number of accounts.
- **Same core UX as the original**: deposit (`$`) and credit (`%`) accounts,
  Withdraw/Deposit vs Charge/Payment columns, `@Account` transfers, subaccounts,
  reconcile tools, filters, transaction history, QIF/CSV import, CSV export.
- **Modernized where it doesn't change the UX**: locale-aware currency and dates,
  dark mode, themes.

## Download

Grab the latest zip from [Releases](../../releases) (or the artifact on any CI run).
Unzip, drag to Applications, then **right-click → Open** the first time —
the build is unsigned, so macOS asks once.

## Building

Open `ChequebookTao.xcodeproj` in Xcode and press Run. That's it.

| Path | What it is |
| --- | --- |
| `Sources/Core/` | All logic: models, balance math, reconcile math, filters, history stats, QIF/CSV/paste parsers. Platform-independent, fully unit-tested. |
| `Sources/App/` | The macOS app: SwiftUI shell, AppKit register table. |
| `Tests/CoreTests/` | Unit tests. `swift test`, or run them in Xcode. |

The register file format is versioned JSON — open a `.chq` in any text editor.

Contributing? Read [AGENTS.md](AGENTS.md) — conventions, invariants, and how to release.

## License

MIT — see [LICENSE](LICENSE).
