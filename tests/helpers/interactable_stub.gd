class_name InteractableStub
extends Area2D
## Test double for Dev A's `Interactable` component
## (`scripts/components/interactable.gd`, SPEC-player-controller: `prompt_text`,
## `hold_seconds`, `interact(player)`), so the contract the player's interact
## scan expects is written down in one place while that component does not
## exist. Owned by tests.
## blocked on Dev A (W3-A5): the real component replaces this stub name for
## name; `Rope` already satisfies the same three members.
## Sync: none — a test double, never spawned in a live scene.

const DEFAULT_PROMPT: String = "Interact"

var prompt_text: String = DEFAULT_PROMPT
var hold_seconds: float = 0.0
## How many times interact() was called, so a test can assert a single use.
var interactions: int = 0


func interact(_player: Player) -> void:
	interactions += 1
