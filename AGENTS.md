# Working in Broccoli

Broccoli is a native Mac launcher for macOS 26 and later. Release builds support both Apple silicon and Intel Macs.

Read `DESIGN.md` before changing anything a user can see or interact with.

## Where things live

| Path | What belongs there |
| --- | --- |
| `Sources/BroccoliCore` | Search, calculator, persistence, models, and other UI-independent behavior |
| `Sources/BroccoliApp` | AppKit and SwiftUI UI, app lifecycle, permissions, hotkeys, clipboard monitoring, and actions |
| `Sources/BroccoliBenchmark` | Release-mode performance checks |
| `Tests/BroccoliCoreTests` | Core behavior and persistence tests |
| `Tests/BroccoliAppTests` | Launcher, Settings, rendering, icons, permissions, and window-management tests |
| `Support` | Bundle metadata, entitlements, icons, and brand assets |
| `scripts` | The supported build, verification, and local-install commands |

## Find the right code first

| Area | Start here | Keep true |
| --- | --- | --- |
| App launch and window ownership | `BroccoliMain.swift`, `AppDelegate.swift` | SwiftUI owns the app and Settings scenes. The launcher itself is an AppKit panel. The placeholder SwiftUI launcher window must remain suppressed. |
| Launcher behavior | `LauncherCoordinator.swift`, `LauncherModeController.swift` | One coordinator owns query state, modes, selection, and execution. Do not add a parallel state path for one feature. |
| Launcher window and controls | `LauncherPanelController.swift`, `LauncherThemeController.swift` | AppKit owns the live search field, result rows, keyboard handling, geometry, and materials. Measurements stay centralized. |
| Search and ranking | `BroccoliCore/SearchEngine.swift`, `SearchModels.swift`, `SearchNormalizer.swift` | Search stays deterministic and UI-independent. Raw queries are not persisted. |
| Applications and System Settings | `ApplicationCatalogService.swift`, `SystemSettingsCatalogService.swift`, `SystemSettingsIconResolver.swift` | Discovery remains incremental and searchable. Use native application and System Settings artwork through the existing icon path. |
| File search | `FileSearchService.swift`, `ApplicationDiscoveryPolicy.swift` | File search is explicit, bounded, and does not expose excluded or inaccessible locations. |
| Calculator | `BroccoliCore/CalculatorEngine.swift` | Calculation is offline and independent of UI state. |
| Clipboard | `ClipboardMonitor.swift`, `ClipboardKeyProvider.swift`, `BroccoliCore/ClipboardPersistence.swift` | Stored history remains encrypted, retention-bounded, and fail-closed. Preserve sensitive-content and ignored-application exclusions. |
| Actions and permissions | `ActionRegistry.swift`, `ActionExecutor.swift`, `AudioController.swift`, `AutomationPermission.swift`, `WindowManagement.swift` | Keep policy, permission checks, and execution separate. A denied permission must not become an attempted action. |
| Preferences and persistence | `AppPreferences.swift`, `PreferenceModels.swift`, `BroccoliCore/Persistence.swift` | Keep old stored values decodable and sanitize invalid values instead of crashing or silently changing unrelated preferences. |
| Settings | `Settings/BroccoliSettingsView.swift`, `SettingsDetailView.swift`, `SettingsModels.swift`, `SpotlightSettingsComponents.swift` | The shell owns navigation and search. Individual panes own only their feature state. Shared visual decisions belong in the shared components. |
| Launcher preview | `LauncherPreviewRenderer.swift`, `LauncherInteractivePreview.swift` | The preview uses the production measurements and rendering decisions. It must not become a second approximation of the launcher. |
| Updates | `Updates/`, `Settings/Panes/AboutSettingsPane.swift` | Update eligibility, policy, presentation, and Sparkle callbacks remain separate. Routine background checks stay quiet; download and installation consent must remain explicit. |
| Bundle and release work | `Support/`, `scripts/` | Keep the bundle identifier, signing requirements, entitlements, version metadata, architecture checks, and appcast expectations aligned. |

## Branches and a dirty worktree

Check `git status -sb` before editing. Uncommitted changes belong to the working directory, not to the branch name shown in the prompt, and will follow a checkout when Git can carry them across.

