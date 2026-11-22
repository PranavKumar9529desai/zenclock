# 2. Domain events go to a pluggable sink, not an in-memory store

Status: accepted

V1 emits Focus Session and Pomodoro Cycle completion events but deliberately
keeps no analytics store: adding one in V2 (SQLite or any other database) must
not require changing the engines or the overlay UI. The engines fire
`focusSessionCompleted(sessionId, durationMinutes, timestamp)` and
`cycleFinished(cycleId, timestamp)` into a small event-sink interface whose
default adapter is a no-op; V2 supplies a different adapter at the same seam.
In-memory recording is rejected because it would create a storage-shaped
interface that has to be discarded or hidden when a real database arrives, and
would invite callers to depend on transient state.

Consequences: the no-op adapter and a test recording adapter are both valid at
the seam, which keeps it honest; V2 adds a SQLite adapter without touching any
engine or any view. Timestamps are Unix epoch milliseconds and IDs are stable
within a shell run, so any adapter can key its records without reinterpretation.
