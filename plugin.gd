@tool
class_name GDAddonPlugin
extends EditorPlugin

const Check = preload("res://addons/gdaddon/src/check.gd")

var _job:Check.Job

func _enter_tree() -> void:
	_job = Check.start()


func _exit_tree() -> void:
	if _job != null:
		_job.cancel()
		_job = null


## Copies the threaded checker to ~/.gdaddon for use with Editor Console
static func install() -> String:
	var home_dir = OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	if home_dir == "":
		push_error("gdaddon - Could not determine the home directory.")
		return ""
	var path = home_dir.path_join(".gdaddon/editor_plugin/check.gd")
	var error = _install_to(path)
	if error != OK:
		push_error("gdaddon - Could not install checker at %s: %s" % [path, error_string(error)])
		return ""
	return "Add one of these to ~/.gdrc file to run on start in every project.\n" + _startup_command(path)


static func run_check() -> void:
	reset_check()
	Check.start(true, 0)


## Delete the check stamp
static func reset_check() -> void:
	if FileAccess.file_exists(Check.STAMP_PATH):
		DirAccess.remove_absolute(Check.STAMP_PATH)

static func _install_to(path:String) -> Error:
	var script:GDScript = Check
	var source = script.source_code
	if source.is_empty():
		return ERR_INVALID_DATA
	var error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(source)
	file.flush()
	return file.get_error()


static func _startup_command(path:String) -> String:
	var quoted = path.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
	return '"%s" call check\n"%s" call check_verbose' % [quoted, quoted]
