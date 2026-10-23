class_name RunResult
extends RefCounted
## The end-of-run summary: why the run ended, its seed, floors cleared, and
## each player's kept/lost tables for the death or extract screen. Owned by
## run-economy; built by the host in GameState.end_run().
## Sync: host-authoritative. The host computes it and sends each peer its own
## kept/lost table (run_summary); clients never build or edit a RunResult.
##
## The keep rules themselves are week 5. Week 3 ships the shape: every table
## carries the EMPTY_TABLE_KEYS with neutral values.

## The documented key shape of one kept/lost table.
const EMPTY_TABLE_KEYS: Array[StringName] = [
	&"gold",
	&"ore",
	&"relics",
	&"echo_shards",
	&"class_xp",
]

var reason: RunEndReason.Reason = RunEndReason.Reason.DEFEAT
var seed: int = 0
var floors_cleared: int = 0
## peer_id -> kept table.
var kept: Dictionary[int, Dictionary] = {}
## peer_id -> lost table.
var lost: Dictionary[int, Dictionary] = {}
## peer_id -> the class that player ran, so banking knows whose class gets the XP.
var classes: Dictionary[int, StringName] = {}


func _init(
	p_reason: RunEndReason.Reason = RunEndReason.Reason.DEFEAT,
	p_seed: int = 0,
	p_floors_cleared: int = 0,
) -> void:
	reason = p_reason
	seed = p_seed
	floors_cleared = p_floors_cleared


## A table with the documented keys and neutral values. Real keep/loss rules
## are week 5; the UI can render this shape today.
static func empty_table() -> Dictionary:
	return {
		&"gold": 0,
		&"ore": 0,
		&"relics": [] as Array[StringName],
		&"echo_shards": 0,
		&"class_xp": 0,
	}


## Records one player's kept and lost tables (copies, so callers can reuse
## their dictionaries).
func set_player_tables(peer_id: int, kept_table: Dictionary, lost_table: Dictionary) -> void:
	kept[peer_id] = kept_table.duplicate(true)
	lost[peer_id] = lost_table.duplicate(true)
