# Constraints

Non-functional constraints that inform architecture and mechanism selection. Constraints have no
direct acceptance test.

- **C-1 — Accessibility API only.** The system shall interact with notifications exclusively through
  the public Accessibility (AX) API against the Notification Center process. It shall **not** use
  screenshots/OCR, simulated mouse movement to fixed coordinates, or private notification
  frameworks. Rationale: the AX surface exposes notifications as addressable elements with readable
  text and named actions — robust where pixel-matching and blind clicks are not. (Probe evidence:
  macOS 26.5.1 exposes title/subtitle/body and `Close`/`Show`/`Show Details` actions per
  notification element.)

- **C-2 — Accessibility permission required.** The system requires the invoking host to be granted
  Accessibility trust (`AXIsProcessTrusted`). It shall detect the absence of this trust and report
  it actionably (how to grant it, which process needs it) rather than failing opaquely.

- **C-3 — OS-version resilience.** The AX hierarchy of Notification Center is undocumented and
  shifts between macOS releases (it changed across Big Sur, Sequoia, Tahoe). The system shall locate
  notification elements by **structural role/attribute matching** (role, available actions, child
  identifiers), never by hardcoded process id or fixed child indices, and shall degrade gracefully —
  reporting "no notifications found / layout not recognized" — rather than crashing when the layout
  changes.

- **C-4 — macOS only.** The system targets macOS exclusively (it is inherently coupled to the macOS
  Notification Center and AX API). Cross-platform portability is explicitly a non-goal.

- **C-5 — Version-selectable access behind a seam.** Notification Center interaction shall be
  defined by a protocol and obtained through a factory that selects the implementation, so that
  alternative layout implementations (per macOS release, C-3) can be added without changing callers.
  A single implementation is provided today; the factory is the sole selection point. Rationale: C-3
  requires the mechanism to survive OS-version shifts; keeping callers behind one seam means a new
  layout is an added implementation and a factory branch, not an edit spread across the code.
