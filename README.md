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

## Building & maintaining

Open `ChequebookTao.xcodeproj` in Xcode and press Run. That's it.

Project layout:

| Path | What it is |
| --- | --- |
| `Sources/Core/` | All logic: models, balance math, reconcile math, filters, history stats, QIF/CSV/paste parsers. Platform-independent, fully unit-tested. |
| `Sources/App/` | The macOS app: SwiftUI shell, AppKit register table. |
| `Tests/CoreTests/` | Unit tests. Run with `swift test` (works on macOS and Linux) or in Xcode. |
| `Tools/generate_project.py` | Regenerates `ChequebookTao.xcodeproj` deterministically. Run it after adding or removing Swift files: `python3 Tools/generate_project.py`. |
| `.github/workflows/ci.yml` | Tests + builds + zips the app on every push. Tags `v*` publish a GitHub Release. |

The register file format is versioned JSON — open a `.chq` in any text editor.

## Releasing

```sh
git tag v0.1.0 && git push --tags
```

CI attaches the zipped app to a GitHub Release.

## License

MIT — see [LICENSE](LICENSE).
