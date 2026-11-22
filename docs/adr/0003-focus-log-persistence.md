# 3. Focus Log persists in a client-local SQLite database with resumable Focus Sessions

Status: accepted

V2 persists the Focus Log in a client-local SQLite database at
`Quickshell.statePath("zenclock/focus-log.sqlite3")`. A single root-level
`FocusLog.qml` adapter connects to the three existing completion signals and
records a Focus Record, a Cycle Record, or a Countdown Record for each. **The
public seam is the database file and its versioned, documented schema** — not a
typed SDK, IPC query method, or HTTP endpoint — so any tool can answer "how much
have I focused?" without our permission. A separate one-row checkpoint stores
the remaining seconds, phase, and Pomodoro Cycle position of an interrupted
Focus Session, so after a shutdown of any length the existing primary button
already reads "Resume" and the existing Reset button discards it.

QML in Quickshell 0.3.2 has no SQL API and this plugin has no native layer, so
the adapter spawns `/usr/bin/python3` through `Quickshell.Io.Process`, feeding
newline-delimited JSON on stdin; the helper uses parameterized SQL and
transactions and is unit-testable on its own. A checkpoint is written on
`pause()` and every 30 seconds of running time — roughly 350k tiny upserts a
year against one constant-size row — while records grow by about 10k rows (~1
MB) a year. Pruning is therefore exposed as a documented operation backed by a
policy table, not an automatic job. Checkpoints never expire by default; that
is what lets a session be resumed months later.

ADR 0002 promised that V2 would add a SQLite adapter without touching an engine
or a view. That holds for the recording path, but restoring a checkpoint needs a
small `restoreSnapshot(...)` function on `PomodoroEngine.qml`, now also passed
the persisted `session_number` so an edited checkpoint restores the stored cycle
position; that clause is superseded for checkpoint restore only. The one view
change in this same exception is a pure label derivation in `PomodoroView.qml`:
"Resume" applies to a paused, partially elapsed **any** active phase — Focus
Session, Short Break or Long Break — rather than only a Focus Session, so a
restored Long Break no longer reads "Play". It adds no new UI, state, or
interaction. Reset discards the checkpoint synchronously and suppresses
checkpoint writes until a new phase actually starts, so the asynchronous clear
response is not load-bearing. No popup, desktop notification, or new UI is
introduced — the fullscreen HUD's own button is the entire interaction.

Considered options: the `sqlite3` CLI via `Process` was rejected because it
means hand-escaped SQL and no direct unit tests; a JSON file via `FileView` was
rejected because it is not SQLite; an append-only checkpoint history was
rejected because it grows without bound for no benefit; in-memory recording was
already rejected in ADR 0002.

Consequences: the database carries a `schema_version` table from day one and
only ever changes additively, so an old Focus Log keeps working after an
upgrade. Timestamps stay Unix epoch milliseconds in UTC, local day boundaries
are a query-time concern, and the full ID string is the primary key. The Focus
Log is strictly local: no network, telemetry, sync, or automatic deletion. The
canonical focus-time metric is completion-only and uses the configured Focus
Session duration rather than measured elapsed time; this limitation is
published in the schema reference instead of being hidden.
