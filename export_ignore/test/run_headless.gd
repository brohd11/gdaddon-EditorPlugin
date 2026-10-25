extends SceneTree


func _init() -> void:
	var result:Dictionary = preload("res://addons/gdaddon/export_ignore/test/startup_check_test.gd").run_tests()
	print("\n".join(result.output))
	quit(0 if result.result == 0 else 1)
