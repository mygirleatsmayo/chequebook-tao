# Chequebook Tao

Native macOS rebuild of *Checkbook Tao Register*. `README.md` describes the app and its layout.

## The Core/App seam

`Sources/Core/` is platform-independent — `import Foundation` only. That is what lets `swift test` run the whole logic layer through the `ChequebookCore` SwiftPM package. New logic goes in Core with a test; `Sources/App/` stays presentation.

Xcode compiles Core + App as **one module**, so App files use Core types with no `import ChequebookCore`. Core declarations still need `public` for the SwiftPM test target to see them.

## After adding or removing a Swift file

```sh
python3 Tools/generate_project.py
```

`project.pbxproj` is generated, not hand-edited. Commit it alongside the source change.

## Domain invariants

Break one and balances silently go wrong:

- Money is `Decimal` end to end — a `Double` near an amount is a bug.
- A transfer is stored **once**, on the account that entered it, and mirrored into the target's register at render time (`RegisterEngine`). Never write the far side as a second transaction.
- `RegisterRow.amount` is signed from the *displayed* account's view: positive fills Deposit/Payment, negative fills Withdraw/Charge. Mirrors reuse the source transaction's `id`, unique only within one account's register.
- Credit accounts store the amount **owed**, not a negative balance. `available = creditLimit - owed`.
- The unallocated subaccount is derived, never stored.
- `.chq` is versioned JSON and stays readable in a text editor.

## Versioning

`VERSION` is the source of truth. Two lines:

1. Marketing version (`0.2.0`) — what testers see. Bump for every binary you hand someone.
2. Build number (`2`) — integer, always increases. Never reuse a pair.

Then regenerate the Xcode project so About and Get Info match:

```sh
python3 Tools/generate_project.py
```

Do not ship two builds that both say `0.2.0 (2)`.

## Worktrees

Directory name equals the branch: `.worktrees/<branch>`. For a tester drop, name the branch after the version (`v0.2.0`) so the folder, the About panel, and the git branch agree.

## Releasing

Bump `VERSION`, regenerate, commit, then tag the marketing version:

```sh
git tag v0.2.0 && git push --tags
```

The tag must match line 1 of `VERSION`. CI zips the app onto a GitHub Release.
