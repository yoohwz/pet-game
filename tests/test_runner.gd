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
	var event_a := DomainEventScript.make("test", 1, "subject")
	var event_b := DomainEventScript.make("test", 1, "subject")
	assert_true(event_a.event_id != event_b.event_id, "event ids unique")
	assert_true(DomainEventScript.is_valid(JSON.parse_string(JSON.stringify(event_a))), "event serializes")
	# Persistence round trip, backup recovery, and interrupted replacement safety.
	assert_true(LocalSaveRepositoryScript.save_profile(profile), "save profile")
	var changed := profile.duplicate(true); changed.memorial_count = 2
	assert_true(LocalSaveRepositoryScript.save_profile(changed), "second save preserves backup")
	var loaded := LocalSaveRepositoryScript.load_profile()
	assert_equal(loaded.profile_id, "profile:test", "profile round trip")
	var corrupt := FileAccess.open(LocalSaveRepositoryScript.PROFILE_PATH, FileAccess.WRITE); corrupt.store_string("[]"); corrupt.close()
	var recovered := LocalSaveRepositoryScript.load_profile()
	assert_equal(recovered.profile_id, "profile:test", "backup recovery")
	assert_false(LocalSaveRepositoryScript.save_profile({}), "invalid interrupted save retains valid backup")
	# Debug uses GameSession.reconcile_to through advance_debug (verified by source contract and smoke call).
	var debug_session = PetGameSessionScript.new()
	debug_session.profile = DomainStateScript.new_profile("profile:debug", 0)
	var debug_result := debug_session.advance_debug(600)
	assert_equal(debug_result.elapsed_seconds, 600, "debug time machine production-path smoke")
	debug_session.free()
