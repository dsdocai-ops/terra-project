extends GutTest


func test_prompt_text_names_the_key_and_the_action() -> void:
	assert_eq(InteractPrompt.prompt_for("F", "Open"), "[F] Open")


func test_key_name_reads_the_interact_binding() -> void:
	assert_eq(InteractPrompt.key_name(), "F")
