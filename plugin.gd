@tool
extends EditorPlugin

const STAMP_PATH = "res://.godot/addons/gdaddon/last_check"

var _timer:Timer
var _thread:Thread


func _enter_tree() -> void:
	set_process(false)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_start_check)
	add_child(_timer)
	_timer.start(10.0)


func _exit_tree() -> void:
	set_process(false)
	_timer.free()
	_timer = null
	# OS.execute must finish before its worker can be released.
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _start_check() -> void:
	if not Check.begin_attempt(STAMP_PATH, int(Time.get_unix_time_from_system())):
		return
	_thread = Thread.new()
	var error = _thread.start(Check.run)
	if error != OK:
		print("gdaddon - Could not start status check: ", error_string(error))
		_thread = null
		return
	set_process(true)


func _process(_delta:float) -> void:
	if _thread == null:
		set_process(false)
		return
	if _thread.is_alive():
		return
	var result:Dictionary = _thread.wait_to_finish()
	_thread = null
	set_process(false)
	if result.has("error"):
		print(result.error)
	elif result.message != "":
		EditorInterface.get_editor_toaster().push_toast(result.message, EditorToaster.SEVERITY_INFO)
		print(result.message)


class Check:
	const INTERVAL_SECONDS = 24 * 60 * 60

	static func is_due(stamp_path:String, now:int) -> bool:
		if not FileAccess.file_exists(stamp_path):
			return true
		var file = FileAccess.open(stamp_path, FileAccess.READ)
		if file == null:
			return true
		var text = file.get_as_text().strip_edges()
		if not text.is_valid_int():
			return true
		var last_check = text.to_int()
		return last_check <= 0 or last_check > now or now - last_check >= INTERVAL_SECONDS


	static func begin_attempt(stamp_path:String, now:int) -> bool:
		if not is_due(stamp_path, now):
			return false
		# Stamp before discovery so failures also consume the daily attempt.
		var error = DirAccess.make_dir_recursive_absolute(stamp_path.get_base_dir())
		if error == OK:
			var file = FileAccess.open(stamp_path, FileAccess.WRITE)
			if file != null:
				file.store_string(str(now))
				file.flush()
				error = file.get_error()
			else:
				error = FileAccess.get_open_error()
		if error != OK:
			print("gdaddon - Could not save check timestamp: ", error_string(error))
		return true


	static func run() -> Dictionary:
		var executable = get_executable()
		if executable == "":
			return {"error": "gdaddon - Could not find the gdaddon binary on PATH or in ~/.gdaddon/bin"}
		var output:Array = []
		var status = OS.execute(executable, ["list", "--json", "--updates"], output)
		return parse_status(output, status)


	static func get_executable() -> String:
		var output:Array = []
		if OS.execute("gdaddon", ["--version"], output) == 0:
			return "gdaddon"
		var windows = OS.get_name() == "Windows"
		var home_dir = OS.get_environment("USERPROFILE" if windows else "HOME")
		if home_dir == "":
			return ""
		var executable = home_dir.path_join(".gdaddon/bin").path_join("gdaddon.exe" if windows else "gdaddon")
		output.clear()
		if OS.execute(executable, ["--version"], output) == 0:
			return executable
		return ""


	static func parse_status(output:Array, status:int) -> Dictionary:
		if status != 0:
			return {"error": "gdaddon - Could not get addon status - Exit Code: %d" % status}
		var json = JSON.new()
		if output.is_empty() or json.parse(str(output[0])) != OK or not json.data is Array:
			return {"error": "gdaddon - Invalid addon status JSON."}
		var has_update = false
		var missing_dependencies = false
		for entry in json.data:
			if not entry is Dictionary:
				return {"error": "gdaddon - Invalid addon status entry."}
			var dependencies:Variant = entry.get("missing_deps", [])
			if dependencies != null and not dependencies is Array:
				return {"error": "gdaddon - Invalid missing dependencies in addon status."}
			has_update = has_update or entry.get("update") == "available"
			missing_dependencies = missing_dependencies or (dependencies != null and not dependencies.is_empty())
		if has_update and missing_dependencies:
			return {"message": "gdaddon - Update available and dependencies missing."}
		if missing_dependencies:
			return {"message": "gdaddon - Dependency missing."}
		if has_update:
			return {"message": "gdaddon - Update available."}
		return {"message": ""}
