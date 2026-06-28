# Cross-cutting requirements

Behavioral requirements that apply to every feature, not just one. These drive acceptance tests at
the feature level.

- **X-1 (ubiquitous) — Single-invocation, hotkey-bindable.** Every operation the system offers shall
  be performable by a single non-interactive CLI invocation, with no prompts, suitable for direct
  binding to a hotkey (skhd). Exit status shall be `0` on success and non-zero on failure.

- **X-2 (ubiquitous) — Machine-readable output.** Query/read operations shall emit a stable,
  parseable representation (JSON) on stdout, so output can be consumed by scripts and other tools.
  Human-oriented diagnostics go to stderr.

- **X-3 (unwanted) — Safe failure, never the wrong target.** If the designated notification is
  absent, stale, or out of range, the system shall fail cleanly (non-zero exit, diagnostic on
  stderr) and perform **no** action — it shall never act on a different notification than the one
  designated.

- **X-4 (event) — Permission preflight.** When any operation is invoked without the required
  Accessibility trust ([C-2](constraints.md)), the system shall report the missing permission and
  how to grant it, and exit non-zero, rather than producing empty or misleading results.
