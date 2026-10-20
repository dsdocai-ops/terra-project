class_name LaunchArgs
extends RefCounted
## Parses the user launch args after `--` (SPEC-foundation):
##   --host            host a game and skip the menu
##   --join=<ip[:port]> join a host and skip the menu
##   --port=<int>      the port a host binds, and the port a --join without its
##                     own port connects to (1..65535). An explicit port inside
##                     --join wins. Lets a second smoke run on a free port
##                     (tools/smoke_two.sh)
##   --seed=<int>      force the run seed
##   --debug-tools     force the debug console on even in a build where
##                     OS.is_debug_build() is false (SPEC-debug-tools)
##   --smoke[=<sec>]   headless two-instance smoke: the local player walks
##                     right, positions are logged every second, quit after
##                     <sec> seconds (default DEFAULT_SMOKE_SECONDS).
##                     See tools/smoke_two.sh
##   --smoke3[=<sec>]  headless two-instance smoke step 3: the client asks the
##                     host to spawn and kill a stub enemy through
##                     request_debug, the host resolves one hit, and
##                     enemy_killed registers exactly once. See smoke_two.sh
##   --smoke-floor[=<sec>]
##                     headless two-instance floor-sync smoke: the host starts a
##                     run (which broadcasts floor_ready for floor 1) once a
##                     client has joined, and both peers log the seed, floor,
##                     biome and the layout_hash each generated locally from it.
##                     See smoke_two.sh
## Owned by foundation. Sync: none.

enum Mode { MENU, HOST, JOIN }

const DEFAULT_SMOKE_SECONDS := 8.0

var mode: Mode = Mode.MENU
var host: bool = false
var join_ip: String = ""
var port: int = NetworkManager.DEFAULT_PORT
## The --port value, or 0 when it was not given. Resolved into `port` after the
## whole argv is read, so an explicit --join=ip:port wins over --port whichever
## order the two appear in.
var port_arg: int = 0
## True once --join=ip:port has carried its own port; --port then defers to it.
var _join_port_given: bool = false
var run_seed: int = 0
## True when --debug-tools was passed: force the debug console on.
var debug_tools: bool = false
## 0 means not a smoke run.
var smoke_seconds: float = 0.0
## 0 means not a smoke-step-3 run.
var smoke3_seconds: float = 0.0
## 0 means not a floor-sync smoke run.
var smoke_floor_seconds: float = 0.0
## Human-readable problems with the arguments; main.gd logs them.
var errors: Array[String] = []


static func parse(args: PackedStringArray) -> LaunchArgs:
	var opts := LaunchArgs.new()
	for arg: String in args:
		if arg == "--host":
			opts.host = true
		elif arg == "--smoke":
			opts.smoke_seconds = DEFAULT_SMOKE_SECONDS
		elif arg.begins_with("--smoke="):
			var value := arg.trim_prefix("--smoke=")
			if value.is_valid_float() and float(value) > 0.0:
				opts.smoke_seconds = float(value)
			else:
				opts.errors.append("--smoke needs a positive number of seconds, got '%s'" % value)
		elif arg == "--smoke3":
			opts.smoke3_seconds = DEFAULT_SMOKE_SECONDS
		elif arg.begins_with("--smoke3="):
			var value3 := arg.trim_prefix("--smoke3=")
			if value3.is_valid_float() and float(value3) > 0.0:
				opts.smoke3_seconds = float(value3)
			else:
				opts.errors.append("--smoke3 needs a positive number of seconds, got '%s'" % value3)
		elif arg == "--smoke-floor":
			opts.smoke_floor_seconds = DEFAULT_SMOKE_SECONDS
		elif arg.begins_with("--smoke-floor="):
			var value_floor := arg.trim_prefix("--smoke-floor=")
			if value_floor.is_valid_float() and float(value_floor) > 0.0:
				opts.smoke_floor_seconds = float(value_floor)
			else:
				opts.errors.append("--smoke-floor needs a positive number of seconds, got '%s'" % value_floor)
		elif arg.begins_with("--join="):
			opts._parse_join(arg.trim_prefix("--join="))
		elif arg.begins_with("--port="):
			opts._parse_port(arg.trim_prefix("--port="))
		elif arg.begins_with("--seed="):
			opts._parse_seed(arg.trim_prefix("--seed="))
		elif arg == "--debug-tools":
			opts.debug_tools = true
	if opts.port_arg > 0 and not opts._join_port_given:
		opts.port = opts.port_arg
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
		_join_port_given = true
	else:
		join_ip = value


func _parse_port(value: String) -> void:
	if value.is_valid_int() and int(value) >= 1 and int(value) <= 65535:
		port_arg = int(value)
	else:
		errors.append("--port must be an integer between 1 and 65535, got '%s'" % value)


func _parse_seed(value: String) -> void:
	if value.is_valid_int():
		run_seed = int(value)
	else:
		errors.append("--seed must be an integer, got '%s'" % value)
