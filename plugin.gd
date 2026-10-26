@tool
class_name GDAddonPlugin
extends EditorPlugin

const Check = preload("res://addons/gdaddon/src/check.gd")

var _job:Check.Job

func _enter_tree() -> void:
	check_install(false)
	_job = Check.start()


func _exit_tree() -> void:
	if _job != null:
		_job.cancel()
		_job = null


## Copies the checker and version metadata to ~/.gdaddon for Editor Console.
static func install() -> String:
	var directory = _install_dir()
	if directory == "":
		push_error("gdaddon - Could not determine the home directory.")
		return ""
	var path = directory.path_join("check.gd")
	var error = _install_to(path)
	if error != OK:
		push_error("gdaddon - Could not install checker and plugin.cfg in %s: %s" % [directory, error_string(error)])
		return ""
	return "Add one of these to ~/.gdrc file to run on start in every project.\n" + _startup_command(path)


static func check_install(show_version:bool = true) -> void:
	var directory = _install_dir()
	if directory == "":
		if show_version:
			print("gdaddon - Could not determine the home directory.")
		return
	for line in _version_report(directory.path_join("plugin.cfg"), _config_path(), show_version):
		print(line)


static func run_check() -> void:
	reset_check()
	Check.start(true, 0)


## Delete the check stamp
static func reset_check() -> void:
	if FileAccess.file_exists(Check.STAMP_PATH):
		DirAccess.remove_absolute(Check.STAMP_PATH)


static func _install_dir() -> String:
	var home_dir = OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	return home_dir.path_join(".gdaddon/editor_plugin") if home_dir != "" else ""


static func _config_path() -> String:
	var script:GDScript = Check
	return script.resource_path.get_base_dir().get_base_dir().path_join("plugin.cfg")


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
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	var metadata = FileAccess.open(_config_path(), FileAccess.READ)
	if metadata == null:
		return FileAccess.get_open_error()
	var bytes = metadata.get_buffer(metadata.get_length())
	if metadata.get_error() != OK:
		return metadata.get_error()
	file = FileAccess.open(path.get_base_dir().path_join("plugin.cfg"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	return file.get_error()


static func _version_report(installed_path:String, project_path:String, show_version:bool) -> Array[String]:
	var lines:Array[String] = []
	if not FileAccess.file_exists(installed_path):
		if show_version:
			lines.append("gdaddon - No installed checker version found (plugin.cfg missing).")
		return lines
	var installed = ConfigFile.new()
	if installed.load(installed_path) != OK:
		if show_version:
			lines.append("gdaddon - Could not read installed checker version.")
		return lines
	var installed_version:Variant = installed.get_value("plugin", "version", "")
	if not installed_version is String or installed_version.strip_edges().is_empty():
		if show_version:
			lines.append("gdaddon - Could not read installed checker version.")
		return lines
	installed_version = installed_version.strip_edges()
	if show_version:
		lines.append("gdaddon - Installed editor checker: %s" % installed_version)
	var project = ConfigFile.new()
	if project.load(project_path) != OK:
		return lines
	var project_version:Variant = project.get_value("plugin", "version", "")
	if project_version is String and _is_newer(project_version, installed_version):
		lines.append("gdaddon - Project plugin %s is newer than installed checker %s. Run GDAddonPlugin call install to refresh it." % [project_version, installed_version])
	return lines


static func _is_newer(project_version:String, installed_version:String) -> bool:
	var project = _version_parts(project_version)
	var installed = _version_parts(installed_version)
	if project.is_empty() or installed.is_empty():
		return false
	for i in range(maxi(project.size(), installed.size())):
		var current = project[i] if i < project.size() else 0
		var previous = installed[i] if i < installed.size() else 0
		if current != previous:
			return current > previous
	return false


static func _version_parts(version:String) -> Array[int]:
	var parts:Array[int] = []
	for part in version.strip_edges().trim_prefix("v").split("."):
		if not part.is_valid_int() or part.begins_with("+") or part.begins_with("-"):
			return []
		parts.append(part.to_int())
	return parts


static func _startup_command(path:String) -> String:
	var quoted = path.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
	return '"%s" call check\n"%s" call check_verbose' % [quoted, quoted]
