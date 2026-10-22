class_name Team
extends RefCounted
## Which side an entity fights for. Owned by combat-core.
## Sync: none. A constant per entity, set in its scene.
##
## `PLAYER` also covers minions and turrets (SPEC-combat-core). `NEUTRAL` is for
## destructibles: players' hits land on them, enemies' do not.

enum Kind { PLAYER, ENEMY, NEUTRAL }


## Whether a hitbox on side `attacker` may hurt a hurtbox on side `victim`.
static func opposes(attacker: Kind, victim: Kind) -> bool:
	match attacker:
		Kind.PLAYER:
			return victim != Kind.PLAYER
		Kind.ENEMY:
			return victim == Kind.PLAYER
		_:
			return false
