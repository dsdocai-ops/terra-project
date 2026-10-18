class_name LaunchArgs
extends RefCounted
## Parses the user launch args after `--` (SPEC-foundation):
##   --host            host a game and skip the menu
##   --join=<ip[:port]> join a host and skip the menu
##   --seed=<int>      force the run seed
## Owned by foundation. Sync: none.

enum Mode { MENU, HOST, JOIN }

var mode: Mode = Mode.MENU
var host: bool = false
var join_ip: String = ""
var port: int = NetworkManager.DEFAULT_PORT
var run_seed: int = 0
## Human-readable problems with the arguments; main.gd logs them.
var errors: Array[String] = []


static func parse(args: PackedStringArray) -> LaunchArgs:
	var opts := LaunchArgs.new()
	for arg: String in args:
		if arg == "--host":
			opts.host = true
		elif arg.begins_with("--join="):
			opts._parse_join(arg.trim_prefix("--join="))
		elif arg.begins_with("--seed="):
			opts._parse_seed(arg.trim_prefix("--seed="))
	if opts.host and not opts.join_ip.is_empty():
		opts.errors.append("--host and --join given together; hosting")
		opts.join_ip = ""
	if opts.host:
		opts.mode = Mode.HOST
	elif not opts.join_ip.is_empty():
		opts.mode = Mode.JOIN
	else:
		opts.mode = Mode.MENU
	return opts


func _parse_join(value: String) -> void:
	if value.is_empty():
		errors.append("--join needs an address, e.g. --join=127.0.0.1")
		return
	var parts := value.rsplit(":", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		join_ip = parts[0]
		port = int(parts[1])
	else:
		join_ip = value


func _parse_seed(value: String) -> void:
	if value.is_valid_int():
		run_seed = int(value)
	else:
		errors.append("--seed must be an integer, got '%s'" % value)
