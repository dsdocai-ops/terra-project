class_name PotionData
extends ContentData
## One potion type (SPEC-run-economy "Potions"): heal, cleanse, haste, shield.
## Owned by run-economy (W5-B3). Sync: none (data). `data/potions/<id>.tres`,
## the id is the file name; the Alchemist building unlocks types and slots.

enum Kind { HEAL, CLEANSE, HASTE, SHIELD }

@export var kind: Kind = Kind.HEAL
## Heal: fraction of max HP restored (Potion Mastery adds 0.15 per rank).
@export var heal_fraction: float = 0.0
## Haste: seconds it lasts and the move speed bonus (0.3 = +30%).
@export var duration: float = 0.0
@export var speed_bonus: float = 0.0
## Shield: how many incoming hits it absorbs.
@export var absorb_hits: int = 0
## Base shop price in gold.
@export var price: int = 40
