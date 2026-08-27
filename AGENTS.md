# Chequebook Tao

## Core/App seam

`Sources/Core/` is `import Foundation` only — that is the `swift test` target (`ChequebookCore`). New logic goes in Core with a test; `Sources/App/` stays presentation.

Xcode compiles Core + App as **one module**, so App uses Core types with no `import ChequebookCore`. Core declarations stay `public` so the SwiftPM test target can see them.

## Regenerating the Xcode project

After adding or removing a Swift file, and after bumping `VERSION`:

```sh
python3 Tools/generate_project.py
```

Commit the regenerated `project.pbxproj` with that change.

## Domain invariants

Break one and balances silently go wrong:

- Money is `Decimal` end to end — a `Double` near an amount is a bug.
- A transfer is stored **once**, on the account that entered it, and *mirrored* into the target's register at render time (`RegisterEngine`). Never write the far side as a second transaction.
- `RegisterRow.amount` is signed from the *displayed* account's view: positive fills Deposit/Payment, negative fills Withdraw/Charge. Mirrors reuse the source transaction's `id`, unique only within one account's register.
- Credit accounts store the amount **owed**. `available = creditLimit - owed`.
- The unallocated subaccount is derived, never stored.
- `.chq` is versioned JSON.

## Versioning and release

`VERSION` is two lines: marketing version, then build integer. Each shipped binary gets a new pair, then regenerate.

Tag `v` plus the marketing line:

```sh
git tag "v$(head -1 VERSION)" && git push --tags
```

CI publishes the zip onto that GitHub Release.

## Worktrees

`.worktrees/<branch>`. A tester drop's branch is `v` plus the marketing version.

## mayo SDD

This project uses the mayo spec-driven development workflow. The settings below tell the skills where to read and write.

### Issue tracker

Issues live in GitHub Issues and are managed with the `gh` CLI. See `.mayosdd/agents/issue-tracker.md`.

### Triage labels

Use the six default mayo triage labels plus `high-context` and `high-intelligence`. See `.mayosdd/agents/triage-labels.md`.

### Domain docs

This is a single-context repository using root-level `CONTEXT.md` and `.mayosdd/adr/`. See `.mayosdd/agents/domain.md`.