- `main` is the product baseline and the home for repository guidance.
- `release-infra` owns release automation and updater work until the user explicitly approves bringing it to `main`.
- Do not copy, restore, or partially apply `release-infra` files while `main` is checked out.
- Do not switch branches with a dirty worktree until every changed and untracked file has been accounted for and the user has approved the Git operation.
- Never treat an untracked file as disposable. It may be the only copy of the user's work.

## Commands

Run commands from the repository root and use the scripts instead of rebuilding their behavior by hand.

| Task | Command |
| --- | --- |
| Focused test | `zsh -c 'source scripts/select-xcode.sh && swift test --filter <TestName>'` |
| Full tests | `zsh -c 'source scripts/select-xcode.sh && swift test'` |
| Performance checks | `zsh scripts/run-benchmark.sh` |
| Build without installing, only when explicitly requested | `zsh scripts/build-app.sh` |
| Verify the local app | `zsh scripts/verify.sh` |
| Build and verify the universal app | `VERIFY_UNIVERSAL=1 zsh scripts/verify.sh` |
| Build or run Broccoli for the user | `zsh scripts/install-local.sh` |

When the user asks to build or run Broccoli, use `scripts/install-local.sh`. A successful build must replace `/Applications/Broccoli.app` and relaunch that installed copy; leaving a new app only in `build/` does not satisfy the request. Use `scripts/build-app.sh` by itself only when the user explicitly asks for a build without installation, or when another supported script invokes it internally. Documentation-only work does not need an install.

The installer must stop Broccoli processes launched from both the Applications bundle and the repository build bundle, including processes with launch arguments. After relaunch, verify that the running executable comes from `/Applications/Broccoli.app`, that no `build/Broccoli.app` process remains, and that both executables have the same hash. Replacing a bundle on disk does not replace a process already running from that bundle.

## Make changes without creating new problems

- Read the affected implementation, its callers, and its existing tests before editing.
- Keep the change about the requested behavior. Do not mix in unrelated cleanup.
- Preserve unrelated worktree changes. Never discard or include them just to make the diff tidy.
- Reuse the existing component, preference model, metric source, icon registry, or persistence path when it fits. Do not create a second way to do the same job.
- Add regression coverage for bug fixes and behavior changes when the behavior can be tested reliably.
- When changing stored data or preferences, preserve decoding compatibility and sanitization.
- Keep Swift concurrency boundaries intact. Do not add `@unchecked Sendable` without a real synchronization invariant and coverage for it.
- Do not edit generated content in `.build/`, `build/`, or release output directories.

Before finishing, inspect the nearby behavior most likely to have been affected. Passing compilation is not enough.

## Architecture that should stay true

- `BroccoliCore` must not depend on `BroccoliApp` or import AppKit or SwiftUI.
- Keep UI and application-lifecycle concerns in `BroccoliApp`.
- Put reusable domain behavior in `BroccoliCore` when it does not need UI or lifecycle state.
- Keep launcher geometry and appearance values in `LauncherThemeController.swift` and its metric types.
- Keep the live launcher and its Settings preview on the same measurements and rendering decisions.
- Fix shared Settings layout in the shared component rather than nudging one pane with local constants.

## The approved Settings baseline

The Settings UI currently on `main` is the approved design. A request to fix Settings behavior is not permission to restyle or restructure it.

- Keep the SwiftUI `Settings` scene in `BroccoliMain.swift`.
- Keep `BroccoliSettingsNativeSearchSplitView` as the active shell: a balanced `NavigationSplitView` with the sidebar permanently visible.
- Keep `SettingsNativeSearchSidebarView` and SwiftUI's native `.searchable(..., placement: .sidebar)`. Do not replace it with the unused custom search-field path or a different container without explicit approval.
- Keep the sidebar toggle removed, the existing section order and symbols, the navigation history behavior, and the geometry in `SettingsShellLayout`.
- Keep `SettingsDetailView` as the single router for General, Appearance, Search, Files, Calculator, Clipboard, Window Management, Actions, Permissions, and About.
- Keep update controls in About and permission controls in their existing panes. Do not move them as incidental cleanup.
- Do not change the deployment target to work around a visual bug. Prove which process and bundle are running, inspect saved window state, and compare the current UI before editing.

