extends RefCounted

const Check = preload("res://addons/gdaddon/src/check.gd")


static func run_tests() -> Dictionary:
	var tree = Engine.get_main_loop() as SceneTree
	var output:Array = []
	var failures = 0
	var job = Check.start()
	failures += _expect(output, not job._verbose, "Default entry keeps minimal output")
	job.cancel()
	Check.check_verbose()
	job = Check.Job._active.back()
	failures += _expect(output, job._verbose, "Verbose entry schedules a retained job with detailed output")
	job.cancel()
	job = Check.Job.new()
	job.start(tree, _work, func(): return true)
	failures += _expect(output, job._timer.time_left > 9.0 and job._thread == null, "Scheduling returns before the 10-second delay and worker")
	job.cancel()
	failures += _expect(output, job._timer == null and job._tree == null and not Check.Job._active.has(job), "Cancelling during the delay releases scheduled work")
	job.cancel()

	job = Check.Job.new()
	job.start(tree, _work, func(): return false)
	job._timer.time_left = 0.001
	await _finish(job)
	failures += _expect(output, job._tree == null and job._thread == null, "Daily gate skips the worker and releases the job")
	job.cancel()

	job = Check.Job.new()
	job.start(tree, _work, func(): return true)
	job._timer.time_left = 0.001
	var deadline = Time.get_ticks_msec() + 3_000
	while job._thread == null and job._tree != null and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var thread = job._thread
	job.cancel()
	failures += _expect(output, thread != null and not thread.is_started() and job._tree == null and not Check.Job._active.has(job), "Cancelling an active job joins its worker and releases callbacks")

	job = Check.Job.new()
	job.start(tree, _work, func(): return true)
	job._timer.time_left = 0.001
	var reference = weakref(job)
	job = null
	failures += _expect(output, reference.get_ref() != null, "Scheduled work survives the caller releasing its reference")
	deadline = Time.get_ticks_msec() + 3_000
	while reference.get_ref() != null and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	await tree.process_frame
	failures += _expect(output, reference.get_ref() == null, "Completed background work releases its retained job")
	if reference.get_ref() != null:
		reference.get_ref().cancel()
	output.append("gdaddon job: %d failures" % failures)
	return {"result": failures, "output": output}


static func _work() -> Dictionary:
	OS.delay_msec(50)
	return {"message": ""}


static func _finish(job:Check.Job) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var deadline = Time.get_ticks_msec() + 3_000
	while job._tree != null and Time.get_ticks_msec() < deadline:
		await tree.process_frame


static func _expect(output:Array, condition:bool, label:String) -> int:
	if condition:
		return 0
	output.append("FAIL " + label)
	return 1
