extends RefCounted

const Plugin = preload("res://addons/gdaddon/plugin.gd")
const Check = preload("res://addons/gdaddon/src/check.gd")


static func run_tests() -> Dictionary:
	var output:Array = []
	var failures = 0
	var bundled:GDScript = Check
	var directory = "res://.godot/gdaddon_install_test_%d" % OS.get_process_id()
	var folder = directory.path_join("with spaces $literal")
	var path = folder.path_join("check.gd")
	failures += _expect(output, Plugin._install_to(path) == OK, "Install creates directories and copies the checker")
	failures += _expect(output, FileAccess.get_file_as_string(path) == bundled.source_code, "Installed source is complete")
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	failures += _expect(output, script.reload() == OK and script.has_method("check") and script.has_method("check_verbose"), "Installed source compiles with both entries and no resource path")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("outdated checker")
	file.close()
	failures += _expect(output, Plugin._install_to(path) == OK, "Repeated installation refreshes the checker")
	failures += _expect(output, FileAccess.get_file_as_string(path) == bundled.source_code, "Refresh restores bundled source")
	failures += _expect(output, Plugin._install_to(path.path_join("blocked.gd")) != OK, "File blocking the install directory reports failure")
	failures += _expect(output, Plugin._install_to(folder) != OK, "Unwritable file destination reports failure")
	var absolute = ProjectSettings.globalize_path(path)
	var command = Plugin._startup_command(absolute)
	failures += _expect(output, command.begins_with('"') and command.ends_with('" call check') and command.contains("\\$literal"), "Startup command quotes spaces and escapes variable expansion")
	failures += _expect(output, Plugin._startup_command('C:\\Users\\Test "User"\\check.gd') == '"C:\\\\Users\\\\Test \\"User\\"\\\\check.gd" call check', "Windows paths and quotes are escaped")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(directory)
	output.append("gdaddon install: %d failures" % failures)
	return {"result": failures, "output": output}


static func _expect(output:Array, condition:bool, label:String) -> int:
	if condition:
		return 0
	output.append("FAIL " + label)
	return 1
