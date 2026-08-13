extends SceneTree

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const DomainEventScript = preload("res://domain/simulation/domain_event.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const PetGameSessionScript = preload("res://application/game_session/game_session.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func assert_true(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL: " + label)

func assert_false(value: bool, label: String) -> void: assert_true(not value, label)
func assert_equal(actual, expected, label: String) -> void: assert_true(actual == expected, "%s (got %s expected %s)" % [label, actual, expected])
func assert_approx(actual: float, expected: float, label: String, tolerance := 0.0001) -> void: assert_true(absf(actual - expected) <= tolerance, "%s (got %s expected %s)" % [label, actual, expected])

func _run() -> void:
	_reset_save_fixture()
	var profile := DomainStateScript.new_profile("profile:test", 1000)
	assert_true(DomainStateScript.validate_profile(profile), "new profile validates")
	assert_equal(profile.profile_id, "profile:test", "profile id stable")
	assert_equal(profile.schema_version, 1, "schema version is one")
	var egg := DomainStateScript.new_egg("egg:test", 1000, 2000)
	assert_false(egg.has("born_at"), "egg has no born_at")
	var pet := DomainStateScript.new_pet("pet:test", "Mochi", 1200, 7)
	assert_true(DomainStateScript.validate_pet(pet), "new pet validates")
	assert_equal(pet.identity.pet_id, "pet:test", "pet id immutable data exists")
	var negative := SimulationKernelScript.simulate(profile, 1000, 900)
	assert_equal(negative.elapsed_seconds, 0, "negative elapsed is zero")
	assert_equal(negative.new_state.simulation.clock_anomaly_count, 1, "negative elapsed records anomaly")
	var deterministic_a := SimulationKernelScript.simulate(profile, 1000, 4600)
	var deterministic_b := SimulationKernelScript.simulate(profile, 1000, 4600)
	assert_equal(deterministic_a.new_state.foundation_elapsed_seconds, deterministic_b.new_state.foundation_elapsed_seconds, "simulation deterministic")
	var chunked := profile.duplicate(true)
	for i in range(24): chunked = SimulationKernelScript.simulate(chunked, 1000 + i * 3600, 1000 + (i + 1) * 3600).new_state
	var whole: Dictionary = SimulationKernelScript.simulate(profile, 1000, 1000 + 24 * 3600).new_state
	assert_approx(chunked.foundation_elapsed_seconds, whole.foundation_elapsed_seconds, "24 x 1h equals 1 x 24h")
	var event_a := DomainEventScript.make("event:explicit:a", "test", 1, "subject")
	var event_b := DomainEventScript.make("event:explicit:b", "test", 1, "subject")
	assert_true(event_a.event_id != event_b.event_id, "distinct explicit event ids remain distinct")
	var round_trip_event: Dictionary = JSON.parse_string(JSON.stringify(event_a))
	assert_equal(round_trip_event.event_id, "event:explicit:a", "explicit event id survives serialization")
	assert_true(DomainEventScript.is_valid(round_trip_event), "event serializes")
	var same_simulation_a: Dictionary = SimulationKernelScript.simulate(profile, 1000, 4600).generated_events[0]
	var same_simulation_b: Dictionary = SimulationKernelScript.simulate(profile, 1000, 4600).generated_events[0]
	var different_simulation: Dictionary = SimulationKernelScript.simulate(profile, 1000, 4601).generated_events[0]
	assert_equal(same_simulation_a.event_id, same_simulation_b.event_id, "same simulation coordinates retain deterministic event id")
	assert_true(same_simulation_a.event_id != different_simulation.event_id, "different simulation coordinates have distinct event ids")
	# Persistence normal round trip and backup rotation.
	var profile_a := profile.duplicate(true); profile_a.memorial_count = 1
	var profile_b := profile.duplicate(true); profile_b.memorial_count = 2
	assert_true(LocalSaveRepositoryScript.save_profile(profile_a), "save valid profile A")
	assert_equal(LocalSaveRepositoryScript.load_profile().memorial_count, 1, "normal profile round trip")
	assert_true(LocalSaveRepositoryScript.save_profile(profile_b), "save valid profile B")
	assert_equal(LocalSaveRepositoryScript.read_valid_profile(LocalSaveRepositoryScript.PROFILE_PATH).memorial_count, 2, "canonical rotates to B")
	assert_equal(LocalSaveRepositoryScript.read_valid_profile(LocalSaveRepositoryScript.BACKUP_PATH).memorial_count, 1, "backup rotates to valid A")
	# Corrupt primary + valid backup recovery; subsequent save must not poison backup.
	_write_raw(LocalSaveRepositoryScript.PROFILE_PATH, "[]")
	assert_equal(LocalSaveRepositoryScript.load_profile().memorial_count, 1, "valid backup recovers corrupt primary")
	assert_true(LocalSaveRepositoryScript.save_profile(profile_b), "save B with corrupt canonical preserves backup")
	assert_equal(LocalSaveRepositoryScript.read_valid_profile(LocalSaveRepositoryScript.BACKUP_PATH).memorial_count, 1, "corrupt canonical never poisons valid backup")
	# Replacement-stage failure happens after valid temp and leaves a valid recovery copy.
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	var profile_c := profile.duplicate(true); profile_c.memorial_count = 3
	assert_false(LocalSaveRepositoryScript.save_profile(profile_c), "injected canonical replacement failure")
	assert_false(LocalSaveRepositoryScript.load_profile().is_empty(), "replacement failure leaves recoverable valid profile")
	# Debug uses GameSession.reconcile_to through advance_debug (verified by source contract and smoke call).
	var debug_session = PetGameSessionScript.new()
	debug_session.profile = DomainStateScript.new_profile("profile:debug", 0)
	var debug_result := debug_session.advance_debug(600)
	assert_equal(debug_result.elapsed_seconds, 600, "debug time machine production-path smoke")
	debug_session.free()

func _write_raw(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _reset_save_fixture() -> void:
	for path in [LocalSaveRepositoryScript.PROFILE_PATH, LocalSaveRepositoryScript.BACKUP_PATH, LocalSaveRepositoryScript.TEMP_PATH, LocalSaveRepositoryScript.BACKUP_TEMP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
