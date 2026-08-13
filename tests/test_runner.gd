extends SceneTree

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const SaveMigratorScript = preload("res://infrastructure/persistence/save_migrator.gd")
const PetGameSessionScript = preload("res://application/game_session/game_session.gd")
const FoundationScreenScript = preload("res://presentation/ui/foundation_screen.gd")

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
	eq(none.schema_version, 3, "new profile uses schema v3")
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
	# Active time preserves fractional monotonic remainder and ignores tick cadence.
	var session = PetGameSessionScript.new(); session.balance = BALANCE; session.profile = fixture(); session.reanchor(10.0); session.last_autosave_monotonic = 10.0
	session.advance_active_to(11.6); session.advance_active_to(12.7)
	eq(session.profile.simulation.last_simulated_at, 1002, "fractional ticks retain two whole seconds")
	session.advance_active_to(13.1)
	eq(session.profile.simulation.last_simulated_at, 1003, "fractional remainder reaches third second")
	var cadence_a = PetGameSessionScript.new(); cadence_a.balance = BALANCE; cadence_a.profile = fixture(); cadence_a.reanchor(10.0)
	for tick in [11.2, 12.4, 13.6, 14.8]: cadence_a.advance_active_to(tick)
	var cadence_b = PetGameSessionScript.new(); cadence_b.balance = BALANCE; cadence_b.profile = fixture(); cadence_b.reanchor(10.0); cadence_b.advance_active_to(14.8)
	for key in ["hunger", "hydration", "energy", "hygiene"]: approx(cadence_a.profile.active_pet.vitals[key], cadence_b.profile.active_pet.vitals[key], "irregular active cadence independence " + key)
	# Foreground ticks mutate only in memory; autosave/pause are explicit persistence boundaries.
	session.persistence_write_count = 0
	for tick in [14.0, 20.0, 39.9]: session.process_at(tick)
	eq(session.persistence_write_count, 0, "active ticks before cadence do not persist")
	session.process_at(40.0)
	eq(session.persistence_write_count, 1, "autosave persists once at thirty seconds")
	session.advance_active_to(45.0); session.pause_at(45.0)
	eq(session.persistence_write_count, 2, "pause persists latest active state")
	# Positive and negative resume both persist and re-anchor.
	var resume = PetGameSessionScript.new(); resume.balance = BALANCE; resume.profile = fixture(); resume.reanchor(10.0); resume.persistence_write_count = 0
	resume.resume_at(1000 + 28800, 50.0)
	approx(resume.profile.active_pet.vitals.energy, 50.0, "positive resume applies eight hour decay")
	eq(resume.persistence_write_count, 1, "positive resume persists")
	resume.advance_active_to(3650.0)
	approx(resume.profile.active_pet.vitals.energy, 43.75, "resume re-anchor continues one hour")
	var before: float = resume.profile.active_pet.vitals.hunger
	resume.resume_at(500, 4000.0)
	eq(resume.profile.active_pet.vitals.hunger, before, "negative wall gap does not reverse needs")
	eq(resume.profile.simulation.clock_anomaly_count, 1, "negative wall gap anomaly")
	# Debug persists and resets the active anchor so the next tick cannot create a false anomaly.
	var debug_session = PetGameSessionScript.new(); debug_session.balance = BALANCE; debug_session.profile = fixture(); debug_session.reanchor(10.0); debug_session.persistence_write_count = 0
	debug_session.advance_debug(28800, 10.0)
	eq(debug_session.persistence_write_count, 1, "debug advancement persists")
	debug_session.advance_active_to(3610.0)
	eq(debug_session.profile.simulation.clock_anomaly_count, 0, "debug re-anchor avoids false anomaly")
	approx(debug_session.profile.active_pet.vitals.energy, 43.75, "debug plus active hour equals nine direct hours")
	# Testable startup path loads, reconciles, persists and anchors an offline active pet.
	_reset(); ok(LocalSaveRepositoryScript.save_profile(fixture()), "persist startup fixture")
	var startup = PetGameSessionScript.new(); startup.balance = BALANCE; startup.initialize_session(1000 + 28800, 70.0)
	approx(startup.profile.active_pet.vitals.energy, 50.0, "startup reconciliation applies eight hours")
	eq(startup.session_anchor_simulated_at, 1000 + 28800, "startup establishes simulation anchor")
	startup.advance_active_to(3670.0)
	approx(startup.profile.active_pet.vitals.energy, 43.75, "startup anchor continues one hour")
	# Phase 2: migration, exactly-once initial egg, offline incubation and safe hatching.
	var v2_none := {"schema_version": 2, "profile_id": "v2:none", "created_at": 1, "active_subject": "NONE", "active_pet": null, "memorial_count": 0, "simulation": {"last_simulated_at": 1, "clock_anomaly_count": 0, "simulation_version": 2, "balance_version": 1}, "recent_events": []}
	var migrated_v3 := SaveMigratorScript.migrate(v2_none)
	ok(DomainStateScript.validate_profile(migrated_v3) and migrated_v3.active_egg == null and not migrated_v3.initial_egg_issued, "v2 NONE migrates to v3 without egg")
	var v2_pet := fixture(); v2_pet.schema_version = 2; v2_pet.simulation.simulation_version = 2; v2_pet.erase("active_egg"); v2_pet.erase("initial_egg_issued")
	var migrated_pet := SaveMigratorScript.migrate(v2_pet)
	ok(DomainStateScript.validate_profile(migrated_pet) and migrated_pet.active_subject == "PET" and migrated_pet.active_egg == null and migrated_pet.initial_egg_issued, "v2 pet migrates without concurrent egg")
	# Phase 2 root and EggState validation matrix.
	var valid_egg := DomainStateScript.new_egg("egg:valid", 1, 2)
	ok(DomainStateScript.validate_egg(valid_egg), "valid incubating egg")
	valid_egg.state = "READY"; ok(DomainStateScript.validate_egg(valid_egg), "valid ready egg")
	valid_egg.state = "HATCHING"; valid_egg.reserved_pet_id = "pet:reserved"; valid_egg.reserved_pet_seed = 7; valid_egg.hatching_started_at = 2
	ok(DomainStateScript.validate_egg(valid_egg), "valid hatching requires complete reservation")
	var invalid_egg: Dictionary = valid_egg.duplicate(true); invalid_egg.reserved_pet_id = null; ok(not DomainStateScript.validate_egg(invalid_egg), "hatching without pet id fails")
	invalid_egg = valid_egg.duplicate(true); invalid_egg.reserved_pet_seed = null; ok(not DomainStateScript.validate_egg(invalid_egg), "hatching without seed fails")
	invalid_egg = valid_egg.duplicate(true); invalid_egg.hatching_started_at = null; ok(not DomainStateScript.validate_egg(invalid_egg), "hatching without start fails")
	invalid_egg = DomainStateScript.new_egg("egg:ready", 1, 2); invalid_egg.state = "READY"; invalid_egg.reserved_pet_id = "pet:x"; ok(not DomainStateScript.validate_egg(invalid_egg), "ready reservation id fails")
	invalid_egg = DomainStateScript.new_egg("egg:ready", 1, 2); invalid_egg.state = "READY"; invalid_egg.reserved_pet_seed = 1; ok(not DomainStateScript.validate_egg(invalid_egg), "ready reservation seed fails")
	invalid_egg = DomainStateScript.new_egg("egg:inc", 1, 2); invalid_egg.hatching_started_at = 1; ok(not DomainStateScript.validate_egg(invalid_egg), "incubating start fails")
	invalid_egg = DomainStateScript.new_egg("egg:born", 1, 2); invalid_egg.born_at = 2; ok(not DomainStateScript.validate_egg(invalid_egg), "egg born_at fails")
	var invalid_root := DomainStateScript.new_profile("root", 1); invalid_root.active_subject = "EGG"; ok(not DomainStateScript.validate_profile(invalid_root), "EGG without egg fails")
	invalid_root = DomainStateScript.new_profile("root", 1); invalid_root.active_subject = "PET"; ok(not DomainStateScript.validate_profile(invalid_root), "PET without pet fails")
	invalid_root = DomainStateScript.new_profile("root", 1); invalid_root.active_subject = "NONE"; invalid_root.active_egg = DomainStateScript.new_egg("egg", 1, 2); ok(not DomainStateScript.validate_profile(invalid_root), "NONE with egg fails")
	invalid_root = fixture(); invalid_root.active_egg = DomainStateScript.new_egg("egg", 1, 2); ok(not DomainStateScript.validate_profile(invalid_root), "both egg and pet fail")
	_reset()
	var egg_session = PetGameSessionScript.new(); egg_session.balance = BALANCE; egg_session.lifecycle = {"lifecycle_version": 1, "initial_incubation_seconds": 14400, "newborn_protection_seconds": 43200}; egg_session.initialize_session(1000, 10.0)
	eq(egg_session.profile.active_subject, "EGG", "first initialization issues egg")
	eq(egg_session.profile.active_egg.received_at, 1000, "egg received at initialization")
	eq(egg_session.profile.active_egg.hatch_ready_at, 15400, "egg incubation is four hours")
	ok(egg_session.profile.initial_egg_issued and egg_session.profile.active_pet == null, "initial egg is sole active subject")
	var same_egg: String = egg_session.profile.active_egg.egg_id
	var restart = PetGameSessionScript.new(); restart.balance = BALANCE; restart.lifecycle = egg_session.lifecycle; restart.initialize_session(1000, 20.0)
	eq(restart.profile.active_egg.egg_id, same_egg, "restart does not issue second egg")
	# Actual startup reconciliation from persisted INCUBATING to offline READY.
	_reset(); var offline_profile := DomainStateScript.new_profile("profile:offline", 1000); offline_profile.initial_egg_issued = true; offline_profile.active_subject = "EGG"; offline_profile.active_egg = DomainStateScript.new_egg("egg:offline", 1000, 15400)
	ok(LocalSaveRepositoryScript.save_profile(offline_profile), "persist incubating startup fixture")
	var offline_start = PetGameSessionScript.new(); offline_start.balance = BALANCE; offline_start.lifecycle = egg_session.lifecycle; offline_start.initialize_session(1000 + 28800, 20.0)
	eq(offline_start.profile.active_egg.state, "READY", "startup offline incubation reaches ready")
	eq(offline_start.profile.active_pet, null, "startup ready creates no pet")
	eq(LocalSaveRepositoryScript.load_profile().active_egg.state, "READY", "startup reconciled ready persists")
	var before_ready: Dictionary = SimulationKernelScript.simulate(restart.profile, 1000, 1000 + 14399, BALANCE, egg_session.lifecycle).new_state
	eq(before_ready.active_egg.state, "INCUBATING", "egg remains incubating before threshold")
	var ready_once := SimulationKernelScript.simulate(restart.profile, 1000, 15400, BALANCE, egg_session.lifecycle)
	eq(ready_once.new_state.active_egg.state, "READY", "egg becomes ready at threshold")
	eq(ready_once.new_state.active_pet, null, "ready egg never auto creates pet")
	var two_hours: Dictionary = SimulationKernelScript.simulate(restart.profile, 1000, 8200, BALANCE, egg_session.lifecycle).new_state
	var ready_chunk := SimulationKernelScript.simulate(two_hours, 8200, 15400, BALANCE, egg_session.lifecycle)
	eq(ready_once.generated_events[0].event_id, ready_chunk.generated_events[0].event_id, "egg ready event identity is chunk independent")
	# Explicit egg touch persists but cannot alter incubation or create a pet.
	ok(egg_session.touch_egg(1100), "touch incubating egg")
	eq(egg_session.profile.active_egg.interaction_summary.touch_count, 1, "egg touch increments summary")
	eq(egg_session.profile.active_egg.hatch_ready_at, 15400, "touch does not alter incubation")
	# Offline debug advance reaches READY without unattended birth.
	egg_session.advance_debug(14400, 10.0)
	eq(egg_session.profile.active_egg.state, "READY", "offline/debug incubation reaches READY")
	eq(egg_session.profile.active_pet, null, "READY remains egg only")
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	ok(not egg_session.begin_hatching(15400, 10.0) and egg_session.profile.active_egg.state == "READY", "begin failure leaves effective READY state")
	ok(egg_session.begin_hatching(15400, 10.0), "begin hatching persists reservation")
	var reserved: String = egg_session.profile.active_egg.reserved_pet_id
	ok(not reserved.is_empty() and egg_session.profile.active_pet == null, "hatching reserves one identity without pet")
	var recovery = PetGameSessionScript.new(); recovery.balance = BALANCE; recovery.lifecycle = egg_session.lifecycle; recovery.initialize_session(15400, 30.0)
	eq(recovery.profile.active_egg.state, "HATCHING", "restart preserves HATCHING")
	eq(recovery.profile.active_egg.reserved_pet_id, reserved, "restart retains reserved identity")
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	ok(not recovery.complete_hatching(16000, 30.0), "completion failure returns false")
	eq(recovery.profile.active_egg.state, "HATCHING", "completion failure leaves in-memory hatching")
	eq(LocalSaveRepositoryScript.load_profile().active_egg.state, "HATCHING", "completion failure leaves persisted hatching")
	ok(recovery.complete_hatching(16000, 30.0), "completion succeeds on retry")
	eq(recovery.profile.active_pet.identity.pet_id, reserved, "successful pet uses reserved identity")
	eq(recovery.profile.active_pet.identity.born_at, 16000, "born_at is successful completion time")
	eq(recovery.profile.active_pet.life.newborn_protection_until, 59200, "newborn protection metadata is twelve hours")
	eq(recovery.profile.active_pet.vitals.hunger, 100.0, "ready waiting causes no retroactive hunger")
	var post_birth: Dictionary = SimulationKernelScript.simulate(recovery.profile, 16000, 19600, BALANCE, egg_session.lifecycle).new_state
	approx(post_birth.active_pet.vitals.energy, 93.75, "passive needs begin only after birth")
	# Backward completion clamps born_at to the simulation timeline and commits anomaly only on success.
	var backward = PetGameSessionScript.new(); backward.balance = BALANCE; backward.lifecycle = egg_session.lifecycle; backward.profile = DomainStateScript.new_profile("profile:back", 20000); backward.profile.initial_egg_issued = true; backward.profile.active_subject = "EGG"; backward.profile.active_egg = DomainStateScript.new_egg("egg:back", 1000, 2); backward.profile.active_egg.state = "HATCHING"; backward.profile.active_egg.reserved_pet_id = "pet:back"; backward.profile.active_egg.reserved_pet_seed = 3; backward.profile.active_egg.hatching_started_at = 3
	ok(backward.complete_hatching(19000, 40.0), "backward-clock completion succeeds")
	eq(backward.profile.active_pet.identity.born_at, 20000, "backward clock clamps born_at")
	eq(backward.profile.simulation.clock_anomaly_count, 1, "backward completion increments anomaly")
	eq(backward.profile.simulation.last_simulated_at, 20000, "birth retains simulation timeline")
	for value in [egg_session, restart, recovery, offline_start, backward]: value.free()
	# Phase 2 presentation: controls rebuild only on lifecycle signature transitions.
	var ui_profile := DomainStateScript.new_profile("profile:ui", 1000)
	ui_profile.initial_egg_issued = true; ui_profile.active_subject = "EGG"; ui_profile.active_egg = DomainStateScript.new_egg("egg:ui", 1000, 15400)
	var ui_session = PetGameSessionScript.new()
	ui_session.balance = BALANCE
	ui_session.lifecycle = {"lifecycle_version": 1, "initial_incubation_seconds": 14400, "newborn_protection_seconds": 43200}
	ui_session.profile = ui_profile
	var screen = FoundationScreenScript.new(); screen.session_override = ui_session; screen._ready()
	eq(screen.rendered_lifecycle_signature, "EGG:INCUBATING", "UI renders incubating lifecycle signature")
	ok(screen.has_lifecycle_button("Touch Egg") and not screen.has_lifecycle_button("Hatch Egg"), "incubating UI has touch only")
	var stable_touch := screen.lifecycle_button("Touch Egg")
	var initial_rebuilds: int = screen.lifecycle_rebuild_count
	for i in range(4): screen.refresh_lifecycle_panel()
	eq(screen.lifecycle_rebuild_count, initial_rebuilds, "stable incubating UI does not rebuild each refresh")
	eq(screen.lifecycle_button("Touch Egg"), stable_touch, "stable touch button identity survives refreshes")
	ui_session.profile.active_egg.state = "READY"; screen.refresh_lifecycle_panel()
	eq(screen.rendered_lifecycle_signature, "EGG:READY", "same-session ready signature changes")
	ok(screen.has_lifecycle_button("Hatch Egg"), "same-session ready exposes hatch button")
	var stable_hatch := screen.lifecycle_button("Hatch Egg"); var ready_rebuilds: int = screen.lifecycle_rebuild_count
	for i in range(3): screen.refresh_lifecycle_panel()
	eq(screen.lifecycle_rebuild_count, ready_rebuilds, "stable ready UI does not rebuild")
	eq(screen.lifecycle_button("Hatch Egg"), stable_hatch, "stable hatch button identity survives refreshes")
	ui_session.profile.active_egg.state = "HATCHING"; ui_session.profile.active_egg.reserved_pet_id = "pet:ui"; ui_session.profile.active_egg.reserved_pet_seed = 1; ui_session.profile.active_egg.hatching_started_at = 15400; screen.refresh_lifecycle_panel()
	ok(not screen.has_lifecycle_button("Hatch Egg") and screen.has_lifecycle_button("Continue Hatching"), "hatching replaces hatch with continue")
	var stable_continue := screen.lifecycle_button("Continue Hatching"); var hatching_rebuilds: int = screen.lifecycle_rebuild_count; screen.refresh_lifecycle_panel()
	eq(screen.lifecycle_rebuild_count, hatching_rebuilds, "stable hatching UI does not rebuild")
	eq(screen.lifecycle_button("Continue Hatching"), stable_continue, "stable continue identity survives refresh")
	ui_session.profile.active_subject = "PET"; ui_session.profile.active_egg = null; ui_session.profile.active_pet = DomainStateScript.new_pet("pet:ui", "UI", 16000, 1); screen.refresh_lifecycle_panel()
	ok(screen.rendered_lifecycle_signature.begins_with("PET:") and not screen.has_lifecycle_button("Continue Hatching"), "pet transition removes egg controls")
	screen.free(); ui_session.free()
	for value in [session, cadence_a, cadence_b, resume, debug_session, startup]: value.free()

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(content); file.close()
func _reset() -> void:
	for path in [LocalSaveRepositoryScript.PROFILE_PATH, LocalSaveRepositoryScript.BACKUP_PATH, LocalSaveRepositoryScript.TEMP_PATH, LocalSaveRepositoryScript.BACKUP_TEMP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