If a task truly needs a different shell, sidebar, search placement, pane order, window size, or shared component appearance, explain the visible change and get explicit approval first.

## macOS compatibility

- macOS 26 is the deployment floor. Do not change it without explicit approval.
- Keep `Package.swift`, `Support/Info.plist`, asset compilation, release verification, Homebrew metadata, and user-facing documentation aligned with that floor.
- Guard APIs introduced after macOS 26 with `#available` or an equivalent supported abstraction.
- Core behavior, keyboard use, accessibility, and readable presentation must work on every supported release.
- Release work must produce and verify a universal `arm64` and `x86_64` application.
- When compatibility code changes, test on the oldest affected macOS version when that machine or VM is available. If it is not available, say exactly what remains unverified.

## Performance

Do not accept a repeatable performance regression.

For performance-sensitive work, measure the affected path before editing and after the final implementation under equivalent conditions. Report median and p95 when the measurement is repeated. An optimization must improve the path it claims to optimize; unrelated work must not make that path measurably slower.

The current release benchmark checks these p95 ceilings:

- Search: 10 ms
- Calculator: 2 ms
- Clipboard filtering: 5 ms

Those are regression ceilings, not targets. Also consider activation, launcher presentation, keystroke-to-results latency, indexing, rendering, icon loading, clipboard monitoring, persistence, memory, and idle CPU when a change can affect them. If the relevant path is not measured yet, add a focused measurement when practical or disclose the gap.

## UI work

- Follow `DESIGN.md` and use the existing components and centralized metrics.
- Inspect the states touched by the change: empty and populated, selected and unselected, focused and inactive, disabled, error, permission denied, resized, and long content where applicable.
- Check Light and Dark appearances. Check Reduce Transparency and Increase Contrast when material or contrast changes.
- Verify keyboard navigation, focus restoration, Return and Escape, and useful accessibility labels.
- Compare the live launcher with its Settings preview whenever either rendering path changes.
- Say plainly when visual inspection was not performed. Automated tests do not replace that disclosure.

## Permissions on the development Mac

macOS privacy permissions cannot be granted by the app or a normal build script. Keep the production bundle identifier and local designated requirement stable so existing grants continue to identify Broccoli across rebuilds.

- Do not reset TCC permissions or change Privacy & Security settings unless the user explicitly asks for permission-onboarding testing.
- Test allowed, denied, not-requested, and unavailable states through the existing permission abstractions where possible.
- If the installed app needs a manual grant, open or identify the correct System Settings pane and report the remaining step. Never claim that a permission was granted automatically.

## Git and publishing

All Git mutations require the user's specific approval. This includes staging, committing, amending, merging, rebasing, tagging, creating or publishing branches, rewriting history, and pushing. Approval to edit files is not approval for any of those actions. Approval to commit is not approval to push.

When work is ready, leave it unstaged and report the intended files, verification performed, and a proposed commit subject. Wait for approval before staging or committing, then wait for separate approval before pushing.

The installed application may contain uncommitted work. If so, state that it is newer than GitHub and is not represented by a remote commit. Do not say a build is on GitHub until the exact commit has been pushed and the remote state has been checked.

Never bypass hooks or checks with `--no-verify`. Never commit secrets, credentials, local environment files, build products, or debug artifacts.

`AGENTS.md` is the instruction layer. The project `.codex/config.toml` and `.codex/rules/git.rules` are the enforcement layer that sends Git mutations to the user for approval. Do not weaken or remove that protection unless the user explicitly asks to change the approval policy.

## What done means

Use focused checks while iterating. Before handing off:

| Change | Required finish |
| --- | --- |
| Source or app resources | `zsh scripts/install-local.sh` |
| User-visible UI | Install/relaunch plus visual and keyboard inspection |
| Performance-sensitive code | Baseline/after evidence plus install/relaunch |
| Build, signing, entitlements, bundle, or release work | Relevant full verification; universal verification for release work |
| Documentation only | Diff review and `git diff --check` |

Review the final diff for accidental changes, debug code, generated files, and unsupported claims. If a check cannot run, give the exact command, the blocker, and the remaining risk.

Finish with the changed behavior and files, checks actually run, anything still unverified, current Git status, and a proposed commit subject. Do not stage or commit it.
