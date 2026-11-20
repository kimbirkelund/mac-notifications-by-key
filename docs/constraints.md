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

  One exception: to open or close the Notification Center panel, the system may post a synthetic
  mouse click on the menu bar clock. The click lands inside the clock element's frame, read from the
  Accessibility API at the time of the click, never at a fixed coordinate, and the pointer is put
  back where it was afterwards. The exception covers the panel only: everything done to a
  notification stays Accessibility-only. Rationale: on macOS 27.2 a panel opened through the
  Accessibility API closes again by itself, and no Accessibility-only opener keeps it open; a click
  on the clock does.

- **C-2 — Accessibility permission required.** The system requires the invoking host to be granted
  Accessibility trust (`AXIsProcessTrusted`). It shall detect the absence of this trust and report
  it actionably (how to grant it, which process needs it) rather than failing opaquely.

- **C-3 — OS-version resilience.** The AX hierarchy of Notification Center is undocumented and
  shifts between macOS releases (it changed across Big Sur, Sequoia, Tahoe). The system shall locate
  notification elements by **structural role/attribute matching** (role, available actions, child
  identifiers), never by hardcoded process id or fixed child indices, and shall degrade gracefully —
  reporting "no notifications found / layout not recognized" — rather than crashing when the layout
  changes. On recent macOS a notification can report a frame that covers the whole list instead of
  its own; when a notification's frame covers another notification's text, the system shall take
  that notification's place and size from where its own text is instead. A rebuilt notification
  shall take its padding, horizontal position and width from a correctly reported notification of
  the same app where there is one, else from any correctly reported notification; a group's header
  row shall bound the top of a rebuilt notification below it, without cutting into its text; and
  stack depth shall be shown only for collapsed stacks.

- **C-4 — macOS only.** The system targets macOS exclusively (it is inherently coupled to the macOS
  Notification Center and AX API). Cross-platform portability is explicitly a non-goal.

- **C-5 — Version-selectable access behind a seam.** Notification Center interaction shall be
  defined by a protocol and obtained through a factory that selects the implementation, so that
  alternative layout implementations (per macOS release, C-3) can be added without changing callers.
  A single implementation is provided today; the factory is the sole selection point. Rationale: C-3
  requires the mechanism to survive OS-version shifts; keeping callers behind one seam means a new
  layout is an added implementation and a factory branch, not an edit spread across the code.
