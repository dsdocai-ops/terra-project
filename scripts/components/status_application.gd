class_name StatusApplication
extends RefCounted
## One status a hit applies: which status and how many stacks. Owned by
## combat-core. Sync: none, ephemeral and built on the host with the HitInfo.

var status: StatusEffects.Status = StatusEffects.Status.BURN
var stacks: int = 1


static func make(status_id: StatusEffects.Status, stack_count: int = 1) -> StatusApplication:
	var application := StatusApplication.new()
	application.status = status_id
	application.stacks = stack_count
	return application
