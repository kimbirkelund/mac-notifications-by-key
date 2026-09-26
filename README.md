# mac-notifications-by-key

[![CI](https://github.com/kimbirkelund/mac-notifications-by-key/actions/workflows/ci.yml/badge.svg)](https://github.com/kimbirkelund/mac-notifications-by-key/actions/workflows/ci.yml)
[![Release](https://github.com/kimbirkelund/mac-notifications-by-key/actions/workflows/release.yml/badge.svg)](https://github.com/kimbirkelund/mac-notifications-by-key/actions/workflows/release.yml)

A keyboard-driven tool for interacting with macOS notifications. It reads the notifications macOS is
currently presenting and acts on a designated one — dismiss, trigger a named action, or activate —
exposed as one-shot CLI commands (`nbk`) suitable for binding to a hotkey daemon (skhd), plus an
interactive mode that overlays the Notification Center UI.

Notifications are reached **only through the public Accessibility (AX) API** against the
Notification Center process (`com.apple.notificationcenterui`) — there is no public API to read or
act on another app's notifications, and the AX surface exposes notifications as addressable elements
with readable text and named actions. No screenshots/OCR, no fixed-coordinate mouse simulation, no
private frameworks. Requires Accessibility permission for the host process and is only support on
recent versions of macOS.

## Development flow

Requirements are written in **EARS** syntax to guide which feature to work on and to generate
**BDD** acceptance scenarios. Those `.feature` files are made **executable** (cucumber-js, driving
the compiled CLI) and used as the basis for coding. See [`docs/`](docs/_index.md).

## CLI (target shape)

```
nbk list [--wait <seconds>]      # JSON of presented notifications, newest first
nbk dismiss <index>              # dismiss the notification at <index>
nbk action <index> <name>        # perform a named action (e.g. "Show")
nbk press <index>                # default activation (open)
nbk interactive                  # overlay mode: opens the NC panel; Escape or SIGINT/SIGTERM ends it
nbk doctor                       # report Accessibility trust, NC pid, macOS version
```

## Testing

Three tiers (full strategy: [`docs/testing.md`](docs/testing.md)):

- **Unit** — swift-testing. Built test-first (TDD) when practical.
- **AX-integration** — swift-testing against the real Notification Center, gated on Accessibility
  trust; delivers real notifications and reads/acts on them.
- **Acceptance** — cucumber-js runs the `.feature` files under `docs/features/**/acceptance/`
  against the compiled `nbk` binary as a black box.

`./build.ps1 -DoTest` runs all three; `-Kinds Unit|Integration|Acceptance|All` selects a subset.
`-Kinds Operator` runs the attended scenarios, which need a human at the terminal; `All` excludes
it.

## Build / test / run

Use [`build.ps1`](build.ps1) (PowerShell) as the entry point.

```pwsh
./build.ps1 -DoInstall                         # resolve SwiftPM + npm deps
./build.ps1 -DoBuild                            # swift build → .build/
./build.ps1 -DoRun -RunArgs list,--wait,5       # run the CLI in development
./build.ps1 -DoTest                             # build + all three tiers
./build.ps1 -DoTest -Kinds Unit                 # unit only
./build.ps1 -DoTest -Kinds Acceptance -SkipBuild# acceptance against existing build
```

The AX-integration and acceptance tiers need Accessibility trust for the host; `build.ps1`
preflights it (`nbk doctor`) and skips those tiers with a clear message when it is absent.

## CI / release

- **CI** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs on macOS (the only supported
  platform, C-4): a **lint** job (`build.ps1 -DoLint` + actionlint), a **build** job (universal
  release binary), and a **test** job (`-Kinds Unit`). The AX-integration and acceptance tiers can't
  run on hosted runners — they need Accessibility trust and a real on-screen Notification Center —
  so they stay local.
- **Release** ([`.github/workflows/release.yml`](.github/workflows/release.yml)) is triggered by
  pushing a `release/v<version>` tag (final) or an `rc/*` branch (prerelease). It runs the unit
  gate, builds a universal (arm64 + x86_64) binary via `build.ps1 -DoPackage -Version <v>`,
  publishes `nbk-<version>-macos-universal.tar.gz` + a `.sha256` to a GitHub Release, and bumps the
  Homebrew tap (see below).

### Homebrew

Distribution is a personal tap
([`kimbirkelund/homebrew-tap`](https://github.com/kimbirkelund/homebrew-tap)) with prebuilt-binary
formulae. Two channels:

```sh
brew install kimbirkelund/tap/nbk        # stable — tracks final releases
brew install kimbirkelund/tap/nbk-beta   # prerelease — tracks release candidates
```

The two conflict (both install a `nbk` binary), so only one is installed at a time; switch with
`brew uninstall nbk && brew install kimbirkelund/tap/nbk-beta` (or vice versa).

The formulae are authored in [`packaging/homebrew/`](packaging/homebrew/) (source of truth); the
Release workflow rewrites `version`/`sha256` and pushes the updated formula into the tap on every
release — final releases bump `nbk`, `rc/*` prereleases bump `nbk-beta`. This requires a
`PAT_RELEASE` secret with write access to the tap repo; without it the bump step is skipped.

The binary is unsigned; Homebrew strips the download quarantine on install. After install, grant
Accessibility permission to whatever runs `nbk` (see `nbk doctor`).

## Project layout

```
Sources/NotificationCore/   pure logic — models, JSON output, selection, action-name parsing (unit-tested)
Sources/NotificationAX/     AX adapter — NotificationCenterAccess seam (protocol + factory), reads/acts on the live tree
Sources/nbk/                the CLI executable wiring Core + AX
Tests/NotificationCoreTests/            unit tier — pure logic (swift-testing)
Tests/NotificationAXUnitTests/          unit tier — AX seam/factory (no AX trust)
Tests/NotificationAXIntegrationTests/   AX-integration tier (gated)
docs/features/**/acceptance/*.feature   acceptance specs (executable via cucumber-js)
acceptance/steps, acceptance/support    cucumber-js step definitions + world
```

## Documentation

See [`docs/`](docs/_index.md). Every documentation directory has an `_index.md` that introduces the
section and links its contents — to understand a section, read its `_index.md` first.
