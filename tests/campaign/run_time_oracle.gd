extends SceneTree
## Long-form oracle evidence for package 2. Driven by run_time_oracle.py.
##   -- --produce <dir> <days_per_segment> <segments>   aggregate run, one checkpoint per segment
##   -- --verify <dir> <index>                          detailed oracle replays one segment
## A segment's oracle starts from the aggregate checkpoint and must reproduce the next
## checkpoint exactly, so segments chain and can run in parallel processes.
const Harness = preload("res://tests/campaign/time_harness.gd")
const PRESET := "time_sustainable_6crew"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var ok := false
	if args.size() == 4 and args[0] == "--produce": ok = produce(args[1], int(args[2]), int(args[3]))
	elif args.size() == 3 and args[0] == "--verify": ok = verify(args[1], int(args[2]))
	else: print("TIME_ORACLE_USAGE see the header of this script")
	quit(0 if ok else 1)

func write(path: String, sim: RefCounted) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(sim.export_save(), "", true, true))
	file.close()

func produce(dir: String, days: int, segments: int) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var sim = Harness.new_sim(PRESET, false, "auto")
	write(dir.path_join("checkpoint_0.json"), sim)
	var started := Time.get_ticks_usec()
	var calls := 0
	for index in segments:
		var target := (index + 1) * days * Harness.DAY
		var stops: Array = Harness.fast_forward_through(sim, "segment_%d" % index, target)
		write(dir.path_join("checkpoint_%d.json" % (index + 1)), sim)
		print("TIME_ORACLE_SEGMENT index=%d target_s=%d stops=%s" % [index, target, JSON.stringify(stops)])
	var stats: Dictionary = sim.get_time_stats()
	print("TIME_ORACLE_PRODUCED simulated_s=%d wall_ms=%.1f detailed_ticks=%d aggregate_intervals=%d aggregate_ticks=%d rejections=%d advance_calls=%d max_call_detailed_ticks=%d max_call_account_ticks=%d max_call_usec=%d" % [
		int(sim.get_snapshot().clock.tick_index), float(Time.get_ticks_usec() - started) / 1000.0, stats.detailed_ticks,
		stats.aggregate_intervals, stats.aggregate_ticks, stats.aggregate_rejections, stats.advance_calls,
		stats.max_call_detailed_ticks, stats.max_call_account_ticks, stats.max_call_usec])
	print("TIME_ORACLE_FALLBACKS ", JSON.stringify(stats.fallback_reasons))
	return true

func verify(dir: String, index: int) -> bool:
	var start: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("checkpoint_%d.json" % index)))
	var expected: String = FileAccess.get_file_as_string(dir.path_join("checkpoint_%d.json" % (index + 1)))
	var expected_record: Dictionary = JSON.parse_string(expected)
	var sim = Harness.new_sim(PRESET, false, "detailed")
	var loaded: Dictionary = sim.import_save(start)
	if not loaded.ok:
		print("TIME_ORACLE_FAIL index=%d load: %s" % [index, loaded.reason])
		return false
	# The segment target is recovered from the aggregate run's own journal.
	var target := 0
	var command_count := 0
	for id in expected_record.journal:
		if id.begins_with("segment_%d_" % index):
			target = int(expected_record.journal[id].normalized.payload.target_elapsed_s)
			command_count += 1
	var started := Time.get_ticks_usec()
	var first_tick := int(sim.get_snapshot().clock.tick_index)
	var stops: Array = Harness.fast_forward_through(sim, "segment_%d" % index, target)
	var actual := JSON.stringify(sim.export_save(), "", true, true)
	var stats: Dictionary = sim.get_time_stats()
	var same: bool = actual == expected and stats.aggregate_intervals == 0 and stops.size() == command_count
	print("TIME_ORACLE_%s index=%d from_s=%d to_s=%d detailed_ticks=%d wall_ms=%.1f stops=%s" % ["MATCH" if same else "FAIL",
		index, first_tick, int(sim.get_snapshot().clock.tick_index), stats.detailed_ticks,
		float(Time.get_ticks_usec() - started) / 1000.0, JSON.stringify(stops)])
	return same
