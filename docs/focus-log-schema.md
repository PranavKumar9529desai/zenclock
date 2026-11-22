# Focus Log schema

This is the published contract for the Focus Log. It is the seam between Zen
Clock and anything that wants to answer questions about focus work — a dashboard,
a script, a spreadsheet, a BI tool. The database file belongs to the user; Zen
Clock is only one of its writers.

## Location

```
Quickshell.statePath("zenclock/focus-log.sqlite3")
```

Typically `~/.local/state/zenclock/focus-log.sqlite3` (respecting
`XDG_STATE_HOME`). The path is fixed; there is no setting to change it. The
database uses WAL mode, so a dashboard can read it while the overlay is writing.
Never edit the file directly while the shell is running.

## Conventions

- All timestamps are Unix epoch **milliseconds**, UTC (`INTEGER`).
- A "local day" is `date(<column> / 1000, 'unixepoch', 'localtime')`. Day and
  week boundaries belong to the query, not the schema.
- IDs are opaque strings. A Focus Session ID has the form
  `zc-<runId>-f<n>`; a Pomodoro Cycle ID has the form `zc-<runId>-c<n>`.
  These are globally unique in practice even though the engine only promises
  per-run stability, so the full string is the primary key.
- Records are immutable. Writes are idempotent (`INSERT OR IGNORE`) so a
  retried delivery cannot double-count.

## Tables

### `schema_version`

| column | type | meaning |
|---|---|---|
| `version` | `INTEGER PRIMARY KEY` | current schema version, starting at 1 |
| `applied_at` | `INTEGER NOT NULL` | when this version was applied |

One row. A reader should check this before interpreting the tables.

### `focus_record`

One completed Focus Session (see `GLOSSARY.md`).

| column | type | meaning |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | Focus Session ID from `focusSessionCompleted` |
| `duration_minutes` | `INTEGER NOT NULL` | **configured** Focus Session length, not measured elapsed time |
| `recorded_at` | `INTEGER NOT NULL` | completion timestamp |

### `cycle_record`

One completed Pomodoro Cycle.

| column | type | meaning |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | Pomodoro Cycle ID from `cycleFinished` |
| `recorded_at` | `INTEGER NOT NULL` | completion timestamp |

### `countdown_record`

One completed Timer countdown. Kept separate from `focus_record` on purpose:
a generic countdown is not a Focus Session.

| column | type | meaning |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | synthesized as `zc-cd-<recorded_at>-<duration_minutes>` because `countdownCompleted` carries no ID |
| `duration_minutes` | `INTEGER NOT NULL` | configured countdown length |
| `recorded_at` | `INTEGER NOT NULL` | completion timestamp |

### `checkpoint` (internal)

A single upserted row describing an interrupted Focus Session. This table is
documented for completeness but is **not** part of the stable public seam — it
may change without a major version bump.

| column | type | meaning |
|---|---|---|
| `singleton` | `INTEGER PRIMARY KEY CHECK (singleton = 1)` | always 1 |
| `phase` | `TEXT NOT NULL` | `focus`, `shortBreak`, or `longBreak` |
| `remaining_seconds` | `INTEGER NOT NULL` | remaining time at pause/checkpoint; offline time is never subtracted |
| `session_number` | `INTEGER NOT NULL` | position in the Pomodoro Cycle |
| `completed_focus_sessions` | `INTEGER NOT NULL` | progress in the Pomodoro Cycle |
| `saved_at` | `INTEGER NOT NULL` | when the checkpoint was written |

Restoring happens in a paused state, so the existing primary button reads
"Resume"; Reset discards the checkpoint. A checkpoint never expires by default,
so a session paused months ago is still resumable.

### `focus_log_policy` (internal)

| column | type | meaning |
|---|---|---|
| `key` | `TEXT PRIMARY KEY` | `record_retention_days` or `checkpoint_ttl_days` |
| `value` | `INTEGER NOT NULL` | retention in whole days; `0` means keep forever |

