class_name InteractableStub
extends Area2D
## Test double for Dev A's `Interactable` component
## (`scripts/components/interactable.gd`, SPEC-player-controller: `prompt_text`,
## `hold_seconds`, `interact(player)`). Owned by tests. The real component
## landed (W3-A5, G13b1) and carries the same three members; the stub stays the
## double for duck-typed interactables (Rope, Chest, ...) that do not extend it.
## Sync: none — a test double, never spawned in a live scene.

const DEFAULT_PROMPT: String = "Interact"

var prompt_text: String = DEFAULT_PROMPT
var hold_seconds: float = 0.0
## How many times interact() was called, so a test can assert a single use.
var interactions: int = 0


func interact(_player: Player) -> void:
	interactions += 1
