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
	eq(none.schema_version, 5, "new profile uses schema v5")
	ok(DomainStateScript.validate_profile(none), "normal v5 profile valid")
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
	for key in ["hunger", "hydration", "energy"]: eq(large.active_pet.vitals[key], 0.0, "large gap clamps " + key)
	ok(String(large.active_pet.life.life_state) == "DEAD" and float(large.active_pet.vitals.hygiene) > 0.0, "death freezes biological needs during a large gap")
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
	ok(DomainStateScript.validate_profile(migrated), "v1 migrates to valid v5")
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
	# Phase 3 care, sleep, validation and migration.
	var pet_v3 := fixture(); pet_v3.schema_version = 3; pet_v3.erase("active_egg"); pet_v3.erase("initial_egg_issued"); pet_v3.simulation.simulation_version = 3; pet_v3.active_pet.erase("activity")
	var pet_v4 := SaveMigratorScript.migrate(pet_v3)
	ok(DomainStateScript.validate_profile(pet_v4) and pet_v4.active_pet.activity.state == "AWAKE", "v3 pet migrates awake")
	var invalid_pet: Dictionary = pet_v4.active_pet.duplicate(true); invalid_pet.activity = {"state":"SLEEPING","sleep_started_at":null}; ok(not DomainStateScript.validate_pet(invalid_pet), "sleeping needs timestamp")
	invalid_pet = pet_v4.active_pet.duplicate(true); invalid_pet.vitals.hunger = 101; ok(not DomainStateScript.validate_pet(invalid_pet), "vitals clamp validation")
	var care_session = PetGameSessionScript.new(); care_session.balance = BALANCE; care_session.lifecycle = {"initial_incubation_seconds":14400,"newborn_protection_seconds":43200}; care_session.care = {"feed_hunger_restore":35,"drink_hydration_restore":45,"wash_hygiene_restore":50,"touch_mood_restore":5,"play_mood_restore":20,"play_energy_cost":10,"play_min_energy":10,"sleep_energy_full_recovery_seconds":28800}; care_session.profile = fixture(); care_session.reanchor(10.0)
	care_session.profile.active_pet.vitals = {"hunger":40.0,"hydration":30.0,"energy":50.0,"hygiene":60.0,"mood":70.0,"health":100.0}
	ok(care_session.care_action("feed", 10.0).ok and care_session.profile.active_pet.vitals.hunger == 75.0, "feed restores hunger")
	ok(care_session.care_action("drink", 10.0).ok and care_session.profile.active_pet.vitals.hydration == 75.0, "drink restores hydration")
	ok(care_session.care_action("wash", 10.0).ok and care_session.profile.active_pet.vitals.hygiene == 100.0, "wash clamps hygiene")
	ok(care_session.care_action("touch", 10.0).ok and care_session.profile.active_pet.vitals.mood == 75.0, "touch restores mood")
	ok(care_session.care_action("play", 10.0).ok and care_session.profile.active_pet.vitals.energy == 40.0 and care_session.profile.active_pet.vitals.mood == 95.0, "play changes mood and energy")
	ok(care_session.care_action("sleep", 10.0).ok and care_session.profile.active_pet.activity.state == "SLEEPING", "sleep persists state")
	eq(care_session.care_action("feed", 10.0).reason, "PET_SLEEPING", "sleep blocks care")
	var sleep_result: Dictionary = SimulationKernelScript.simulate(care_session.profile, 1000, 1000 + 28800, BALANCE, care_session.lifecycle, care_session.care).new_state
	eq(sleep_result.active_pet.vitals.energy, 100.0, "sleep restores energy")
	eq(sleep_result.active_pet.vitals.health, 100.0, "sleep has no health consequence")
	ok(care_session.care_action("wake", 10.0).ok and care_session.profile.active_pet.activity.state == "AWAKE", "wake persists")
	# Phase 3 acceptance gaps: event semantics, failures, offline sleep and timeline ordering.
	var care_v2: Dictionary = care_session.care.duplicate(true); care_v2.care_balance_version = 2
	var event_one: Dictionary = SimulationKernelScript.simulate(fixture(), 1000, 4600, BALANCE, care_session.lifecycle, care_session.care).generated_events[-1]
	var event_two: Dictionary = SimulationKernelScript.simulate(fixture(), 1000, 4600, BALANCE, care_session.lifecycle, care_session.care).generated_events[-1]
	var care_v2_profile := fixture(); care_v2_profile.simulation.care_balance_version = 2
	var event_changed: Dictionary = SimulationKernelScript.simulate(care_v2_profile, 1000, 4600, BALANCE, care_session.lifecycle, care_v2).generated_events[-1]
	eq(event_one.event_id, event_two.event_id, "same care version simulation event deterministic")
	ok(event_one.event_id != event_changed.event_id, "care balance version changes event identity")
	# Final evidence: persisted c1 with supplied c2 must use c2 math and identity.
	var mismatch_profile := fixture(); mismatch_profile.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; mismatch_profile.active_pet.vitals.energy = 0.0; mismatch_profile.simulation.care_balance_version = 1
	var mismatch_v1: Dictionary = care_session.care.duplicate(true); mismatch_v1.care_balance_version = 1; mismatch_v1.sleep_energy_full_recovery_seconds = 28800
	var mismatch_v2: Dictionary = care_session.care.duplicate(true); mismatch_v2.care_balance_version = 2; mismatch_v2.sleep_energy_full_recovery_seconds = 14400
	var mismatch_result_v1 := SimulationKernelScript.simulate(mismatch_profile, 1000, 8200, BALANCE, care_session.lifecycle, mismatch_v1)
	var mismatch_result_v2 := SimulationKernelScript.simulate(mismatch_profile, 1000, 8200, BALANCE, care_session.lifecycle, mismatch_v2)
	approx(mismatch_result_v2.new_state.active_pet.vitals.energy, 50.0, "mismatch runtime uses supplied care v2 math")
	ok(mismatch_result_v2.generated_events[-1].event_id.contains(":c2:"), "mismatch event identity encodes supplied care v2")
	ok(mismatch_result_v1.generated_events[-1].event_id != mismatch_result_v2.generated_events[-1].event_id, "mismatch c1 and c2 identities differ")
	eq(mismatch_result_v2.new_state.simulation.care_balance_version, 1, "pure simulation preserves persisted care version")
	var fail_care = PetGameSessionScript.new(); fail_care.balance = BALANCE; fail_care.lifecycle = care_session.lifecycle; fail_care.care = care_session.care; fail_care.profile = fixture(); fail_care.profile.active_pet.vitals.hunger = 40.0; fail_care.reanchor(10.0)
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(fail_care.care_action("feed", 10.0).reason, "PERSIST_FAILED", "care save failure reported")
	eq(fail_care.profile.active_pet.vitals.hunger, 40.0, "failed feed does not commit care effect")
	eq(fail_care.profile.recent_events.size(), 0, "failed feed adds no authoritative event")
	ok(not _has_event(fail_care.profile.recent_events, "pet_fed"), "failed feed has no pet_fed event")
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(fail_care.care_action("sleep", 10.0).reason, "PERSIST_FAILED", "sleep save failure reported")
	eq(fail_care.profile.active_pet.activity.state, "AWAKE", "failed sleep stays awake")
	eq(fail_care.profile.active_pet.activity.sleep_started_at, null, "failed sleep has no start timestamp")
	eq(fail_care.profile.recent_events.size(), 0, "failed sleep adds no authoritative event")
	ok(not _has_event(fail_care.profile.recent_events, "pet_sleep_started"), "failed sleep has no event")
	fail_care.profile.active_pet.vitals.energy = 5.0; var before_mood: float = fail_care.profile.active_pet.vitals.mood; var before_energy: float = fail_care.profile.active_pet.vitals.energy; var before_events: int = fail_care.profile.recent_events.size()
	eq(fail_care.care_action("play", 10.0).reason, "LOW_ENERGY", "low energy play rejected")
	eq(fail_care.profile.active_pet.vitals.energy, before_energy, "low energy play preserves energy")
	eq(fail_care.profile.active_pet.vitals.mood, before_mood, "low energy play preserves mood")
	eq(fail_care.profile.recent_events.size(), before_events, "low energy play emits no event")
	# Offline sleeping startup reconciliation.
	_reset(); var offline_sleep := fixture(); offline_sleep.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; offline_sleep.active_pet.vitals.energy = 25.0; ok(LocalSaveRepositoryScript.save_profile(offline_sleep), "persist sleeping fixture")
	var sleep_startup = PetGameSessionScript.new(); sleep_startup.balance = BALANCE; sleep_startup.lifecycle = care_session.lifecycle; sleep_startup.care = care_session.care; sleep_startup.initialize_session(1000 + 14400, 20.0)
	approx(sleep_startup.profile.active_pet.vitals.energy, 75.0, "offline sleep recovers energy")
	eq(sleep_startup.profile.active_pet.activity.state, "SLEEPING", "offline sleep remains sleeping")
	approx(sleep_startup.profile.active_pet.vitals.hydration, 83.3333333, "offline sleep passive hydration decay")
	approx(LocalSaveRepositoryScript.load_profile().active_pet.vitals.energy, 75.0, "offline sleep reconciliation persists")
	# Interaction timeline sync precedes care application and event uses simulated timestamp.
	var timeline = PetGameSessionScript.new(); timeline.balance = BALANCE; timeline.lifecycle = care_session.lifecycle; timeline.care = care_session.care; timeline.profile = fixture(); timeline.profile.active_pet.vitals.hunger = 50.0; timeline.reanchor(10.0)
	ok(timeline.care_action("feed", 3610.0).ok, "timeline feed succeeds")
	approx(timeline.profile.active_pet.vitals.hunger, 82.9166667, "timeline decays before feed")
	eq(timeline.profile.recent_events[-1].occurred_at, 4600, "care event timestamp uses simulated time")
	eq(timeline.profile.recent_events[-1].subject_id, "pet:test", "care event subject is pet id")
	# Corrective pass 2: all v3 lifecycle migrations and care acceptance evidence.
	var v3_egg := DomainStateScript.new_profile("v3:egg", 1000); v3_egg.schema_version = 3; v3_egg.simulation.simulation_version = 3; v3_egg.erase("initial_egg_issued"); v3_egg.erase("active_egg"); v3_egg.active_subject = "EGG"; v3_egg["active_egg"] = DomainStateScript.new_egg("egg:migrate", 1000, 15400); v3_egg.active_egg.schema_version = 3
	var migrated_inc := SaveMigratorScript.migrate(v3_egg)
	eq(migrated_inc.schema_version, 5, "v3 incubating migrates v5")
	eq(migrated_inc.active_egg.egg_id, "egg:migrate", "v3 incubating preserves egg id")
	eq(migrated_inc.active_egg.interaction_summary, v3_egg.active_egg.interaction_summary, "v3 incubating preserves interaction summary")
	v3_egg.active_egg.state = "READY"; var migrated_ready := SaveMigratorScript.migrate(v3_egg)
	eq(migrated_ready.active_egg.state, "READY", "v3 ready remains ready")
	v3_egg.active_egg.state = "HATCHING"; v3_egg.active_egg.reserved_pet_id = "pet:migrated"; v3_egg.active_egg.reserved_pet_seed = 77; v3_egg.active_egg.hatching_started_at = 15400
	var migrated_hatching := SaveMigratorScript.migrate(v3_egg)
	eq(migrated_hatching.active_egg.reserved_pet_id, "pet:migrated", "v3 hatching preserves reserved id")
	eq(migrated_hatching.active_egg.reserved_pet_seed, 77, "v3 hatching preserves seed")
	var migrated_hatch_session = PetGameSessionScript.new(); migrated_hatch_session.balance = BALANCE; migrated_hatch_session.lifecycle = care_session.lifecycle; migrated_hatch_session.care = care_session.care; migrated_hatch_session.profile = migrated_hatching
	ok(migrated_hatch_session.complete_hatching(16000, 10.0), "migrated hatching completes")
	eq(migrated_hatch_session.profile.active_pet.identity.pet_id, "pet:migrated", "migrated hatching retains identity")
	var valid_awake := fixture(); ok(DomainStateScript.validate_pet(valid_awake.active_pet), "valid awake pet passes")
	var valid_sleep := fixture(); valid_sleep.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; ok(DomainStateScript.validate_pet(valid_sleep.active_pet), "valid sleeping pet passes")
	invalid_pet = fixture().active_pet; invalid_pet.activity = {"state":"AWAKE", "sleep_started_at":1}; ok(not DomainStateScript.validate_pet(invalid_pet), "awake with sleep timestamp fails")
	invalid_pet = fixture().active_pet; invalid_pet.activity = {"state":"DREAMING", "sleep_started_at":null}; ok(not DomainStateScript.validate_pet(invalid_pet), "unknown activity fails")
	invalid_pet = fixture().active_pet; invalid_pet.vitals.erase("hunger"); ok(not DomainStateScript.validate_pet(invalid_pet), "missing vital fails")
	invalid_pet = fixture().active_pet; invalid_pet.vitals.energy = -1; ok(not DomainStateScript.validate_pet(invalid_pet), "negative vital fails")
	var clamp_session = PetGameSessionScript.new(); clamp_session.balance = BALANCE; clamp_session.lifecycle = care_session.lifecycle; clamp_session.care = care_session.care; clamp_session.profile = fixture(); clamp_session.profile.active_pet.vitals.hunger = 90.0; clamp_session.reanchor(10.0)
	ok(clamp_session.care_action("feed", 10.0).ok and clamp_session.profile.active_pet.vitals.hunger == 100.0, "feed clamps hunger at 100")
	var sleep_full := fixture(); sleep_full.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; sleep_full.active_pet.vitals = {"hunger":100.0,"hydration":100.0,"energy":0.0,"hygiene":100.0,"mood":80.0,"health":100.0}
	var sleep_eight: Dictionary = SimulationKernelScript.simulate(sleep_full, 1000, 29800, BALANCE, care_session.lifecycle, care_session.care).new_state
	approx(sleep_eight.active_pet.vitals.hunger, 83.3333333, "sleep 8h hunger")
	approx(sleep_eight.active_pet.vitals.hydration, 66.6666667, "sleep 8h hydration")
	eq(sleep_eight.active_pet.vitals.energy, 100.0, "sleep 8h energy")
	approx(sleep_eight.active_pet.vitals.hygiene, 88.8888889, "sleep 8h hygiene")
	eq(sleep_eight.active_pet.vitals.mood, 80.0, "sleep mood unchanged")
	var sleep_chunks := sleep_full.duplicate(true)
	for i in range(8): sleep_chunks = SimulationKernelScript.simulate(sleep_chunks, 1000 + i * 3600, 1000 + (i + 1) * 3600, BALANCE, care_session.lifecycle, care_session.care).new_state
	for key in ["hunger", "hydration", "energy", "hygiene"]: approx(sleep_chunks.active_pet.vitals[key], sleep_eight.active_pet.vitals[key], "sleep chunking " + key)
	var clamp_sleep := sleep_full.duplicate(true); clamp_sleep.active_pet.vitals.energy = 90.0
	eq(SimulationKernelScript.simulate(clamp_sleep, 1000, 1000 + 28800, BALANCE, care_session.lifecycle, care_session.care).new_state.active_pet.vitals.energy, 100.0, "sleep energy clamps")
	# Awake/sleep UI controls, reaction messages, and stable reaction text.
	var care_ui_session = PetGameSessionScript.new(); care_ui_session.balance = BALANCE; care_ui_session.lifecycle = care_session.lifecycle; care_ui_session.care = care_session.care; care_ui_session.profile = fixture(); care_ui_session.profile.active_pet.vitals.mood = 70.0; care_ui_session.reanchor(10.0)
	var care_screen = FoundationScreenScript.new(); care_screen.session_override = care_ui_session; care_screen._ready()
	for name in ["Feed", "Drink", "Play", "Wash", "Touch", "Sleep"]: ok(care_screen.has_lifecycle_button(name), "awake UI has " + name)
	var feed_button := care_screen.lifecycle_button("Feed"); var awake_rebuilds: int = care_screen.lifecycle_rebuild_count
	for i in range(3): care_screen.refresh()
	eq(care_screen.lifecycle_button("Feed"), feed_button, "awake feed button stable")
	eq(care_screen.lifecycle_rebuild_count, awake_rebuilds, "awake controls do not rebuild")
	care_screen._care("feed"); ok(care_screen.reaction_label.text.contains("ate"), "feed reaction visible")
	var reaction_before: String = care_screen.reaction_label.text; care_screen.refresh(); eq(care_screen.reaction_label.text, reaction_before, "reaction survives refresh")
	care_ui_session.profile.active_pet.vitals.energy = 5.0; care_screen._care("play"); ok(care_screen.reaction_label.text.contains("tired"), "low energy reaction visible")
	care_ui_session.profile.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; care_screen.refresh(); eq(care_screen.lifecycle_rebuild_count, awake_rebuilds + 1, "awake to sleeping rebuilds once")
	ok(care_screen.has_lifecycle_button("Wake") and not care_screen.has_lifecycle_button("Feed"), "sleeping UI shows wake only")
	var wake_button := care_screen.lifecycle_button("Wake"); var sleep_rebuilds: int = care_screen.lifecycle_rebuild_count; care_screen.refresh(); care_screen.refresh()
	eq(care_screen.lifecycle_button("Wake"), wake_button, "wake button stable")
	eq(care_screen.lifecycle_rebuild_count, sleep_rebuilds, "sleep controls do not rebuild")
	care_screen._care("feed"); ok(care_screen.reaction_label.text.contains("sleeping"), "sleep rejection reaction visible")
	care_ui_session.profile.active_pet.activity = {"state":"AWAKE", "sleep_started_at":null}; care_screen.refresh(); eq(care_screen.lifecycle_rebuild_count, sleep_rebuilds + 1, "sleeping to awake rebuilds once")
	# Phase 4: survival is formula-based, protection-aware, and durable.
	var SURVIVAL := {"survival_balance_version":1, "hunger_zero_health_loss_per_hour":2.0, "hydration_zero_health_loss_per_hour":4.0, "critical_health_threshold":25.0}
	var protected := fixture(); protected.active_pet.life.newborn_protection_until = 1000 + 43200; protected.active_pet.vitals.hunger = 0.0; protected.active_pet.vitals.hydration = 0.0
	var protected_result: Dictionary = SimulationKernelScript.simulate(protected, 1000, 1000 + 3600, BALANCE, {}, {}, SURVIVAL).new_state
	eq(protected_result.active_pet.vitals.health, 100.0, "newborn protection blocks deprivation damage")
	var crossing := protected.duplicate(true); var crossing_result: Dictionary = SimulationKernelScript.simulate(crossing, 1000 + 42000, 1000 + 45000, BALANCE, {}, {}, SURVIVAL).new_state
	approx(crossing_result.active_pet.vitals.health, 97.0, "only post-protection deprivation damages health")
	var hunger_only := fixture(); hunger_only.active_pet.life.newborn_protection_until = 0; hunger_only.active_pet.vitals.hunger = 0.0
	approx(SimulationKernelScript.simulate(hunger_only, 1000, 19000, BALANCE, {}, {}, SURVIVAL).new_state.active_pet.vitals.health, 90.0, "hunger zero loses two health per hour")
	var hydration_only := fixture(); hydration_only.active_pet.life.newborn_protection_until = 0; hydration_only.active_pet.vitals.hydration = 0.0
	approx(SimulationKernelScript.simulate(hydration_only, 1000, 19000, BALANCE, {}, {}, SURVIVAL).new_state.active_pet.vitals.health, 80.0, "hydration zero loses four health per hour")
	var midpoint := fixture(); midpoint.active_pet.life.newborn_protection_until = 0; midpoint.active_pet.vitals.hunger = 1.0
	approx(SimulationKernelScript.simulate(midpoint, 1000, 1000 + 3600, BALANCE, {}, {}, SURVIVAL).new_state.active_pet.vitals.health, 98.96, "damage begins only after hunger reaches zero")
	var critical := fixture(); critical.active_pet.life.newborn_protection_until = 0; critical.active_pet.vitals.hunger = 0.0; critical.active_pet.vitals.hydration = 100.0; critical.active_pet.vitals.health = 30.0
	var critical_one: Dictionary = SimulationKernelScript.simulate(critical, 1000, 11000, BALANCE, {}, {}, SURVIVAL)
	eq(critical_one.new_state.active_pet.survival.condition, "CRITICAL", "health threshold enters critical")
	eq(critical_one.new_state.active_pet.survival.critical_started_at, 10000, "critical timestamp is deterministic")
	ok(_has_event(critical_one.generated_events, "pet_became_critical"), "critical emits event")
	var critical_chunk: Dictionary = SimulationKernelScript.simulate(critical, 1000, 6000, BALANCE, {}, {}, SURVIVAL).new_state
	critical_chunk = SimulationKernelScript.simulate(critical_chunk, 6000, 11000, BALANCE, {}, {}, SURVIVAL).new_state
	eq(critical_chunk.active_pet.survival.critical_started_at, critical_one.new_state.active_pet.survival.critical_started_at, "critical chunking timestamp equivalence")
	var death := fixture(); death.active_pet.life.newborn_protection_until = 0; death.active_pet.vitals.hunger = 0.0; death.active_pet.vitals.hydration = 0.0; death.active_pet.vitals.health = 12.0
	var dead_result: Dictionary = SimulationKernelScript.simulate(death, 1000, 1000 + 10800, BALANCE, {}, {}, SURVIVAL)
	eq(dead_result.new_state.active_pet.life.life_state, "DEAD", "combined deprivation kills pet")
	eq(dead_result.new_state.active_pet.life.died_at, 8200, "death timestamp is earliest whole second")
	eq(dead_result.new_state.active_pet.life.death_cause, "COMBINED_DEPRIVATION", "combined death cause")
	eq(dead_result.new_state.active_pet.vitals.health, 0.0, "death sets health to zero")
	ok(_has_event(dead_result.generated_events, "pet_became_critical") and _has_event(dead_result.generated_events, "pet_died"), "critical event precedes a death candidate")
	ok(dead_result.generated_events[-1].event_id.contains(":s1:"), "simulation event identity includes survival balance version")
	var frozen_hygiene: float = dead_result.new_state.active_pet.vitals.hygiene
	var dead_later: Dictionary = SimulationKernelScript.simulate(dead_result.new_state, 1000 + 10800, 1000 + 86400, BALANCE, {}, {}, SURVIVAL).new_state
	eq(dead_later.active_pet.vitals.hygiene, frozen_hygiene, "dead pet remains biologically frozen")
	var rescue_session = PetGameSessionScript.new(); rescue_session.balance = BALANCE; rescue_session.lifecycle = care_session.lifecycle; rescue_session.care = care_session.care; rescue_session.survival = SURVIVAL; rescue_session.profile = critical_one.new_state; rescue_session.reanchor(10.0)
	ok(rescue_session.care_action("feed", 10.0).ok, "critical feed succeeds")
	eq(rescue_session.profile.active_pet.survival.condition, "STABLE", "feed rescues single deprivation critical pet")
	ok(_has_event(rescue_session.profile.recent_events, "pet_stabilized"), "rescue emits stabilized event")
	var dead_session = PetGameSessionScript.new(); dead_session.balance = BALANCE; dead_session.lifecycle = care_session.lifecycle; dead_session.care = care_session.care; dead_session.survival = SURVIVAL; dead_session.profile = dead_result.new_state; dead_session.reanchor(10.0)
	eq(dead_session.care_action("feed", 10.0).reason, "PET_DEAD", "dead pet care is rejected")
	_reset(); ok(LocalSaveRepositoryScript.save_profile(dead_result.new_state), "persist dead pet before memorial")
	ok(dead_session.memorialize_pet(10.0).ok, "memorialization persists dead pet snapshot")
	eq(dead_session.profile.active_subject, "NONE", "memorialization removes active dead pet")
	eq(dead_session.profile.memorials.size(), 1, "memorialization appends one memorial")
	eq(dead_session.profile.memorials[0].pet_snapshot.identity.pet_id, "pet:test", "memorial preserves pet identity")
	ok(_has_event(dead_session.profile.recent_events, "pet_memorialized"), "memorialization emits event")
	var failed_memorial = PetGameSessionScript.new(); failed_memorial.balance = BALANCE; failed_memorial.lifecycle = care_session.lifecycle; failed_memorial.care = care_session.care; failed_memorial.survival = SURVIVAL; failed_memorial.profile = dead_result.new_state.duplicate(true); failed_memorial.reanchor(10.0)
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(failed_memorial.memorialize_pet(10.0).reason, "PERSIST_FAILED", "memorial persistence failure is reported")
	eq(failed_memorial.profile.active_subject, "PET", "failed memorial keeps dead pet active")
	eq(failed_memorial.profile.memorials.size(), 0, "failed memorial adds no authoritative snapshot")
	ok(dead_session.request_new_egg(10.0).ok, "explicit post-memorial new egg succeeds")
	eq(dead_session.profile.active_subject, "EGG", "new egg restores egg lifecycle only by explicit action")
	eq(dead_session.profile.memorials.size(), 1, "new egg preserves memorial history")
	# v4 migration adds survival metadata without changing the v4 pet identity/vitals.
	var v4_pet := fixture(); v4_pet.schema_version = 4; v4_pet.active_pet.schema_version = 4; v4_pet.active_pet.erase("survival"); v4_pet.simulation.simulation_version = 4; v4_pet.simulation.erase("survival_balance_version")
	var migrated_v4 := SaveMigratorScript.migrate(v4_pet)
	eq(migrated_v4.schema_version, 5, "v4 pet migrates to v5")
	eq(migrated_v4.active_pet.survival.condition, "STABLE", "v4 pet migration adds stable survival")
	eq(migrated_v4.simulation.survival_balance_version, 1, "v4 migration adds survival balance version")
	ok(DomainStateScript.validate_profile(migrated_v4), "migrated v4 pet validates")
	var valid_dead: Dictionary = dead_result.new_state.active_pet; ok(DomainStateScript.validate_pet(valid_dead), "valid dead pet validates")
	var malformed_memorial := DomainStateScript.new_profile("bad:memorial", 1); malformed_memorial.memorials = [{"memorial_id":"", "memorialized_at":1, "pet_snapshot":valid_dead}]; malformed_memorial.memorial_count = 1
	ok(not DomainStateScript.validate_profile(malformed_memorial), "malformed memorial fails validation")
	_reset(); var offline_dead := death.duplicate(true); ok(LocalSaveRepositoryScript.save_profile(offline_dead), "persist survival fixture for offline death")
	var offline_death_session = PetGameSessionScript.new(); offline_death_session.balance = BALANCE; offline_death_session.lifecycle = care_session.lifecycle; offline_death_session.care = care_session.care; offline_death_session.survival = SURVIVAL; offline_death_session.initialize_session(1000 + 10800, 20.0)
	eq(offline_death_session.profile.active_pet.life.life_state, "DEAD", "offline reconciliation produces dead pet")
	eq(offline_death_session.profile.active_pet.life.died_at, 8200, "offline death keeps deterministic earlier timestamp")
	eq(LocalSaveRepositoryScript.load_profile().active_pet.life.life_state, "DEAD", "offline death reconciliation persists")
	# Phase 4 corrective pass: complete survival, memorial and presentation acceptance coverage.
	var combined := fixture(); combined.active_pet.life.newborn_protection_until = 0; combined.active_pet.vitals.hunger = 0.0; combined.active_pet.vitals.hydration = 0.0
	approx(SimulationKernelScript.simulate(combined, 1000, 19000, BALANCE, {}, {}, SURVIVAL).new_state.active_pet.vitals.health, 70.0, "combined non-lethal deprivation loses six health per hour")
	var starvation := fixture(); starvation.active_pet.life.newborn_protection_until = 0; starvation.active_pet.vitals.hunger = 0.0; starvation.active_pet.vitals.hydration = 100.0; starvation.active_pet.vitals.health = 4.0
	var starvation_result: Dictionary = SimulationKernelScript.simulate(starvation, 1000, 10000, BALANCE, {}, {}, SURVIVAL)
	eq(starvation_result.new_state.active_pet.life.death_cause, "STARVATION", "hunger-only deprivation has starvation cause")
	eq(starvation_result.new_state.active_pet.life.died_at, 8200, "starvation death timestamp is deterministic")
	var dehydration := fixture(); dehydration.active_pet.life.newborn_protection_until = 0; dehydration.active_pet.vitals.hunger = 100.0; dehydration.active_pet.vitals.hydration = 0.0; dehydration.active_pet.vitals.health = 4.0
	var dehydration_result: Dictionary = SimulationKernelScript.simulate(dehydration, 1000, 6000, BALANCE, {}, {}, SURVIVAL)
	eq(dehydration_result.new_state.active_pet.life.death_cause, "DEHYDRATION", "hydration-only deprivation has dehydration cause")
	var death_chunk: Dictionary = SimulationKernelScript.simulate(death, 1000, 4600, BALANCE, {}, {}, SURVIVAL).new_state
	death_chunk = SimulationKernelScript.simulate(death_chunk, 4600, 8200, BALANCE, {}, {}, SURVIVAL).new_state
	for key in ["life_state", "died_at", "death_cause"]: eq(death_chunk.active_pet.life[key], dead_result.new_state.active_pet.life[key], "death chunking preserves " + key)
	for key in ["hunger", "hydration", "energy", "hygiene", "health"]: approx(death_chunk.active_pet.vitals[key], dead_result.new_state.active_pet.vitals[key], "death chunking preserves " + key)
	var critical_repeat: Dictionary = SimulationKernelScript.simulate(critical_one.new_state, 11000, 12000, BALANCE, {}, {}, SURVIVAL)
	ok(not _has_event(critical_repeat.generated_events, "pet_became_critical"), "critical event is emitted exactly once")
	eq(critical_repeat.new_state.active_pet.survival.critical_started_at, 10000, "critical timestamp remains unchanged")
	var partial_session = PetGameSessionScript.new(); partial_session.balance = BALANCE; partial_session.lifecycle = care_session.lifecycle; partial_session.care = care_session.care; partial_session.survival = SURVIVAL; partial_session.profile = fixture(); partial_session.profile.active_pet.life.newborn_protection_until = 0; partial_session.profile.active_pet.vitals.hunger = 0.0; partial_session.profile.active_pet.vitals.hydration = 0.0; partial_session.profile.active_pet.vitals.health = 20.0; partial_session.profile.active_pet.survival = {"condition":"CRITICAL","critical_started_at":1000}; partial_session.reanchor(10.0)
	var health_before_rescue: float = partial_session.profile.active_pet.vitals.health
	ok(partial_session.care_action("feed", 10.0).ok, "partial rescue feed succeeds")
	eq(partial_session.profile.active_pet.survival.condition, "CRITICAL", "feed alone does not clear combined critical danger")
	ok(not _has_event(partial_session.profile.recent_events, "pet_stabilized"), "partial rescue emits no stabilized event")
	ok(partial_session.care_action("drink", 10.0).ok, "complete rescue drink succeeds")
	eq(partial_session.profile.active_pet.survival.condition, "STABLE", "both restored needs stabilize pet")
	eq(partial_session.profile.active_pet.survival.critical_started_at, null, "complete rescue clears critical timestamp")
	eq(partial_session.profile.active_pet.vitals.health, health_before_rescue, "rescue does not restore health")
	# Runtime survival config governs both math and deterministic event identity without mutating persisted governance.
	var survival_mismatch := fixture(); survival_mismatch.active_pet.life.newborn_protection_until = 0; survival_mismatch.active_pet.vitals.hunger = 0.0; survival_mismatch.simulation.survival_balance_version = 1
	var survival_v2 := SURVIVAL.duplicate(true); survival_v2.survival_balance_version = 2; survival_v2.hunger_zero_health_loss_per_hour = 4.0
	var survival_one: Dictionary = SimulationKernelScript.simulate(survival_mismatch, 1000, 4600, BALANCE, {}, {}, SURVIVAL)
	var survival_two: Dictionary = SimulationKernelScript.simulate(survival_mismatch, 1000, 4600, BALANCE, {}, {}, survival_v2)
	approx(survival_two.new_state.active_pet.vitals.health, 96.0, "runtime survival v2 changes health math")
	ok(survival_two.generated_events[-1].event_id.contains(":s2:"), "runtime survival v2 event identity is honest")
	ok(survival_one.generated_events[-1].event_id != survival_two.generated_events[-1].event_id, "survival v1 and v2 ids differ")
	eq(survival_two.new_state.simulation.survival_balance_version, 1, "pure simulation preserves persisted survival version")
	# Historical memorial counts may exceed persisted snapshot count and are never lost.
	var legacy_memorial = dead_result.new_state.duplicate(true); legacy_memorial.memorial_count = 3; legacy_memorial.memorials = []
	var legacy_session = PetGameSessionScript.new(); legacy_session.balance = BALANCE; legacy_session.lifecycle = care_session.lifecycle; legacy_session.care = care_session.care; legacy_session.survival = SURVIVAL; legacy_session.profile = legacy_memorial; legacy_session.reanchor(10.0)
	ok(legacy_session.memorialize_pet(10.0).ok, "legacy memorial profile can memorialize")
	eq(legacy_session.profile.memorial_count, 4, "historical memorial count increments independently")
	eq(legacy_session.profile.memorials.size(), 1, "new memorial snapshot is retained beside historical count")
	var failed_egg = PetGameSessionScript.new(); failed_egg.balance = BALANCE; failed_egg.lifecycle = care_session.lifecycle; failed_egg.care = care_session.care; failed_egg.survival = SURVIVAL; failed_egg.profile = legacy_session.profile.duplicate(true); failed_egg.reanchor(10.0)
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(failed_egg.request_new_egg(10.0).reason, "PERSIST_FAILED", "new egg persistence failure is reported")
	eq(failed_egg.profile.active_subject, "NONE", "failed new egg retains memorial state")
	eq(failed_egg.profile.memorial_count, 4, "failed new egg preserves historical memorial count")
	# DEAD and memorial presentation reads current/deep snapshot data and keeps controls stable.
	var death_ui_session = PetGameSessionScript.new(); death_ui_session.balance = BALANCE; death_ui_session.lifecycle = care_session.lifecycle; death_ui_session.care = care_session.care; death_ui_session.survival = SURVIVAL; death_ui_session.profile = dead_result.new_state.duplicate(true); death_ui_session.reanchor(10.0)
	var death_screen = FoundationScreenScript.new(); death_screen.session_override = death_ui_session; death_screen._ready()
	ok(death_screen.has_lifecycle_button("Memorialize Pet") and not death_screen.has_lifecycle_button("Feed"), "dead UI shows memorial only")
	ok(death_screen.inspector.text.contains("Name: Test") and death_screen.inspector.text.contains("Died At: 8200") and death_screen.inspector.text.contains("Death Cause: COMBINED_DEPRIVATION"), "dead UI displays death information")
	var memorial_button := death_screen.lifecycle_button("Memorialize Pet"); var dead_rebuilds: int = death_screen.lifecycle_rebuild_count; death_screen.refresh(); eq(death_screen.lifecycle_button("Memorialize Pet"), memorial_button, "dead memorial button stable"); eq(death_screen.lifecycle_rebuild_count, dead_rebuilds, "dead UI does not rebuild")
	ok(death_ui_session.memorialize_pet(10.0).ok, "UI fixture memorialization succeeds"); death_screen.refresh()
	ok(death_screen.has_lifecycle_button("New Egg") and death_screen.inspector.text.contains("Memorial") and death_screen.inspector.text.contains("Name: Test"), "memorial UI displays latest snapshot")
	var new_egg_button := death_screen.lifecycle_button("New Egg"); var memorial_rebuilds: int = death_screen.lifecycle_rebuild_count; death_screen.refresh(); eq(death_screen.lifecycle_button("New Egg"), new_egg_button, "new egg button stable"); eq(death_screen.lifecycle_rebuild_count, memorial_rebuilds, "memorial UI does not rebuild")
	ok(death_ui_session.request_new_egg(10.0).ok, "UI fixture creates explicit new egg"); death_screen.refresh(); ok(death_screen.has_lifecycle_button("Touch Egg") and not death_screen.has_lifecycle_button("New Egg"), "new egg UI returns to incubation controls")
	death_screen.free(); death_ui_session.free(); failed_egg.free(); legacy_session.free(); partial_session.free()
	offline_death_session.free(); failed_memorial.free(); dead_session.free(); rescue_session.free()
	care_screen.free(); care_ui_session.free(); clamp_session.free(); migrated_hatch_session.free()
	for value in [fail_care, sleep_startup, timeline]: value.free()
	care_session.free()

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(content); file.close()
func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if String(event.get("event_type", "")) == event_type: return true
	return false
func _reset() -> void:
	for path in [LocalSaveRepositoryScript.PROFILE_PATH, LocalSaveRepositoryScript.BACKUP_PATH, LocalSaveRepositoryScript.TEMP_PATH, LocalSaveRepositoryScript.BACKUP_TEMP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
