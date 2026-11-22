# 2. Domain events go to a pluggable sink, not an in-memory store

Status: accepted

V1 emits Focus Session and Pomodoro Cycle completion events but deliberately
keeps no analytics store: adding one in V2 (SQLite or any other database) must
not require changing the engines or the overlay UI. The engines fire
`focusSessionCompleted(sessionId, durationMinutes, timestamp)` and
`cycleFinished(cycleId, timestamp)`. **The seam is the engine signals
themselves.** V1 attaches no persistent listener: the only connections are a
test-only event capture, disabled in normal use. V2 connects a concrete adapter
(SQLite or any other database) without editing an engine or a view. There is no
sink object in V1 on purpose — adding a one-implementation wrapper would be a
hypothetical seam. In-memory recording is rejected because it would create a
storage-shaped interface that has to be discarded or hidden when a real
database arrives, and would invite callers to depend on transient state.

Consequences: a listener is the only thing V2 adds at this seam. Timestamps are
Unix epoch milliseconds and IDs are stable within a shell run, so any adapter
can key its records without reinterpretation.
