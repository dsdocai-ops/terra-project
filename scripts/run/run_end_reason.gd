class_name RunEndReason
extends RefCounted
## Why a run ended. Owned by run-economy; consumed by GameState.end_run(),
## RunResult and the end-of-run UI (death/extract screen).
## Sync: host-authoritative. The host decides the reason; clients read it from
## the run_ended broadcast and never choose it themselves.

## The four ways a run can stop (SPEC-run-economy, "Death and extraction rules").
enum Reason {
	DEFEAT,   ## every player is downed or dead
	EXTRACT,  ## the rope vote passed; solo extracts immediately
	VICTORY,  ## the floor-30 boss died (ending sequence, story-dialogue)
	ABORT,    ## the host quit; counts as a death for every player
}
