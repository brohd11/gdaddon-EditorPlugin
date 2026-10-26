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
	var metadata = folder.path_join("plugin.cfg")
	var bundled_metadata = FileAccess.get_file_as_string(Plugin._config_path())
	failures += _expect(output, Plugin._install_to(path) == OK, "Install creates directories and copies the checker")
	failures += _expect(output, FileAccess.get_file_as_string(path) == bundled.source_code, "Installed source is complete")
	failures += _expect(output, FileAccess.get_file_as_string(metadata) == bundled_metadata, "Installed plugin.cfg matches the bundled metadata verbatim")
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	failures += _expect(output, script.reload() == OK and script.has_method("check") and script.has_method("check_verbose"), "Installed source compiles with both entries and no resource path")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("outdated checker")
	file.close()
	_write_version(metadata, "999.0.0")
	failures += _expect(output, Plugin._install_to(path) == OK, "Repeated installation refreshes the checker")
	failures += _expect(output, FileAccess.get_file_as_string(path) == bundled.source_code, "Refresh restores bundled source")
	failures += _expect(output, FileAccess.get_file_as_string(metadata) == bundled_metadata, "Refresh overwrites metadata regardless of installed version")
	failures += _expect(output, Plugin._install_to(path.path_join("blocked.gd")) != OK, "File blocking the install directory reports failure")
	failures += _expect(output, Plugin._install_to(folder) != OK, "Unwritable file destination reports failure")
	var absolute = ProjectSettings.globalize_path(path)
	var command = Plugin._startup_command(absolute)
	var commands = command.split("\n")
	failures += _expect(output, commands.size() == 2 and commands[0].begins_with('"') and commands[0].ends_with('" call check') and commands[1].ends_with('" call check_verbose') and command.contains("\\$literal"), "Both startup commands quote spaces and escape variable expansion")
	var windows = Plugin._startup_command('C:\\Users\\Test "User"\\check.gd').split("\n")
	failures += _expect(output, windows[0] == '"C:\\\\Users\\\\Test \\"User\\"\\\\check.gd" call check' and windows[1] == windows[0] + "_verbose", "Both Windows commands escape paths and quotes")
	DirAccess.remove_absolute(metadata)
	DirAccess.make_dir_absolute(metadata)
	failures += _expect(output, Plugin._install_to(path) != OK, "Metadata write failure reports installation failure")
	failures += _expect(output, FileAccess.get_file_as_string(path) == bundled.source_code, "Metadata is written after the checker")
	DirAccess.remove_absolute(metadata)
	failures += _test_versions(directory, output)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(directory)
	output.append("gdaddon install: %d failures" % failures)
	return {"result": failures, "output": output}


static func _test_versions(directory:String, output:Array) -> int:
	var failures = 0
	var installed = directory.path_join("installed.cfg")
	var project = directory.path_join("project.cfg")
	_write_version(project, "1.0.0")
	failures += _expect(output, Plugin._version_report(installed, project, false).is_empty(), "Missing installation is quiet at startup")
	var lines = Plugin._version_report(installed, project, true)
	failures += _expect(output, lines.size() == 1 and lines[0].contains("plugin.cfg missing"), "Manual check explains missing metadata")
	var cases = [
		["0.3.0", "0.3.0", false],
		["0.4.0", "0.3.0", true],
		["0.3.1", "0.3.0", true],
		["1.0.0", "0.99.99", true],
		["0.10.0", "0.9.0", true],
		["0.3.0", "0.4.0", false],
		["v0.4.0", "v0.3.0", true],
		["1.2", "1.2.0", false],
		["1.2.0", "1.2", false],
		["nightly", "0.3.0", false],
		["1.0.0", "nightly", false],
		["1.0.0-dev", "0.3.0", false],
		["-1.0.0", "0.3.0", false],
		["1..0", "0.3.0", false],
	]
	for case in cases:
		_write_version(project, case[0])
		_write_version(installed, case[1])
		lines = Plugin._version_report(installed, project, false)
		failures += _expect(output, lines.size() == (1 if case[2] else 0), "Startup version comparison: %s vs %s" % [case[0], case[1]])
		if case[2] and not lines.is_empty():
			failures += _expect(output, lines[0].contains(case[0]) and lines[0].contains(case[1]) and lines[0].contains("GDAddonPlugin call install"), "Newer notice shows both versions and the refresh command")
		lines = Plugin._version_report(installed, project, true)
		failures += _expect(output, lines.size() == (2 if case[2] else 1) and lines[0].contains(case[1]), "Manual check always displays the installed version: %s" % case[1])
	var config = ConfigFile.new()
	config.set_value("plugin", "name", "no version")
	config.save(installed)
	failures += _expect(output, Plugin._version_report(installed, project, false).is_empty(), "Absent version is quiet at startup")
	lines = Plugin._version_report(installed, project, true)
	failures += _expect(output, lines.size() == 1 and lines[0].contains("Could not read"), "Manual check diagnoses absent version")
	config.set_value("plugin", "version", 3)
	config.save(installed)
	failures += _expect(output, Plugin._version_report(installed, project, false).is_empty(), "Non-string version is not compared")
	_write_version(installed, "0.3.0")
	DirAccess.remove_absolute(project)
	failures += _expect(output, Plugin._version_report(installed, project, false).is_empty(), "Missing project metadata skips the comparison")
	DirAccess.remove_absolute(installed)
	return failures


static func _write_version(path:String, version:String) -> void:
	var config = ConfigFile.new()
	config.set_value("plugin", "version", version)
	config.save(path)


static func _expect(output:Array, condition:bool, label:String) -> int:
	if condition:
		return 0
	output.append("FAIL " + label)
	return 1
