extends SceneTree
## Gives every hand-written .tscn / .tres under scenes/, assets/, data/ a UID
## header if it has none, through the same ResourceSaver.set_uid path the
## editor uses. A headless editor scan does not do this on its own, and a
## scene without a UID gets rewritten in someone else's PR on first save.
## Owned by foundation. Sync: none.
##
##   godot --headless --path . -s tools/set_missing_uids.gd
## Run --import afterwards so the UID cache picks the new ids up.

const ROOTS: Array[String] = ["res://scenes", "res://assets", "res://data"]

var _fixed: int = 0


func _init() -> void:
	for root: String in ROOTS:
		_walk(root)
	print("%d file(s) given a UID" % _fixed)
	quit()


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk(full)
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			_ensure_uid(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _ensure_uid(path: String) -> void:
	if _has_uid_header(path):
		return
	var uid := ResourceUID.create_id()
	var err := ResourceSaver.set_uid(path, uid)
	if err != OK:
		push_error("could not set uid on %s: %s" % [path, error_string(err)])
		return
	_fixed += 1
	print("%s -> %s" % [path, ResourceUID.id_to_text(uid)])


func _has_uid_header(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return true
	var first := file.get_line()
	file.close()
	return first.contains("uid=\"uid://")
