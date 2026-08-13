extends SceneTree

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const SaveMigratorScript = preload("res://infrastructure/persistence/save_migrator.gd")
const PetGameSessionScript = preload("res://application/game_session/game_session.gd")

const BALANCE := {"balance_version": 1, "hunger_full_decay_seconds": 172800, "hydration_full_decay_seconds": 86400, "energy_full_decay_seconds": 57600, "hygiene_full_decay_seconds": 259200}
var passed := 0
var failed := 0

func _init() -> void:
	_run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func ok(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL: " + label)
func eq(actual, expected, label: String) -> void: ok(actual == expected, "%s got=%s expected=%s" % [label, actual, expected])
func approx(actual: float, expected: float, label: String) -> void: ok(absf(actual - expected) < 0.001, "%s got=%s expected=%s" % [label, actual, expected])

func fixture(at := 1000, id := "pet:test") -> Dictionary:
	var p := DomainStateScript.new_profile("profile:test", at)
	p.active_subject = "PET"
	p.active_pet = DomainStateScript.new_pet(id, "Test", at, 4)
	return p

func _run() -> void:
	_reset()
	var none := DomainStateScript.new_profile("profile:none", 1000)
	eq(none.schema_version, 2, "new profile uses schema v2")
	ok(DomainStateScript.validate_profile(none), "normal v2 profile valid")
	eq(SimulationKernelScript.simulate(none, 1000, 4600, BALANCE).new_state.active_pet, null, "no pet remains absent")
	var p := fixture()
	ok(DomainStateScript.validate_profile(p), "active pet profile valid")
	var one: Dictionary = SimulationKernelScript.simulate(p, 1000, 4600, BALANCE).new_state
	approx(one.active_pet.vitals.hunger, 97.9166667, "1h hunger")
	approx(one.active_pet.vitals.hydration, 95.8333333, "1h hydration")
	approx(one.active_pet.vitals.energy, 93.75, "1h energy")
	approx(one.active_pet.vitals.hygiene, 98.6111111, "1h hygiene")
	var eight: Dictionary = SimulationKernelScript.simulate(p, 1000, 1000 + 28800, BALANCE).new_state
	approx(eight.active_pet.vitals.hunger, 83.3333333, "8h hunger")
	approx(eight.active_pet.vitals.hydration, 66.6666667, "8h hydration")
	approx(eight.active_pet.vitals.energy, 50.0, "8h energy")
	approx(eight.active_pet.vitals.hygiene, 88.8888889, "8h hygiene")
	var day: Dictionary = SimulationKernelScript.simulate(p, 1000, 1000 + 86400, BALANCE).new_state
	approx(day.active_pet.vitals.hunger, 50.0, "24h hunger")
	eq(day.active_pet.vitals.hydration, 0.0, "24h hydration clamps")
	eq(day.active_pet.vitals.energy, 0.0, "24h energy clamps")
	approx(day.active_pet.vitals.hygiene, 66.6666667, "24h hygiene")
	eq(day.active_pet.vitals.mood, 100.0, "mood unchanged")
	eq(day.active_pet.vitals.health, 100.0, "health unchanged")
	var large: Dictionary = SimulationKernelScript.simulate(p, 1000, 1000 + 365 * 86400, BALANCE).new_state
	for key in ["hunger", "hydration", "energy", "hygiene"]: eq(large.active_pet.vitals[key], 0.0, "large gap clamps " + key)
	var dead := fixture(); dead.active_pet.life.life_state = "DEAD"; dead.active_pet.life.died_at = 1000
	eq(SimulationKernelScript.simulate(dead, 1000, 9000, BALANCE).new_state.active_pet.vitals, dead.active_pet.vitals, "dead pet unchanged")
	var chunk := fixture()
	for i in range(24): chunk = SimulationKernelScript.simulate(chunk, 1000 + 3600 * i, 1000 + 3600 * (i + 1), BALANCE).new_state
	for key in ["hunger", "hydration", "energy", "hygiene"]: approx(chunk.active_pet.vitals[key], day.active_pet.vitals[key], "chunking equivalence " + key)
	var ev_a: Dictionary = SimulationKernelScript.simulate(p, 1000, 4600, BALANCE).generated_events[0]
	var ev_b: Dictionary = SimulationKernelScript.simulate(p, 1000, 4600, BALANCE).generated_events[0]
	var ev_other: Dictionary = SimulationKernelScript.simulate(fixture(1000, "pet:other"), 1000, 4600, BALANCE).generated_events[0]
	eq(ev_a.event_id, ev_b.event_id, "deterministic event id")
	ok(ev_a.event_id != ev_other.event_id and ev_a.subject_id == "pet:test", "pet id event subject")
	var v1 := {"schema_version": 1, "profile_id": "legacy", "created_at": 10, "active_subject": "NONE", "memorial_count": 3, "simulation": {"last_simulated_at": 20, "clock_anomaly_count": 2, "simulation_version": 1}, "recent_events": [], "foundation_elapsed_seconds": 9.0}
	var migrated := SaveMigratorScript.migrate(v1)
	ok(DomainStateScript.validate_profile(migrated), "v1 migrates to valid v2")
	eq(migrated.profile_id, "legacy", "migration preserves profile")
	eq(migrated.memorial_count, 3, "migration preserves memorial count")
	eq(migrated.active_pet, null, "migration invents no pet")
	# v2 pet state round trip and Phase 0 backup/recovery safety.
	ok(LocalSaveRepositoryScript.save_profile(p), "save v2 pet A")
	var b := fixture(); b.active_pet.vitals.hunger = 77.0
	ok(LocalSaveRepositoryScript.save_profile(b), "save v2 pet B")
	eq(LocalSaveRepositoryScript.load_profile().active_pet.vitals.hunger, 77.0, "active pet round trip")
	eq(LocalSaveRepositoryScript.read_valid_profile(LocalSaveRepositoryScript.BACKUP_PATH).active_pet.vitals.hunger, 100.0, "backup keeps valid A")
	_write(LocalSaveRepositoryScript.PROFILE_PATH, "[]")
	eq(LocalSaveRepositoryScript.load_profile().active_pet.vitals.hunger, 100.0, "backup recovers corrupt v2 primary")
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	ok(not LocalSaveRepositoryScript.save_profile(b), "actual replacement failure injected")
	ok(not LocalSaveRepositoryScript.load_profile().is_empty(), "replacement failure retains valid copy")
	# Explicit application paths: offline, monotonic session, anomaly and debug share reconciliation.
	var session = PetGameSessionScript.new(); session.balance = BALANCE; session.profile = fixture(); session.reanchor(10.0)
	eq(session.advance_active_to(3610.0).new_state.active_pet.vitals.energy, 93.75, "monotonic active session equals direct")
	var before: float = session.profile.active_pet.vitals.hunger
	session.resume_at(500, 4000.0)
	eq(session.profile.active_pet.vitals.hunger, before, "negative wall gap does not reverse needs")
	eq(session.profile.simulation.clock_anomaly_count, 1, "negative wall gap anomaly")
	var debug := session.advance_debug(28800)
	approx(debug.new_state.active_pet.vitals.energy, 43.75, "debug uses production simulation path")
	session.free()

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(content); file.close()
func _reset() -> void:
	for path in [LocalSaveRepositoryScript.PROFILE_PATH, LocalSaveRepositoryScript.BACKUP_PATH, LocalSaveRepositoryScript.TEMP_PATH, LocalSaveRepositoryScript.BACKUP_TEMP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
