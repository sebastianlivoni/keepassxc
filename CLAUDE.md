# CLAUDE.md

Notes for working in this repo, captured while debugging the macOS AutoFill multi-database XPC issue (branch `feature/macos-autofill-v2`).

## Build

CMake build lives in `./build` (already configured). Useful targets:

```
cmake --build build --target keepassxc_gui -j 4   # library incl. src/autofill, src/gui, src/browser
cmake --build build --target KeePassXC -j 4        # full app bundle, links keepassxc_gui
```

`keepassxc_gui` alone is enough to catch compile errors in `src/autofill/` and `src/gui/` without a full relink.

## macOS AutoFill / Credential Provider (XPC)

All under `src/autofill/` (Objective-C++, `.mm`/`.h`, no Swift). Two separate processes talk over an **anonymous NSXPCConnection**:

- **Main app** (`AutoFillXPCService.h/.mm`) — creates an `NSXPCListener`, exports `AutoFillXPCServiceProtocol`, forwards every RPC straight into `AutoFillServiceV2`.
- **`KeePassXCAutoFillExtension.appex`** (the sandboxed `ASCredentialProviderViewController`, `CredentialProviderViewController.h/.mm`) — mirrors the connection via `AutoFillXPCServiceClient.h/.m`.
- Since the two processes are sandboxed and can't otherwise discover each other's anonymous listener endpoint, a tiny **rendezvous broker** LaunchAgent (`src/autofill/rendezvous/`, registered via `SMAppService`) hands off the endpoint between them.
- Shared credential-lookup logic lives in `AutoFillService.h/.mm` (static helpers, usable from either process). The main-app-only stateful half — XPC glue, "current database" tracking, pending-unlock bookkeeping — is `AutoFillServiceV2.h/.mm` (a `QObject`, singleton via `autoFillServiceV2()`).
- XPC callbacks arrive off the Qt main thread; every handler in `AutoFillServiceV2` immediately does `dispatch_async(dispatch_get_main_queue(), ^{ ... })` before touching any Qt object.

### Identifying which database an entry belongs to

- Every AutoFill `recordIdentifier` is `"<dbUuidHex>:<entryUuidHex>"`, built by `AutoFillService::recordIdentifierForEntry` and parsed back by `AutoFillService::parseRecordIdentifier`.
- The `dbUuid` is `Database::publicUuid()` (`src/core/Database.cpp`) — stored in the **unencrypted** KDBX4 header (`PublicCustomData["KPXC_PUBLIC_UUID"]`). Crucially, this is readable **even while the database is locked**: `DatabaseWidget` swaps in a fresh, header-only `Database` on lock (`DatabaseWidget.cpp` `replaceDatabase`), but the header (and thus `publicUuid()`) is still parsed. `DatabaseOpenWidget` already relies on this for quick-unlock key lookup.
- `MainWindow::getOpenDatabases()` returns every open tab's `DatabaseWidget*`, locked or unlocked, with no filtering — this is the registry to search when resolving a `recordIdentifier` to a specific open database.
- Precedent for "find the right open database by UUID": `BrowserService::getDatabase(QUuid rootGroupUuid)` in `src/browser/BrowserService.cpp` does the same kind of scan for the browser extension. AutoFill's equivalent is `AutoFillServiceV2::findDatabaseWidgetByUuid()`.

### Unlocking a specific (possibly non-focused) database

- `DatabaseTabWidget::unlockDatabaseInDialog(DatabaseWidget*, Intent)` shows the unlock UI **targeted at one specific widget** — prefer this over `unlockAnyDatabaseInDialog(Intent)`, which shows a picker across all locked tabs (used by `performBrowserUnlock`/global AutoType instead).
- `DatabaseOpenDialog::Intent` enum: `None, AutoType, Merge, RemoteSync, Browser`. `displayUnlockDialog()` only special-cases `AutoType`/`Browser` to raise the app window first on macOS — AutoFill reuses `Intent::Browser` for this reason rather than adding a new enum value.
- `MainWindow::databaseUnlockDialogFinished(bool accepted, DatabaseWidget*)` fires when the unlock dialog closes (accepted or cancelled) — the only reliable "give up waiting" signal; `DatabaseWidget::databaseUnlocked()` alone doesn't tell you if it was cancelled.

### Bug fixed 2026-07 (commit f1b288d5)

`AutoFillServiceV2` resolved every credential fetch (password/OTP/passkey) against `m_currentDatabaseWidget` (whichever tab was focused in the GUI) instead of the `dbUuid` already embedded in the `recordIdentifier` — so requests for entries in a non-focused open database silently failed, and there was no way to trigger unlock UI for a locked *non-focused* database at all (dead empty `else` branch in `performAutofillUnlock`). Any database unlocking would also resolve/clear whatever pending request existed, regardless of whether it was the right one. Fixed by resolving via `findDatabaseWidgetByUuid()` everywhere, threading the target `DatabaseWidget*` through the unlock-trigger path, and only clearing a pending request when the unlocked (or dialog-cancelled) widget matches its stashed target.

### Known follow-ups (not yet fixed)

- `CredentialProviderViewController.mm` (`-unlockDatabase`, ~line 187-217) has a hardcoded dev database path and password, currently unreachable dead code (guarded by an early `return;`).
