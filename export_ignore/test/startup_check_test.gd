extends RefCounted

const Check = preload("res://addons/gdaddon/src/check.gd")


static func run_tests() -> Dictionary:
	var output:Array = []
	var failures = 0
	var now = 1_800_000_000
	var directory = "res://.godot/gdaddon_check_test_%d" % OS.get_process_id()
	var stamp = directory.path_join("last_check")
	DirAccess.remove_absolute(stamp)
	failures += _expect(output, Check.is_due(stamp, now), "Missing stamp allows a check")
	failures += _expect(output, Check.begin_attempt(stamp, now), "First attempt creates its directory and stamp")
	failures += _expect(output, FileAccess.get_file_as_string(stamp) == str(now), "Stamp persists Unix seconds")
	failures += _expect(output, not Check.is_due(stamp, now), "Same-time launch skips the check")
	failures += _expect(output, not Check.is_due(stamp, now + 86_399), "Check skips just before 24 hours")
	failures += _expect(output, Check.is_due(stamp, now + 86_400), "Check is due at exactly 24 hours")
	failures += _expect(output, Check.is_due(stamp, now + 86_401), "Check is due after 24 hours")
	failures += _expect(output, not Check.begin_attempt(stamp, now + 10), "Recent attempt prevents another attempt")
	failures += _expect(output, FileAccess.get_file_as_string(stamp) == str(now), "Skipped attempts do not renew the stamp")
	for value in ["", "invalid", "1.5", "0", "-10", str(now + 1)]:
		_write(stamp, value)
		failures += _expect(output, Check.is_due(stamp, now), "Invalid or future stamp allows a check: %s" % value)
	_write(stamp, str(now - 86_400))
	failures += _expect(output, Check.begin_attempt(stamp, now), "Expired stamp is renewed before a failed command")
	var failed = Check.parse_status([], 1)
	failures += _expect(output, failed.has("error") and not Check.is_due(stamp, now + 1), "Failed command consumes the daily attempt")
	failures += _expect(output, FileAccess.get_file_as_string(stamp) == str(now), "Failed attempt keeps the renewed timestamp")
	# A file in place of the cache directory makes persistence impossible.
	failures += _expect(output, Check.begin_attempt(stamp.path_join("blocked"), now), "Stamp write failure still allows the attempt")
	DirAccess.remove_absolute(stamp)
	DirAccess.remove_absolute(directory)
	failures += _expect(output, Check.is_due(stamp, now), "Deleting the stamp allows another check")

	var cases:Array = [
		[[], ""],
		[[{}], ""],
		[[{"update": "current", "missing_deps": []}], ""],
		[[{"missing_deps": null}], ""],
		[[{"update": "available"}], "gdaddon - Update available."],
		[[{"missing_deps": ["dependency"]}], "gdaddon - Dependency missing."],
		[[{"update": "available", "missing_deps": ["dependency"]}], "gdaddon - Update available and dependencies missing."],
		[[{"update": "available"}, {"missing_deps": ["dependency"]}], "gdaddon - Update available and dependencies missing."],
		[[{"missing_deps": ["dependency"]}, {"update": "available"}], "gdaddon - Update available and dependencies missing."],
	]
	for case in cases:
		var result = Check.parse_status([JSON.stringify(case[0])], 0)
		failures += _expect(output, result.get("message") == case[1], "Aggregated notification for %s" % JSON.stringify(case[0]))
	for raw in ["", "not json", "null", "{}", "[1]", '[{"missing_deps": "invalid"}]']:
		failures += _expect(output, Check.parse_status([raw], 0).has("error"), "Reject malformed status: %s" % raw)
	failures += _expect(output, Check.parse_status([], 0).has("error"), "Empty process output is diagnosed")
	failures += _expect(output, Check.parse_status(["[]"], 7).has("error"), "Nonzero exit is diagnosed even with valid JSON")
	failures += _test_details(output)
	output.append("gdaddon startup check: %d failures" % failures)
	return {"result": failures, "output": output}


static func _test_details(output:Array) -> int:
	var failures = 0
	var entries = [
		{"name": "script_dock", "update": "available", "latest_tag": "v0.4.0", "missing_deps": [
			{"repo_id": "github.com/me/absent", "tag": "v1.0.0", "state": "missing"},
			{"repo_id": "github.com/me/uninstalled", "state": "not_installed"},
		]},
		{"name": "script_tabs", "update": "available", "latest_tag": "v0.5.0", "missing_deps": [
			{"repo_id": "github.com/me/old", "tag": "v2.0.0", "local_tag": "v1.0.0", "state": "outdated"},
		]},
		{"name": "healthy", "update": "current", "missing_deps": []},
		{"name": "locked", "update": "locked", "missing_deps": null},
	]
	var result = Check.parse_status([JSON.stringify(entries)], 0)
	var expected = [
		"gdaddon - script_dock: update available (v0.4.0)",
		"gdaddon - script_dock: dependency github.com/me/absent missing from manifest (requires v1.0.0)",
		"gdaddon - script_dock: dependency github.com/me/uninstalled not installed",
		"gdaddon - script_tabs: update available (v0.5.0)",
		"gdaddon - script_tabs: dependency github.com/me/old outdated (recorded v1.0.0, requires v2.0.0)",
	]
	failures += _expect(output, result.get("details") == expected, "Details list affected plugins, new versions, and all dependency states in source order")
	failures += _expect(output, result.get("message") == "gdaddon - Update available and dependencies missing.", "Details keep the existing minimal summary")
	entries = [
		{"update": "available", "latest_tag": null},
		{"display_name": "Display Name", "update": "available", "latest_tag": ""},
		{"path": "addons/legacy", "missing_deps": [
			{"url": "https://github.com/me/legacy", "tag": "v1.0.0"},
			"legacy dependency",
			{"repo_id": "github.com/me/old", "state": "outdated"},
			null,
		]},
	]
	result = Check.parse_status([JSON.stringify(entries)], 0)
	expected = [
		"gdaddon - unknown addon: update available (version unknown)",
		"gdaddon - Display Name: update available (version unknown)",
		"gdaddon - addons/legacy: dependency https://github.com/me/legacy missing (requires v1.0.0)",
		"gdaddon - addons/legacy: dependency legacy dependency missing",
		"gdaddon - addons/legacy: dependency github.com/me/old outdated (recorded version unknown)",
		"gdaddon - addons/legacy: dependency unknown dependency missing",
	]
	failures += _expect(output, result.get("details") == expected, "Legacy entries and absent names, identities, or versions have readable fallbacks")
	for healthy in [[], [{"name": "healthy", "update": "current", "missing_deps": []}]]:
		result = Check.parse_status([JSON.stringify(healthy)], 0)
		failures += _expect(output, result.get("message") == "" and result.get("details") == [], "Healthy results have no notification or detail lines")
	return failures


static func _write(path:String, text:String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


static func _expect(output:Array, condition:bool, label:String) -> int:
	if condition:
		return 0
	output.append("FAIL " + label)
	return 1
