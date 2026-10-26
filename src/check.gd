@tool
extends RefCounted

const STAMP_PATH = "res://.godot/addons/gdaddon/last_check"
const INTERVAL_SECONDS = 24 * 60 * 60


static func check() -> void:
	start()

static func check_verbose() -> void:
	start(true)


static func start(verbose:bool = false, time:=10.0) -> Job:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		print("gdaddon - A running SceneTree is required to check addon status.")
		return null
	var project_root = ProjectSettings.globalize_path("res://")
	var stamp_path = ProjectSettings.globalize_path(STAMP_PATH)
	var job = Job.new()
	var begin = func():
		return begin_attempt(stamp_path, int(Time.get_unix_time_from_system()))
	job.start(tree, run.bind(project_root), begin, verbose, time)
	return job


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


static func run(project_root:String) -> Dictionary:
	var executable = get_executable()
	if executable == "":
		return {"error": "gdaddon - Could not find the gdaddon binary on PATH or in ~/.gdaddon/bin"}
	var output:Array = []
	var status = OS.execute(executable, ["list", project_root, "--json", "--updates"], output)
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
	var details:Array[String] = []
	for entry in json.data:
		if not entry is Dictionary:
			return {"error": "gdaddon - Invalid addon status entry."}
		var dependencies:Variant = entry.get("missing_deps", [])
		if dependencies != null and not dependencies is Array:
			return {"error": "gdaddon - Invalid missing dependencies in addon status."}
		has_update = has_update or entry.get("update") == "available"
		missing_dependencies = missing_dependencies or (dependencies != null and not dependencies.is_empty())
		var name = _label(entry, ["name", "display_name", "path"], "unknown addon")
		if entry.get("update") == "available":
			details.append("gdaddon - %s: update available (%s)" % [name, _label(entry, ["latest_tag"], "version unknown")])
		if dependencies != null:
			for dependency in dependencies:
				details.append(_dependency_detail(name, dependency))
	var message = ""
	if has_update and missing_dependencies:
		message = "gdaddon - Update available and dependencies missing."
	elif missing_dependencies:
		message = "gdaddon - Dependency missing."
	elif has_update:
		message = "gdaddon - Update available."
	return {"message": message, "details": details}


static func _dependency_detail(name:String, dependency:Variant) -> String:
	if not dependency is Dictionary:
		var identity = str(dependency) if dependency != null and str(dependency) != "" else "unknown dependency"
		return "gdaddon - %s: dependency %s missing" % [name, identity]
	var identity = _label(dependency, ["repo_id", "url"], "unknown dependency")
	var state = _label(dependency, ["state"], "")
	var description = "missing"
	match state:
		"missing": description = "missing from manifest"
		"not_installed": description = "not installed"
		"outdated": description = "outdated"
	var versions:Array[String] = []
	if state == "outdated":
		versions.append("recorded %s" % _label(dependency, ["local_tag"], "version unknown"))
	var required = _label(dependency, ["tag"], "")
	if required != "":
		versions.append("requires %s" % required)
	var suffix = " (%s)" % ", ".join(versions) if not versions.is_empty() else ""
	return "gdaddon - %s: dependency %s %s%s" % [name, identity, description, suffix]


static func _label(data:Dictionary, keys:Array, fallback:String) -> String:
	for key in keys:
		var value:Variant = data.get(key)
		if value is String and not value.strip_edges().is_empty():
			return value.strip_edges()
	return fallback


class Job extends RefCounted:
	# GDSh releases the script target when the command returns; retain scheduled jobs.
	static var _active:Array[RefCounted] = []

	var _tree:SceneTree
	var _timer:SceneTreeTimer
	var _thread:Thread
	var _task:Callable
	var _begin_attempt:Callable
	var _verbose:bool = false


	func start(tree:SceneTree, task:Callable, begin:Callable, verbose:bool = false, time:=10.0) -> void:
		_tree = tree
		_task = task
		_begin_attempt = begin
		_verbose = verbose
		_active.append(self)
		_tree.root.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
		if time < 0.15:
			_begin()
		else:
			_timer = _tree.create_timer(time)
			_timer.timeout.connect(_begin)


	func cancel() -> void:
		if _timer != null:
			if _timer.timeout.is_connected(_begin):
				_timer.timeout.disconnect(_begin)
			_timer = null
		if _tree != null:
			if _tree.process_frame.is_connected(_poll):
				_tree.process_frame.disconnect(_poll)
			if _tree.root.tree_exiting.is_connected(cancel):
				_tree.root.tree_exiting.disconnect(cancel)
			_tree = null
		# OS.execute must finish before its worker can be released.
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		_task = Callable()
		_begin_attempt = Callable()
		_active.erase(self)


	func _begin() -> void:
		_timer = null
		if not _begin_attempt.call():
			cancel()
			return
		_thread = Thread.new()
		var error = _thread.start(_task)
		if error != OK:
			print("gdaddon - Could not start status check: ", error_string(error))
			_thread = null
			cancel()
			return
		_tree.process_frame.connect(_poll)


	func _poll() -> void:
		if _thread == null or _thread.is_alive():
			return
		var result:Dictionary = _thread.wait_to_finish()
		_thread = null
		cancel()
		if result.has("error"):
			print(result.error)
		elif result.message != "":
			if Engine.is_editor_hint():
				EditorInterface.get_editor_toaster().push_toast(result.message, EditorToaster.SEVERITY_INFO)
			if _verbose:
				for line in result.get("details", []):
					print(line)
			else:
				print(result.message)
