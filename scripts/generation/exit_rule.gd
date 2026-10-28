class_name ExitRule
extends RefCounted
## The Exit-opens rule (SPEC-floor-generation "Doors and clearing"): the Exit
## requires all COMBAT/ELITE_COMBAT rooms on at least one Start-Exit path to be
## cleared, so the number a floor demands is the fewest locking rooms of any
## simple Start-Exit path. Owned by floor-generation.
## Sync: pure; every peer computes the same number from the same layout. The
## host writes it into `RunState.required_rooms_cleared` when the floor paints.

## Returned when no Start-Exit path exists: one more than the count of locking
## rooms, so `RunState.exit_open` (rooms_cleared >= required) can never fire
## and a broken floor cannot open the Exit by underflowing the requirement.
static func required_clears(layout: FloorLayout) -> int:
	if layout.start_room == null or layout.exit_room == null:
		return 0
	var count: int = layout.rooms.size()
	var locking: int = 0
	for room: RoomSpec in layout.rooms:
		if room.locks():
			locking += 1
	# Dijkstra over the room graph, the cost of a step being 1 when the room it
	# enters locks: the first settle of the Exit is the fewest-locks path.
	var best: Array[int] = []
	best.resize(count)
	best.fill(locking + 1)
	var done: Array[bool] = []
	done.resize(count)
	done.fill(false)
	best[layout.start_room.index] = 0
	for _step: int in count:
		var pick: int = -1
		for index: int in count:
			if not done[index] and best[index] <= locking and (pick < 0 or best[index] < best[pick]):
				pick = index
		if pick < 0:
			break
		done[pick] = true
		for neighbor: int in layout.rooms[pick].neighbors:
			var step: int = best[pick] + (1 if layout.rooms[neighbor].locks() else 0)
			if step < best[neighbor]:
				best[neighbor] = step
	return best[layout.exit_room.index]
