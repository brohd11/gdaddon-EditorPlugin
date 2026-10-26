extends SceneTree


const SUITES = [
	preload("res://addons/gdaddon/export_ignore/test/startup_check_test.gd"),
	preload("res://addons/gdaddon/export_ignore/test/install_test.gd"),
	preload("res://addons/gdaddon/export_ignore/test/job_test.gd"),
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures = 0
	for suite in SUITES:
		var result:Dictionary = await suite.run_tests()
		failures += result.result
		print("\n".join(result.output))
	quit(0 if failures == 0 else 1)