| key | default | meaning |
|---|---|---|
| `record_retention_days` | `0` | age past which records are eligible for a manual prune |
| `checkpoint_ttl_days` | `0` | checkpoint retention; `0` means a paused session never expires |

Both rows are created on first use with value `0` (keep forever). Edit a value
with an ordinary SQLite client if you want finite retention; there is no
settings key and no retention UI.

## Manual prune

**No prune runs automatically** — not at startup, not at shutdown, not on any
timer. Cleaning up is an operation you choose to run yourself. It removes only
**records** (Focus Records, Cycle Records and Countdown Records) whose
`recorded_at` is older than `record_retention_days`. It **never** deletes the
`checkpoint`, regardless of its age: a Focus Session paused months ago must
still be resumable. With the default `record_retention_days = 0` the prune
removes nothing at all.

To see what a prune would remove (a keep-forever policy reports zero for every
kind):

```sql
WITH policy AS (
  SELECT CASE WHEN value > 0
              THEN (strftime('%s','now') - value * 86400) * 1000
         END AS cutoff
  FROM focus_log_policy WHERE key = 'record_retention_days'
)
SELECT 'focus_record' AS kind, COUNT(*) AS would_remove
FROM focus_record, policy WHERE recorded_at < policy.cutoff
UNION ALL
SELECT 'cycle_record', COUNT(*) FROM cycle_record, policy
WHERE recorded_at < policy.cutoff
UNION ALL
SELECT 'countdown_record', COUNT(*) FROM countdown_record, policy
WHERE recorded_at < policy.cutoff;
```

To actually prune, run the same deletion for each record table:

```sql
DELETE FROM focus_record
WHERE recorded_at < (
  SELECT CASE WHEN value > 0
              THEN (strftime('%s','now') - value * 86400) * 1000
         END
  FROM focus_log_policy WHERE key = 'record_retention_days'
);
-- repeat the identical DELETE for cycle_record and countdown_record
```

The helper implements this same operation as the `prune` command
(`{"op": "prune", "path": "..."}` on its newline-delimited JSON interface),
reporting how many rows it removed from each record table. It touches only
those three tables: neither the checkpoint nor either policy value is changed.

## Canonical metric

"How much have I focused?" means the sum of configured Focus Session durations
for **completed** Focus Sessions only:

```sql
SELECT SUM(duration_minutes) AS focus_minutes FROM focus_record;
```

Limitations, published rather than hidden:

- A Focus Session counts only on completion. `reset()` and `skip()` emit
  nothing; partially worked time is not credited.
- `duration_minutes` is the configured length (25 by default), not measured
  elapsed time. Changing the configured length mid-session is not reflected.
- Breaks, Stopwatch time, and Timer countdowns are excluded. Countdowns live in
  `countdown_record` for whoever wants them.

Users who disagree with this definition can compute their own from the same
tables — that is the point of the seam.

## Example dashboard queries

Focus minutes per local day:

```sql
SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
       SUM(duration_minutes) AS minutes,
       COUNT(*) AS sessions
FROM focus_record
GROUP BY day ORDER BY day;
```

Today's focus minutes:

```sql
SELECT COALESCE(SUM(duration_minutes), 0) AS minutes
FROM focus_record
WHERE date(recorded_at / 1000, 'unixepoch', 'localtime') = date('now','localtime');
```

Completed Pomodoro Cycles:

```sql
SELECT COUNT(*) FROM cycle_record;
```

Longest focus day:

```sql
SELECT day, minutes FROM (
  SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
         SUM(duration_minutes) AS minutes
  FROM focus_record GROUP BY day
) ORDER BY minutes DESC LIMIT 1;
```

## Versioning rules

1. `schema_version` starts at 1 and increments for every schema change.
2. Changes are additive only: new tables, new nullable columns with defaults,
   new indexes. No renames, no drops, no destructive migrations.
3. An older database must remain readable after a plugin upgrade.
4. A reader that does not recognize `version` should stop and report it rather
   than guess.

## Privacy

The Focus Log stays on the user's machine. No network access, telemetry, sync,
or automatic deletion is part of this contract.
