extends SceneTree

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const SaveMigratorScript = preload("res://infrastructure/persistence/save_migrator.gd")
const PetGameSessionScript = preload("res://application/game_session/game_session.gd")
const FoundationScreenScript = preload("res://presentation/ui/foundation_screen.gd")
const DefaultGrowthBalanceScript = preload("res://application/growth/default_growth_balance.gd")

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
	eq(none.schema_version, 7, "new profile uses schema v7")
	ok(DomainStateScript.validate_profile(none), "normal v6 profile valid")
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
	ok(DomainStateScript.validate_profile(migrated), "v1 migrates to valid v6")
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
	eq(migrated_inc.schema_version, 7, "v3 incubating migrates v7")
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
	eq(migrated_v4.schema_version, 7, "v4 pet migrates to v7")
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
	# Final Phase 4 corrective pass: application permanence, UI matrices and v4 egg migration.
	var permanent_session = PetGameSessionScript.new(); permanent_session.balance = BALANCE; permanent_session.lifecycle = care_session.lifecycle; permanent_session.care = care_session.care; permanent_session.survival = SURVIVAL; permanent_session.profile = dead_result.new_state.duplicate(true); permanent_session.reanchor(10.0)
	var dead_vitals: Dictionary = permanent_session.profile.active_pet.vitals.duplicate(true); var dead_at: int = int(permanent_session.profile.active_pet.life.died_at); var dead_cause: String = String(permanent_session.profile.active_pet.life.death_cause)
	permanent_session.resume_at(20000, 20.0); eq(permanent_session.profile.active_pet.life.life_state, "DEAD", "resume keeps death permanent"); eq(permanent_session.profile.active_pet.vitals, dead_vitals, "resume freezes dead vitals"); eq(permanent_session.profile.active_pet.life.died_at, dead_at, "resume keeps death timestamp")
	permanent_session.advance_debug(604800, 30.0); eq(permanent_session.profile.active_pet.vitals, dead_vitals, "debug keeps dead vitals frozen"); eq(permanent_session.profile.active_pet.life.death_cause, dead_cause, "debug keeps death cause")
	permanent_session.resume_at(1000, 40.0); eq(permanent_session.profile.active_pet.life.died_at, dead_at, "backward wall clock does not alter dead timestamp"); eq(permanent_session.profile.active_pet.vitals.health, 0.0, "backward wall clock cannot revive pet")
	var dead_events_before: int = permanent_session.profile.recent_events.size()
	for action in ["feed", "drink", "sleep", "wake"]:
		eq(permanent_session.care_action(action, 40.0).reason, "PET_DEAD", "dead %s is rejected" % action)
	eq(permanent_session.profile.recent_events.size(), dead_events_before, "dead care actions append no events")
	# Stable/critical/dead control semantics include the critical-sleeping warning.
	var critical_ui_session = PetGameSessionScript.new(); critical_ui_session.balance = BALANCE; critical_ui_session.lifecycle = care_session.lifecycle; critical_ui_session.care = care_session.care; critical_ui_session.survival = SURVIVAL; critical_ui_session.profile = fixture(); critical_ui_session.reanchor(10.0)
	var critical_screen = FoundationScreenScript.new(); critical_screen.session_override = critical_ui_session; critical_screen._ready()
	var stable_feed := critical_screen.lifecycle_button("Feed"); var stable_rebuilds: int = critical_screen.lifecycle_rebuild_count; critical_screen.refresh(); eq(critical_screen.lifecycle_button("Feed"), stable_feed, "stable awake feed remains stable"); eq(critical_screen.lifecycle_rebuild_count, stable_rebuilds, "stable awake does not rebuild")
	critical_ui_session.profile.active_pet.survival = {"condition":"CRITICAL", "critical_started_at":1000}; critical_screen.refresh(); eq(critical_screen.lifecycle_rebuild_count, stable_rebuilds + 1, "stable to critical awake rebuilds once"); ok(critical_screen.inspector.text.contains("CRITICAL") or critical_screen.lifecycle_status.text.contains("CRITICAL"), "critical awake warning visible"); ok(critical_screen.has_lifecycle_button("Feed") and critical_screen.has_lifecycle_button("Drink"), "critical awake retains care controls")
	var critical_feed := critical_screen.lifecycle_button("Feed"); var critical_rebuilds: int = critical_screen.lifecycle_rebuild_count; critical_screen.refresh(); eq(critical_screen.lifecycle_button("Feed"), critical_feed, "critical awake feed stable"); eq(critical_screen.lifecycle_rebuild_count, critical_rebuilds, "critical awake does not rebuild")
	critical_ui_session.profile.active_pet.activity = {"state":"SLEEPING", "sleep_started_at":1000}; critical_screen.refresh(); eq(critical_screen.lifecycle_rebuild_count, critical_rebuilds + 1, "critical awake to sleeping rebuilds once"); ok(critical_screen.has_lifecycle_button("Wake") and not critical_screen.has_lifecycle_button("Feed"), "critical sleeping remains wake-only"); ok(critical_screen.lifecycle_status.text.contains("CRITICAL") and critical_screen.lifecycle_status.text.contains("sleeping"), "critical sleeping warning remains visible")
	var critical_wake := critical_screen.lifecycle_button("Wake"); var critical_sleep_rebuilds: int = critical_screen.lifecycle_rebuild_count; critical_screen.refresh(); eq(critical_screen.lifecycle_button("Wake"), critical_wake, "critical sleeping wake stable"); eq(critical_screen.lifecycle_rebuild_count, critical_sleep_rebuilds, "critical sleeping does not rebuild")
	critical_ui_session.profile = dead_result.new_state.duplicate(true); critical_screen.refresh(); ok(critical_screen.has_lifecycle_button("Memorialize Pet") and not critical_screen.has_lifecycle_button("Wake"), "critical to dead removes care controls")
	# Historical count-only state cannot expose an impossible New Egg action.
	var historical_ui_session = PetGameSessionScript.new(); historical_ui_session.balance = BALANCE; historical_ui_session.lifecycle = care_session.lifecycle; historical_ui_session.care = care_session.care; historical_ui_session.survival = SURVIVAL; historical_ui_session.profile = DomainStateScript.new_profile("historical", 1000); historical_ui_session.profile.memorial_count = 3; historical_ui_session.profile.memorials = []
	var historical_screen = FoundationScreenScript.new(); historical_screen.session_override = historical_ui_session; historical_screen._ready(); ok(historical_screen.inspector.text.contains("Historical memorials: 3"), "historical-only memorial UI is safe"); ok(not historical_screen.has_lifecycle_button("New Egg"), "historical-only UI hides unavailable new egg action"); eq(historical_ui_session.request_new_egg(10.0).reason, "NEW_EGG_UNAVAILABLE", "application and historical-only UI agree")
	# Full validation matrix for survival/death and snapshot memorials.
	var validation_critical: Dictionary = fixture().active_pet; validation_critical.survival = {"condition":"CRITICAL", "critical_started_at":1}; ok(DomainStateScript.validate_pet(validation_critical), "valid alive critical pet validates")
	var invalid_survival: Dictionary = fixture().active_pet; invalid_survival.survival = {"condition":"STABLE", "critical_started_at":1}; ok(not DomainStateScript.validate_pet(invalid_survival), "stable with timestamp fails")
	invalid_survival = fixture().active_pet; invalid_survival.survival = {"condition":"CRITICAL", "critical_started_at":null}; ok(not DomainStateScript.validate_pet(invalid_survival), "critical without timestamp fails")
	var invalid_dead := valid_dead.duplicate(true); invalid_dead.life.died_at = null; ok(not DomainStateScript.validate_pet(invalid_dead), "dead without died_at fails")
	invalid_dead = valid_dead.duplicate(true); invalid_dead.life.death_cause = ""; ok(not DomainStateScript.validate_pet(invalid_dead), "dead without cause fails")
	invalid_dead = valid_dead.duplicate(true); invalid_dead.vitals.health = 1.0; ok(not DomainStateScript.validate_pet(invalid_dead), "dead health above zero fails")
	invalid_dead = fixture().active_pet; invalid_dead.life.died_at = 1; ok(not DomainStateScript.validate_pet(invalid_dead), "alive with died_at fails")
	var valid_memorial := DomainStateScript.new_profile("good:memorial", 1); valid_memorial.memorial_count = 1; valid_memorial.memorials = [{"schema_version":1, "memorial_id":"memorial:good", "memorialized_at":9000, "pet_snapshot":valid_dead.duplicate(true)}]; ok(DomainStateScript.validate_profile(valid_memorial), "valid dead snapshot memorial validates")
	# Real schema-v4 egg migration preserves all egg/hatching data and completion identity.
	var v4_egg := DomainStateScript.new_profile("v4:egg", 1000); v4_egg.schema_version = 4; v4_egg.simulation.simulation_version = 4; v4_egg.simulation.erase("survival_balance_version"); v4_egg.active_subject = "EGG"; v4_egg.active_egg = DomainStateScript.new_egg("egg:v4", 1000, 15400); v4_egg.active_egg.schema_version = 4
	var v5_inc := SaveMigratorScript.migrate(v4_egg); eq(v5_inc.schema_version, 7, "v4 incubating migrates to v7"); eq(v5_inc.active_egg.egg_id, "egg:v4", "v4 egg id preserved"); eq(v5_inc.active_egg.hatch_ready_at, 15400, "v4 egg ready time preserved")
	v4_egg.active_egg.state = "READY"; eq(SaveMigratorScript.migrate(v4_egg).active_egg.state, "READY", "v4 ready remains ready")
	v4_egg.active_egg.state = "HATCHING"; v4_egg.active_egg.reserved_pet_id = "pet:v4-reserved"; v4_egg.active_egg.reserved_pet_seed = 88; v4_egg.active_egg.hatching_started_at = 15400
	var v5_hatching := SaveMigratorScript.migrate(v4_egg); eq(v5_hatching.active_egg.reserved_pet_id, "pet:v4-reserved", "v4 hatching reserved identity preserved")
	var v4_hatching_session = PetGameSessionScript.new(); v4_hatching_session.balance = BALANCE; v4_hatching_session.lifecycle = care_session.lifecycle; v4_hatching_session.care = care_session.care; v4_hatching_session.survival = SURVIVAL; v4_hatching_session.profile = v5_hatching; ok(v4_hatching_session.complete_hatching(16000, 10.0), "migrated v4 hatching completes"); eq(v4_hatching_session.profile.active_pet.identity.pet_id, "pet:v4-reserved", "migrated v4 hatching uses reserved pet identity")
	# Critical/death chronology is ordered in a single long reconciliation.
	ok(_event_index(dead_result.generated_events, "pet_became_critical") < _event_index(dead_result.generated_events, "pet_died"), "critical event precedes death event"); ok(dead_result.new_state.active_pet.survival.critical_started_at < dead_result.new_state.active_pet.life.died_at, "critical timestamp precedes death timestamp")
	# Final transaction authority evidence: failed candidates never replace profile or recovery state.
	_reset(); var authority_dead: Dictionary = dead_result.new_state.duplicate(true); authority_dead.initial_egg_issued = true; ok(LocalSaveRepositoryScript.save_profile(authority_dead), "persist active dead pet for memorial authority")
	var memorial_authority = PetGameSessionScript.new(); memorial_authority.balance = BALANCE; memorial_authority.lifecycle = care_session.lifecycle; memorial_authority.care = care_session.care; memorial_authority.survival = SURVIVAL; memorial_authority.profile = authority_dead.duplicate(true); memorial_authority.reanchor(10.0)
	var before_memorial_count: int = memorial_authority.profile.memorial_count; var before_memorials: Array = memorial_authority.profile.memorials.duplicate(true); var before_memorial_events: Array = memorial_authority.profile.recent_events.duplicate(true); var before_dead_pet: Dictionary = memorial_authority.profile.active_pet.duplicate(true)
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	var failed_memorial_result: Dictionary = memorial_authority.memorialize_pet(10.0)
	eq(failed_memorial_result.ok, false, "failed memorial returns failure"); eq(failed_memorial_result.reason, "PERSIST_FAILED", "failed memorial reports persistence reason")
	eq(memorial_authority.profile.active_subject, "PET", "failed memorial keeps active subject")
	eq(memorial_authority.profile.active_pet, before_dead_pet, "failed memorial preserves complete dead pet")
	eq(memorial_authority.profile.memorial_count, before_memorial_count, "failed memorial preserves count")
	eq(memorial_authority.profile.memorials, before_memorials, "failed memorial preserves snapshots")
	eq(memorial_authority.profile.recent_events, before_memorial_events, "failed memorial preserves recent events")
	ok(not _has_event(memorial_authority.profile.recent_events, "pet_memorialized"), "failed memorial has no authoritative event")
	var recovered_dead: Dictionary = LocalSaveRepositoryScript.load_profile(); eq(recovered_dead.active_subject, "PET", "failed memorial recovery keeps dead subject"); ok(not _has_event(recovered_dead.recent_events, "pet_memorialized"), "failed memorial event is not durable")
	# Successful memorialization is exact-once at the active-pet boundary.
	ok(memorial_authority.memorialize_pet(10.0).ok, "first memorialization succeeds")
	var after_memorial_count: int = memorial_authority.profile.memorial_count; var after_memorial_size: int = memorial_authority.profile.memorials.size(); var after_memorial_events: int = _count_events(memorial_authority.profile.recent_events, "pet_memorialized")
	var second_memorial: Dictionary = memorial_authority.memorialize_pet(10.0)
	eq(second_memorial.ok, false, "second memorialization rejected"); eq(memorial_authority.profile.active_subject, "NONE", "second memorialization retains none state"); eq(memorial_authority.profile.active_pet, null, "second memorialization keeps pet absent")
	eq(memorial_authority.profile.memorial_count, after_memorial_count, "second memorialization preserves count"); eq(memorial_authority.profile.memorials.size(), after_memorial_size, "second memorialization adds no snapshot"); eq(_count_events(memorial_authority.profile.recent_events, "pet_memorialized"), after_memorial_events, "second memorialization adds no event")
	# Memorial startup is inert; New Egg is always an explicit action.
	var memorial_startup = PetGameSessionScript.new(); memorial_startup.balance = BALANCE; memorial_startup.lifecycle = care_session.lifecycle; memorial_startup.care = care_session.care; memorial_startup.survival = SURVIVAL; memorial_startup.initialize_session(20000, 20.0)
	eq(memorial_startup.profile.active_subject, "NONE", "memorial startup issues no automatic egg"); eq(memorial_startup.profile.active_egg, null, "memorial startup has no active egg"); eq(memorial_startup.profile.memorials.size(), after_memorial_size, "memorial startup preserves snapshots"); ok(not _has_event(memorial_startup.profile.recent_events, "egg_received"), "memorial startup adds no egg event")
	# Replacement egg failure candidate authority, then explicit creation and offline READY integration.
	var egg_authority = PetGameSessionScript.new(); egg_authority.balance = BALANCE; egg_authority.lifecycle = care_session.lifecycle; egg_authority.care = care_session.care; egg_authority.survival = SURVIVAL; egg_authority.profile = memorial_authority.profile.duplicate(true); egg_authority.reanchor(10.0)
	var before_egg_subject: String = String(egg_authority.profile.active_subject); var before_egg_value: Variant = egg_authority.profile.active_egg; var before_egg_count: int = egg_authority.profile.memorial_count; var before_egg_memorials: Array = egg_authority.profile.memorials.duplicate(true); var before_egg_events: Array = egg_authority.profile.recent_events.duplicate(true)
	LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	var failed_egg_result: Dictionary = egg_authority.request_new_egg(10.0)
	eq(failed_egg_result.ok, false, "failed new egg returns failure"); eq(failed_egg_result.reason, "PERSIST_FAILED", "failed new egg reports persistence reason")
	eq(String(egg_authority.profile.active_subject), before_egg_subject, "failed new egg preserves subject"); eq(egg_authority.profile.active_egg, before_egg_value, "failed new egg preserves null egg"); eq(egg_authority.profile.memorial_count, before_egg_count, "failed new egg preserves count"); eq(egg_authority.profile.memorials, before_egg_memorials, "failed new egg preserves snapshots"); eq(egg_authority.profile.recent_events, before_egg_events, "failed new egg preserves events"); ok(not _has_event(egg_authority.profile.recent_events, "egg_received"), "failed new egg has no authoritative event")
	var old_pet_id := String(egg_authority.profile.memorials[-1].pet_snapshot.identity.pet_id)
	ok(egg_authority.request_new_egg(10.0).ok, "explicit replacement egg succeeds")
	eq(egg_authority.profile.active_subject, "EGG", "replacement egg becomes active subject"); eq(egg_authority.profile.active_pet, null, "replacement egg has no pet"); eq(egg_authority.profile.active_egg.state, "INCUBATING", "replacement egg starts incubating"); eq(egg_authority.profile.initial_egg_issued, true, "replacement egg retains initial issue marker")
	var replacement_egg: Dictionary = egg_authority.profile.active_egg; ok(not String(replacement_egg.egg_id).is_empty() and String(replacement_egg.egg_id) != old_pet_id, "replacement egg receives fresh identity")
	eq(int(replacement_egg.hatch_ready_at) - int(replacement_egg.received_at), 14400, "replacement egg uses four hour incubation")
	var replacement_event: Dictionary = egg_authority.profile.recent_events[-1]; eq(replacement_event.event_type, "egg_received", "replacement egg emits received event"); eq(replacement_event.subject_id, replacement_egg.egg_id, "replacement egg event uses egg subject"); eq(replacement_event.payload.source, "new_cycle", "replacement egg event marks new cycle")
	var replacement_ready = PetGameSessionScript.new(); replacement_ready.balance = BALANCE; replacement_ready.lifecycle = care_session.lifecycle; replacement_ready.care = care_session.care; replacement_ready.survival = SURVIVAL; replacement_ready.initialize_session(int(replacement_egg.received_at) + 28800, 20.0)
	eq(replacement_ready.profile.active_subject, "EGG", "replacement egg remains egg after offline reconciliation"); eq(replacement_ready.profile.active_egg.state, "READY", "replacement egg becomes ready offline"); eq(replacement_ready.profile.active_pet, null, "replacement ready has no pet"); eq(replacement_ready.profile.active_egg.reserved_pet_id, null, "replacement ready has no reservation"); eq(replacement_ready.profile.active_egg.reserved_pet_seed, null, "replacement ready has no seed"); eq(replacement_ready.profile.active_egg.hatching_started_at, null, "replacement ready has not started hatching"); ok(not _has_event(replacement_ready.profile.recent_events, "pet_hatched"), "replacement ready has no unattended birth")
	var persisted_replacement: Dictionary = LocalSaveRepositoryScript.load_profile(); eq(persisted_replacement.active_egg.state, "READY", "replacement ready reconciliation persists")
	replacement_ready.free(); egg_authority.free(); memorial_startup.free(); memorial_authority.free()
	# Phase 5 relationship and memory: explicit care, pure views and atomic candidates.
	var RELATIONSHIP := {"relationship_balance_version":1, "reward_cooldown_seconds":300, "rewards":{"feed":{"bond":1,"trust":2,"care_experience":1},"drink":{"bond":1,"trust":2,"care_experience":1},"wash":{"bond":1,"trust":1,"care_experience":1},"touch":{"bond":2,"trust":1,"care_experience":1},"play":{"bond":2,"trust":1,"care_experience":1}},"rescue":{"bond":3,"trust":5,"care_experience":3}}
	var MEMORY := {"memory_version":1,"event_store_limit":64,"working_memory_limit":8,"episodic_min_importance":3}
	var relationship_session = PetGameSessionScript.new(); relationship_session.balance = BALANCE; relationship_session.lifecycle = care_session.lifecycle; relationship_session.care = care_session.care; relationship_session.survival = SURVIVAL; relationship_session.relationship_balance = RELATIONSHIP; relationship_session.memory_config = MEMORY; relationship_session.profile = fixture(); relationship_session.profile.active_pet.vitals.hunger = 40.0; relationship_session.reanchor(10.0)
	ok(relationship_session.care_action("feed", 10.0).ok, "meaningful feed succeeds with relationship config")
	eq(relationship_session.profile.active_pet.relationship.bond, 1.0, "feed grants bond"); eq(relationship_session.profile.active_pet.relationship.trust, 2.0, "feed grants trust"); eq(relationship_session.profile.active_pet.relationship.care_experience, 1.0, "feed grants care experience"); eq(relationship_session.profile.active_pet.relationship.last_rewarded_at.feed, 1000, "feed reward stores simulation timestamp")
	eq(relationship_session.profile.active_pet.memory.events[-1].event_type, "pet_fed", "feed projects care memory"); eq(relationship_session.profile.active_pet.memory.routine.feed.count, 1, "feed updates routine count"); eq(relationship_session.profile.active_pet.memory.routine.feed.meaningful_count, 1, "meaningful feed updates routine meaningful count"); eq(relationship_session.profile.active_pet.memory.semantic.favorite_interaction, "feed", "first meaningful care becomes favorite")
	relationship_session.profile.active_pet.vitals.hunger = 40.0; ok(relationship_session.care_action("feed", 20.0).ok, "cooldown feed still applies biological care")
	eq(relationship_session.profile.active_pet.relationship.bond, 1.0, "cooldown feed grants no bond"); eq(relationship_session.profile.recent_events[-1].payload.relationship_rewarded, false, "cooldown event reports no relationship reward")
	relationship_session.advance_active_to(310.0); relationship_session.profile.active_pet.vitals.hunger = 40.0; ok(relationship_session.care_action("feed", 310.0).ok, "feed after cooldown succeeds"); eq(relationship_session.profile.active_pet.relationship.bond, 2.0, "feed after cooldown rewards again")
	var no_op = PetGameSessionScript.new(); no_op.balance = BALANCE; no_op.lifecycle = care_session.lifecycle; no_op.care = care_session.care; no_op.survival = SURVIVAL; no_op.relationship_balance = RELATIONSHIP; no_op.memory_config = MEMORY; no_op.profile = fixture(); no_op.reanchor(10.0); ok(no_op.care_action("feed", 10.0).ok, "full feed remains biological success"); eq(no_op.profile.active_pet.relationship.bond, 0.0, "full feed receives no relationship reward"); eq(no_op.profile.active_pet.memory.events[-1].valence, 0, "full feed memory is neutral")
	var relation_v2 := RELATIONSHIP.duplicate(true); relation_v2.relationship_balance_version = 2; relation_v2.rewards = RELATIONSHIP.rewards.duplicate(true); relation_v2.rewards.feed = {"bond":7,"trust":8,"care_experience":9}
	var version_session = PetGameSessionScript.new(); version_session.balance = BALANCE; version_session.lifecycle = care_session.lifecycle; version_session.care = care_session.care; version_session.survival = SURVIVAL; version_session.relationship_balance = relation_v2; version_session.memory_config = MEMORY; version_session.profile = fixture(); version_session.profile.active_pet.vitals.hunger = 40.0; version_session.reanchor(10.0); ok(version_session.care_action("feed", 10.0).ok, "runtime v2 relationship feed succeeds"); eq(version_session.profile.active_pet.relationship.bond, 7.0, "runtime v2 relationship math is used"); eq(version_session.profile.active_pet.relationship.relationship_balance_version, 2, "runtime v2 relationship version persists"); eq(version_session.profile.recent_events[-1].payload.relationship_balance_version, 2, "runtime v2 event is honest")
	var fail_relation = PetGameSessionScript.new(); fail_relation.balance = BALANCE; fail_relation.lifecycle = care_session.lifecycle; fail_relation.care = care_session.care; fail_relation.survival = SURVIVAL; fail_relation.relationship_balance = relation_v2; fail_relation.memory_config = MEMORY; fail_relation.profile = fixture(); fail_relation.profile.active_pet.vitals.hunger = 40.0; fail_relation.reanchor(10.0); var relationship_before: Dictionary = fail_relation.profile.active_pet.relationship.duplicate(true); var memory_before: Dictionary = fail_relation.profile.active_pet.memory.duplicate(true); LocalSaveRepositoryScript.test_fail_next_primary_replace = true; eq(fail_relation.care_action("feed", 10.0).reason, "PERSIST_FAILED", "relationship-memory candidate failure reports failure"); eq(fail_relation.profile.active_pet.relationship, relationship_before, "failed candidate preserves relationship"); eq(fail_relation.profile.active_pet.memory, memory_before, "failed candidate preserves memory")
	var memory_model = preload("res://domain/memory/memory_model.gd"); var raw_memory: Dictionary = memory_model.new_memory()
	for index in range(70): raw_memory = memory_model.project(raw_memory, {"event_id":"evt:memory:%d" % index, "event_type":"pet_fed", "occurred_at":index, "payload":{"action":"feed","meaningful":true}}, MEMORY)
	eq(raw_memory.events.size(), 64, "memory store evicts to configured cap"); eq(raw_memory.next_sequence, 70, "memory sequence remains lifetime monotonic after eviction"); eq(memory_model.working_memory(raw_memory, MEMORY).size(), 8, "working memory returns latest configured window")
	var rich_memory := memory_model.new_memory(); rich_memory = memory_model.project(rich_memory, {"event_id":"evt:hatch","event_type":"pet_hatched","occurred_at":1,"payload":{}}, MEMORY); rich_memory = memory_model.project(rich_memory, {"event_id":"evt:sleep","event_type":"pet_sleep_started","occurred_at":2,"payload":{}}, MEMORY); rich_memory = memory_model.project(rich_memory, {"event_id":"evt:critical","event_type":"pet_became_critical","occurred_at":3,"payload":{}}, MEMORY)
	eq(memory_model.episodic_memory(rich_memory, MEMORY).size(), 2, "episodic view filters high-importance memories"); eq(memory_model.emotional_memory(rich_memory).size(), 2, "emotional view excludes neutral memories"); var dedup_size: int = rich_memory.events.size(); rich_memory = memory_model.project(rich_memory, {"event_id":"evt:critical","event_type":"pet_became_critical","occurred_at":3,"payload":{}}, MEMORY); eq(rich_memory.events.size(), dedup_size, "memory projection deduplicates source event")
	# v5 migration does not backfill, but normalizes active and memorial pets independently.
	var v5_memory_profile := fixture(); v5_memory_profile.schema_version = 5; v5_memory_profile.active_pet.schema_version = 5; v5_memory_profile.active_pet.erase("memory"); v5_memory_profile.active_pet.relationship = {"bond":7.0,"trust":8.0,"care_experience":9.0}; v5_memory_profile.memorial_count = 1; var dead_snapshot: Dictionary = valid_dead.duplicate(true); dead_snapshot.schema_version = 5; dead_snapshot.erase("memory"); dead_snapshot.relationship = {"bond":4.0,"trust":5.0,"care_experience":6.0}; v5_memory_profile.memorials = [{"schema_version":1,"memorial_id":"memorial:v5","memorialized_at":9000,"pet_snapshot":dead_snapshot}]
	var v6_memory_profile: Dictionary = SaveMigratorScript.migrate(v5_memory_profile); ok(DomainStateScript.validate_profile(v6_memory_profile), "v5 active and memorial pets migrate to valid v6"); eq(v6_memory_profile.active_pet.relationship.bond, 7.0, "v5 relationship values are preserved"); eq(v6_memory_profile.active_pet.memory.events.size(), 0, "v5 active pet memory is not backfilled"); eq(v6_memory_profile.memorials[0].pet_snapshot.relationship.trust, 5.0, "v5 memorial relationship preserved"); eq(v6_memory_profile.memorials[0].pet_snapshot.memory.events.size(), 0, "v5 memorial memory starts empty")
	# Hatch event starts a new pet's own lifecycle memory.
	var hatch_memory_session = PetGameSessionScript.new(); hatch_memory_session.balance = BALANCE; hatch_memory_session.lifecycle = care_session.lifecycle; hatch_memory_session.care = care_session.care; hatch_memory_session.survival = SURVIVAL; hatch_memory_session.relationship_balance = RELATIONSHIP; hatch_memory_session.memory_config = MEMORY; hatch_memory_session.profile = DomainStateScript.new_profile("hatch:memory", 1000); hatch_memory_session.profile.initial_egg_issued = true; hatch_memory_session.profile.active_subject = "EGG"; hatch_memory_session.profile.active_egg = DomainStateScript.new_egg("egg:hatch-memory", 1000, 1000); hatch_memory_session.profile.active_egg.state = "HATCHING"; hatch_memory_session.profile.active_egg.reserved_pet_id = "pet:hatch-memory"; hatch_memory_session.profile.active_egg.reserved_pet_seed = 11; hatch_memory_session.profile.active_egg.hatching_started_at = 1000
	ok(hatch_memory_session.complete_hatching(1000, 10.0), "hatching projects memory before persistence"); eq(hatch_memory_session.profile.active_pet.memory.events.size(), 1, "new pet starts with hatch memory only"); eq(hatch_memory_session.profile.active_pet.memory.events[0].event_type, "pet_hatched", "hatch memory event type"); eq(hatch_memory_session.profile.active_pet.memory.events[0].category, "LIFECYCLE", "hatch memory category")
	# Simulation survival events project in order and freeze with the dead pet.
	var survival_memory_session = PetGameSessionScript.new(); survival_memory_session.balance = BALANCE; survival_memory_session.lifecycle = care_session.lifecycle; survival_memory_session.care = care_session.care; survival_memory_session.survival = SURVIVAL; survival_memory_session.relationship_balance = RELATIONSHIP; survival_memory_session.memory_config = MEMORY; survival_memory_session.profile = death.duplicate(true); survival_memory_session.reanchor(10.0); survival_memory_session.advance_in_memory_to(11800)
	var survival_memories: Array = survival_memory_session.profile.active_pet.memory.events; eq(survival_memories.size(), 2, "critical and death each project one memory"); eq(survival_memories[0].event_type, "pet_became_critical", "critical memory precedes death memory"); eq(survival_memories[1].event_type, "pet_died", "death memory follows critical memory"); var frozen_memory: Dictionary = survival_memory_session.profile.active_pet.memory.duplicate(true); survival_memory_session.advance_debug(604800, 20.0); eq(survival_memory_session.profile.active_pet.memory, frozen_memory, "dead debug progression freezes memory")
	# A rescue projects care then stabilization at equal timestamp and includes its bonus.
	var rescue_memory = PetGameSessionScript.new(); rescue_memory.balance = BALANCE; rescue_memory.lifecycle = care_session.lifecycle; rescue_memory.care = care_session.care; rescue_memory.survival = SURVIVAL; rescue_memory.relationship_balance = RELATIONSHIP; rescue_memory.memory_config = MEMORY; rescue_memory.profile = fixture(); rescue_memory.profile.active_pet.vitals.hunger = 0.0; rescue_memory.profile.active_pet.vitals.hydration = 0.0; rescue_memory.profile.active_pet.survival = {"condition":"CRITICAL","critical_started_at":1000}; rescue_memory.reanchor(10.0); ok(rescue_memory.care_action("feed", 10.0).ok, "partial rescue feed for memory succeeds"); ok(rescue_memory.care_action("drink", 10.0).ok, "stabilizing drink for memory succeeds"); eq(rescue_memory.profile.active_pet.memory.events[-2].event_type, "pet_drank", "rescue care memory precedes stabilization"); eq(rescue_memory.profile.active_pet.memory.events[-1].event_type, "pet_stabilized", "stabilization memory follows care"); eq(rescue_memory.profile.active_pet.memory.semantic.rescue_count, 1, "rescue semantic count increments once"); eq(rescue_memory.profile.active_pet.relationship.bond, 5.0, "rescue includes independent bond bonus"); eq(rescue_memory.profile.active_pet.relationship.trust, 9.0, "rescue includes independent trust bonus"); eq(rescue_memory.profile.active_pet.relationship.care_experience, 5.0, "rescue includes independent experience bonus")
	# Memorial snapshots preserve final memory/relationship; replacement pet begins isolated.
	_reset(); var isolation_session = PetGameSessionScript.new(); isolation_session.balance = BALANCE; isolation_session.lifecycle = care_session.lifecycle; isolation_session.care = care_session.care; isolation_session.survival = SURVIVAL; isolation_session.relationship_balance = RELATIONSHIP; isolation_session.memory_config = MEMORY; isolation_session.profile = survival_memory_session.profile.duplicate(true); isolation_session.profile.initial_egg_issued = true; ok(LocalSaveRepositoryScript.save_profile(isolation_session.profile), "persist dead pet memory before memorial")
	var pet_a_id := String(isolation_session.profile.active_pet.identity.pet_id); var pet_a_relationship: Dictionary = isolation_session.profile.active_pet.relationship.duplicate(true); var pet_a_memory: Dictionary = isolation_session.profile.active_pet.memory.duplicate(true)
	ok(isolation_session.memorialize_pet(10.0).ok, "memorial preserves Phase 5 pet")
	eq(isolation_session.profile.memorials[-1].pet_snapshot.relationship, pet_a_relationship, "memorial snapshot preserves relationship"); eq(isolation_session.profile.memorials[-1].pet_snapshot.memory, pet_a_memory, "memorial snapshot preserves memory")
	ok(isolation_session.request_new_egg(10.0).ok, "replacement egg starts isolated pet path"); isolation_session.advance_debug(14400, 20.0); ok(isolation_session.begin_hatching(int(isolation_session.profile.simulation.last_simulated_at), 20.0), "replacement hatching begins"); ok(isolation_session.complete_hatching(int(isolation_session.profile.simulation.last_simulated_at), 20.0), "replacement hatching completes")
	ok(String(isolation_session.profile.active_pet.identity.pet_id) != pet_a_id, "replacement pet has new identity"); eq(isolation_session.profile.active_pet.relationship.bond, 0.0, "replacement pet inherits no bond"); eq(isolation_session.profile.active_pet.relationship.trust, 0.0, "replacement pet inherits no trust"); eq(isolation_session.profile.active_pet.relationship.care_experience, 0.0, "replacement pet inherits no care experience"); eq(isolation_session.profile.active_pet.memory.events.size(), 1, "replacement pet starts with hatch memory only")
	isolation_session.free()
	# Phase 5 corrective pass: relationship deltas are actual clamped changes.
	var relationship_model = preload("res://domain/relationship/relationship_model.gd")
	var near_cap := relationship_model.new_relationship(); near_cap.bond = 99.0; near_cap.trust = 99.0
	var clamped_touch: Dictionary = relationship_model.apply_reward(near_cap, "touch", 1000, RELATIONSHIP)
	eq(clamped_touch.relationship.bond, 100.0, "touch clamp reaches bond cap"); eq(clamped_touch.relationship.trust, 100.0, "touch clamp reaches trust cap")
	eq(clamped_touch.deltas.bond, 1.0, "touch reports actual clamped bond delta"); eq(clamped_touch.deltas.trust, 1.0, "touch reports actual clamped trust delta"); eq(clamped_touch.deltas.care_experience, 1.0, "touch reports actual experience delta")
	var relation_clamp_session = PetGameSessionScript.new(); relation_clamp_session.balance = BALANCE; relation_clamp_session.lifecycle = care_session.lifecycle; relation_clamp_session.care = care_session.care; relation_clamp_session.survival = SURVIVAL; relation_clamp_session.relationship_balance = RELATIONSHIP; relation_clamp_session.memory_config = MEMORY; relation_clamp_session.profile = fixture(); relation_clamp_session.profile.active_pet.vitals.mood = 100.0; relation_clamp_session.profile.active_pet.relationship = near_cap; relation_clamp_session.reanchor(10.0)
	ok(relation_clamp_session.care_action("touch", 10.0).ok, "clamped touch succeeds")
	var touch_event: Dictionary = relation_clamp_session.profile.recent_events[-1]; var touch_memory: Dictionary = relation_clamp_session.profile.active_pet.memory.events[-1]
	eq(touch_event.payload.bond_delta, 1.0, "care event records actual bond delta"); eq(touch_event.payload.trust_delta, 1.0, "care event records actual trust delta"); eq(touch_memory.details.bond_delta, 1.0, "care memory records actual bond delta"); eq(touch_memory.details.trust_delta, 1.0, "care memory records actual trust delta")
	# Stabilization carries causal action but creates no second routine occurrence.
	var rescue_clamp = PetGameSessionScript.new(); rescue_clamp.balance = BALANCE; rescue_clamp.lifecycle = care_session.lifecycle; rescue_clamp.care = care_session.care; rescue_clamp.survival = SURVIVAL; rescue_clamp.relationship_balance = RELATIONSHIP; rescue_clamp.memory_config = MEMORY; rescue_clamp.profile = fixture(); rescue_clamp.profile.active_pet.vitals.hydration = 0.0; rescue_clamp.profile.active_pet.survival = {"condition":"CRITICAL","critical_started_at":1000}; rescue_clamp.profile.active_pet.relationship.bond = 96.0; rescue_clamp.profile.active_pet.relationship.trust = 95.0; rescue_clamp.reanchor(10.0)
	ok(rescue_clamp.care_action("drink", 10.0).ok, "critical drink stabilizes")
	var rescue_care_event: Dictionary = rescue_clamp.profile.recent_events[-2]; var rescue_event: Dictionary = rescue_clamp.profile.recent_events[-1]
	eq(rescue_care_event.payload.bond_delta, 1.0, "rescue care event records base actual bond delta"); eq(rescue_care_event.payload.trust_delta, 2.0, "rescue care event records base actual trust delta")
	eq(rescue_event.payload.bond_delta, 3.0, "stabilized event records actual rescue bond delta"); eq(rescue_event.payload.trust_delta, 3.0, "stabilized event records actual rescue trust delta")
	eq(rescue_clamp.profile.active_pet.relationship.bond, 100.0, "rescue clamp reaches bond cap"); eq(rescue_clamp.profile.active_pet.relationship.trust, 100.0, "rescue clamp reaches trust cap")
	eq(rescue_clamp.profile.active_pet.memory.routine.drink.count, 1, "stabilized event does not double count routine drink"); eq(rescue_clamp.profile.active_pet.memory.routine.drink.meaningful_count, 1, "stabilized event does not double count meaningful drink"); eq(rescue_clamp.profile.active_pet.memory.semantic.rescue_count, 1, "stabilized projects one rescue semantic")
	eq(rescue_clamp.profile.active_pet.memory.events[-2].details.bond_delta, 1.0, "rescue care memory retains actual base delta"); eq(rescue_clamp.profile.active_pet.memory.events[-1].details.bond_delta, 3.0, "stabilized memory retains actual rescue delta")
	# Every configured reward action is deterministic and only successful actions reward.
	for action_reward in [["feed",1.0,2.0], ["drink",1.0,2.0], ["wash",1.0,1.0], ["touch",2.0,1.0], ["play",2.0,1.0]]:
		var reward_result: Dictionary = relationship_model.apply_reward(relationship_model.new_relationship(), String(action_reward[0]), 1000, RELATIONSHIP)
		eq(reward_result.deltas.bond, action_reward[1], "%s configured bond reward applies" % action_reward[0]); eq(reward_result.deltas.trust, action_reward[2], "%s configured trust reward applies" % action_reward[0]); eq(reward_result.deltas.care_experience, 1.0, "%s configured experience reward applies" % action_reward[0])
	var low_energy = PetGameSessionScript.new(); low_energy.balance = BALANCE; low_energy.lifecycle = care_session.lifecycle; low_energy.care = care_session.care; low_energy.survival = SURVIVAL; low_energy.relationship_balance = RELATIONSHIP; low_energy.memory_config = MEMORY; low_energy.profile = fixture(); low_energy.profile.active_pet.vitals.energy = 9.0; low_energy.reanchor(10.0)
	var before_low: Dictionary = low_energy.profile.active_pet.duplicate(true); var low_events: Array = low_energy.profile.recent_events.duplicate(true); eq(low_energy.care_action("play", 10.0).reason, "LOW_ENERGY", "low energy play is rejected"); eq(low_energy.profile.active_pet, before_low, "low energy play leaves pet unchanged"); eq(low_energy.profile.recent_events, low_events, "low energy play creates no event")
	# Cooldown retains the care memory but applies zero relationship delta.
	var cooldown_memory: Dictionary = relationship_session.profile.active_pet.memory.events[-2]
	eq(cooldown_memory.details.relationship_rewarded, false, "cooldown memory records no reward"); eq(cooldown_memory.details.bond_delta, 0.0, "cooldown memory has zero bond delta"); eq(relationship_session.profile.active_pet.memory.routine.feed.count, 3, "cooldown action still counts as routine"); eq(relationship_session.profile.active_pet.memory.routine.feed.meaningful_count, 3, "cooldown meaningful care still counts in memory")
	var boundary_relationship := relationship_model.new_relationship(); var boundary_first: Dictionary = relationship_model.apply_reward(boundary_relationship, "feed", 1000, RELATIONSHIP); var boundary_299: Dictionary = relationship_model.apply_reward(boundary_first.relationship, "feed", 1299, RELATIONSHIP); var boundary_300: Dictionary = relationship_model.apply_reward(boundary_first.relationship, "feed", 1300, RELATIONSHIP)
	eq(boundary_299.deltas.bond, 0.0, "reward cooldown rejects 299 seconds"); eq(boundary_300.deltas.bond, 1.0, "reward cooldown accepts 300 seconds")
	# Runtime relationship version governs math, event and projected details atomically.
	eq(version_session.profile.active_pet.memory.events[-1].details.relationship_balance_version, 2, "runtime v2 memory records supplied relationship version")
	var v2_failure = PetGameSessionScript.new(); v2_failure.balance = BALANCE; v2_failure.lifecycle = care_session.lifecycle; v2_failure.care = care_session.care; v2_failure.survival = SURVIVAL; v2_failure.relationship_balance = relation_v2; v2_failure.memory_config = MEMORY; v2_failure.profile = fixture(); v2_failure.profile.active_pet.vitals.hunger = 40.0; v2_failure.reanchor(10.0)
	var v2_before: Dictionary = v2_failure.profile.active_pet.duplicate(true); var v2_events: Array = v2_failure.profile.recent_events.duplicate(true); LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(v2_failure.care_action("feed", 10.0).reason, "PERSIST_FAILED", "runtime v2 failure reports persistence failure"); eq(v2_failure.profile.active_pet, v2_before, "runtime v2 failure preserves vitals relationship and memory"); eq(v2_failure.profile.recent_events, v2_events, "runtime v2 failure creates no authoritative event")
	# A failed normal care candidate and a failed rescue candidate leave every authority unchanged.
	var care_authority = PetGameSessionScript.new(); care_authority.balance = BALANCE; care_authority.lifecycle = care_session.lifecycle; care_authority.care = care_session.care; care_authority.survival = SURVIVAL; care_authority.relationship_balance = RELATIONSHIP; care_authority.memory_config = MEMORY; care_authority.profile = fixture(); care_authority.profile.active_pet.vitals.hunger = 40.0; care_authority.reanchor(10.0)
	var care_before: Dictionary = care_authority.profile.active_pet.duplicate(true); var care_events_before: Array = care_authority.profile.recent_events.duplicate(true); LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(care_authority.care_action("feed", 10.0).reason, "PERSIST_FAILED", "failed care reports persistence failure"); eq(care_authority.profile.active_pet, care_before, "failed care leaves authoritative pet unchanged"); eq(care_authority.profile.recent_events, care_events_before, "failed care leaves authoritative events unchanged")
	var rescue_authority = PetGameSessionScript.new(); rescue_authority.balance = BALANCE; rescue_authority.lifecycle = care_session.lifecycle; rescue_authority.care = care_session.care; rescue_authority.survival = SURVIVAL; rescue_authority.relationship_balance = RELATIONSHIP; rescue_authority.memory_config = MEMORY; rescue_authority.profile = fixture(); rescue_authority.profile.active_pet.vitals.hydration = 0.0; rescue_authority.profile.active_pet.survival = {"condition":"CRITICAL","critical_started_at":1000}; rescue_authority.reanchor(10.0)
	var rescue_before: Dictionary = rescue_authority.profile.active_pet.duplicate(true); var rescue_events_before: Array = rescue_authority.profile.recent_events.duplicate(true); LocalSaveRepositoryScript.test_fail_next_primary_replace = true
	eq(rescue_authority.care_action("drink", 10.0).reason, "PERSIST_FAILED", "failed rescue reports persistence failure"); eq(rescue_authority.profile.active_pet, rescue_before, "failed rescue leaves critical pet unchanged"); eq(rescue_authority.profile.recent_events, rescue_events_before, "failed rescue leaves events unchanged")
	# Memory validator rejects fractional/incomplete values rather than coercing them.
	var valid_memory_profile := fixture(); ok(DomainStateScript.validate_profile(valid_memory_profile), "valid empty memory validates")
	var invalid_memory_pet: Dictionary = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.next_sequence = 1.5; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "fractional next sequence rejected")
	invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.events = [{"memory_id":"memory:a","source_event_id":"evt:a","sequence":1.5,"event_type":"pet_fed","occurred_at":1000,"category":"CARE","valence":1,"importance":1,"details":{}}]; invalid_memory_pet.memory.next_sequence = 2; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "fractional record sequence rejected")
	for invalid_field in [["valence", 1.5], ["importance", 1.5], ["occurred_at", 1.5], ["details", []], ["category", "UNKNOWN"]]:
		invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.events = [{"memory_id":"memory:a","source_event_id":"evt:a","sequence":0,"event_type":"pet_fed","occurred_at":1000,"category":"CARE","valence":1,"importance":1,"details":{}}]; invalid_memory_pet.memory.events[0][invalid_field[0]] = invalid_field[1]; invalid_memory_pet.memory.next_sequence = 1; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "memory field %s invalid type/value rejected" % invalid_field[0])
	invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.events = [{"memory_id":"memory:a","source_event_id":"evt:a","sequence":1,"event_type":"pet_fed","occurred_at":1000,"category":"CARE","valence":1,"importance":1,"details":{}}, {"memory_id":"memory:b","source_event_id":"evt:a","sequence":2,"event_type":"pet_fed","occurred_at":1001,"category":"CARE","valence":1,"importance":1,"details":{}}]; invalid_memory_pet.memory.next_sequence = 3; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "duplicate memory source rejected")
	invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.events = [{"memory_id":"memory:a","source_event_id":"evt:a","sequence":1,"event_type":"pet_fed","occurred_at":1000,"category":"CARE","valence":1,"importance":1,"details":{}}, {"memory_id":"memory:a","source_event_id":"evt:b","sequence":2,"event_type":"pet_fed","occurred_at":1001,"category":"CARE","valence":1,"importance":1,"details":{}}]; invalid_memory_pet.memory.next_sequence = 3; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "duplicate memory id rejected")
	invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.routine.feed.meaningful_count = 1; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "routine meaningful count cannot exceed count")
	invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.routine.feed.meaningful_count = -1; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "negative routine meaningful count rejected")
	for semantic_key in ["care_interaction_count", "critical_count"]:
		invalid_memory_pet = valid_memory_profile.active_pet.duplicate(true); invalid_memory_pet.memory.semantic[semantic_key] = -1; ok(not DomainStateScript.validate_pet(invalid_memory_pet), "negative semantic %s rejected" % semantic_key)
	# Exact views, dedupe, priority eviction and lifetime sequence are deterministic.
	var view_memory: Dictionary = memory_model.new_memory()
	for view_index in range(10): view_memory = memory_model.project(view_memory, {"event_id":"evt:view:%d" % view_index,"event_type":"pet_fed","occurred_at":view_index,"payload":{"meaningful":true}}, MEMORY)
	var working: Array = memory_model.working_memory(view_memory, MEMORY); eq(working.size(), 8, "working memory uses exact configured window"); eq(working[0].sequence, 2, "working memory starts at latest retained eighth record"); eq(working[-1].sequence, 9, "working memory ends at latest sequence")
	var exact_views := memory_model.new_memory(); exact_views = memory_model.project(exact_views, {"event_id":"evt:i0","event_type":"pet_sleep_started","occurred_at":0,"payload":{}}, MEMORY); exact_views = memory_model.project(exact_views, {"event_id":"evt:i3","event_type":"pet_became_critical","occurred_at":1,"payload":{}}, MEMORY); exact_views = memory_model.project(exact_views, {"event_id":"evt:i4","event_type":"pet_hatched","occurred_at":2,"payload":{}}, MEMORY)
	eq(memory_model.episodic_memory(exact_views, MEMORY).size(), 2, "episodic returns only importance three and four"); eq(memory_model.emotional_memory(exact_views).size(), 2, "emotional returns only non-neutral values")
	var dedupe_before: Dictionary = exact_views.duplicate(true); exact_views = memory_model.project(exact_views, {"event_id":"evt:i3","event_type":"pet_became_critical","occurred_at":1,"payload":{}}, MEMORY); eq(exact_views, dedupe_before, "duplicate memory projection changes nothing")
	var priority_memory := memory_model.new_memory(); priority_memory = memory_model.project(priority_memory, {"event_id":"evt:hatch:high","event_type":"pet_hatched","occurred_at":0,"payload":{}}, MEMORY); priority_memory = memory_model.project(priority_memory, {"event_id":"evt:critical:high","event_type":"pet_became_critical","occurred_at":1,"payload":{}}, MEMORY)
	for priority_index in range(64): priority_memory = memory_model.project(priority_memory, {"event_id":"evt:low:%d" % priority_index,"event_type":"pet_sleep_started","occurred_at":priority_index + 2,"payload":{}}, MEMORY)
	ok(_has_memory_source(priority_memory.events, "evt:hatch:high") and _has_memory_source(priority_memory.events, "evt:critical:high"), "eviction preserves high importance memories"); eq(priority_memory.next_sequence, 66, "eviction sequence remains lifetime monotonic"); priority_memory = memory_model.project(priority_memory, {"event_id":"evt:after-eviction","event_type":"pet_sleep_started","occurred_at":100,"payload":{}}, MEMORY); eq(priority_memory.events[-1].sequence, 66, "new memory never reuses evicted sequence")
	# Relationship validation has no coercion or hidden negative state.
	for relationship_invalid in [["bond", -1.0], ["bond", 101.0], ["trust", -1.0], ["trust", 101.0], ["care_experience", -1.0], ["relationship_version", 2], ["relationship_balance_version", 0], ["last_rewarded_at", "bad"]]:
		var invalid_relationship_pet: Dictionary = fixture().active_pet
		if relationship_invalid[0] == "last_rewarded_at": invalid_relationship_pet.relationship.last_rewarded_at = relationship_invalid[1]
		else: invalid_relationship_pet.relationship[relationship_invalid[0]] = relationship_invalid[1]
		ok(not DomainStateScript.validate_pet(invalid_relationship_pet), "invalid relationship %s is rejected" % relationship_invalid[0])
	var timestamp_relationship_pet: Dictionary = fixture().active_pet; timestamp_relationship_pet.relationship.last_rewarded_at.feed = "1000"; ok(not DomainStateScript.validate_pet(timestamp_relationship_pet), "string relationship timestamp rejected"); timestamp_relationship_pet.relationship.last_rewarded_at.feed = null; ok(DomainStateScript.validate_pet(timestamp_relationship_pet), "null relationship timestamp valid"); timestamp_relationship_pet.relationship.last_rewarded_at.feed = 1000; ok(DomainStateScript.validate_pet(timestamp_relationship_pet), "integer relationship timestamp valid")
	# Complete memory state validation: identity, ordering, ranges, projections and cap.
	var populated_memory_pet: Dictionary = fixture().active_pet; populated_memory_pet.memory.events = [{"memory_id":"memory:one","source_event_id":"evt:one","sequence":4,"event_type":"pet_fed","occurred_at":1000,"category":"CARE","valence":1,"importance":1,"details":{}}]; populated_memory_pet.memory.next_sequence = 5; ok(DomainStateScript.validate_pet(populated_memory_pet), "valid populated memory validates")
	for memory_case in [["memory_id", ""], ["source_event_id", ""], ["event_type", ""], ["sequence", -1], ["sequence", 1.5], ["occurred_at", "bad"], ["category", "BAD"], ["valence", 2], ["valence", 0.5], ["importance", -1], ["importance", 5], ["importance", 1.5], ["details", []]]:
		var malformed_memory_pet: Dictionary = populated_memory_pet.duplicate(true); malformed_memory_pet.memory.events[0][memory_case[0]] = memory_case[1]; ok(not DomainStateScript.validate_pet(malformed_memory_pet), "malformed memory %s rejected" % memory_case[0])
	var sequence_memory_pet: Dictionary = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.next_sequence = 4; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "next sequence must exceed retained sequence")
	sequence_memory_pet = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.events.append({"memory_id":"memory:two","source_event_id":"evt:two","sequence":3,"event_type":"pet_fed","occurred_at":1001,"category":"CARE","valence":1,"importance":1,"details":{}}); sequence_memory_pet.memory.next_sequence = 5; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "memory sequence must be strictly increasing")
	sequence_memory_pet = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.routine.feed.count = -1; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "negative routine count rejected")
	sequence_memory_pet = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.routine.feed.last_at = "bad"; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "invalid routine timestamp rejected")
	sequence_memory_pet = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.semantic.rescue_count = -1; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "negative semantic count rejected")
	sequence_memory_pet = populated_memory_pet.duplicate(true); sequence_memory_pet.memory.semantic.favorite_interaction = "unknown"; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "invalid favorite interaction rejected")
	sequence_memory_pet = fixture().active_pet
	for cap_index in range(65): sequence_memory_pet.memory.events.append({"memory_id":"memory:cap:%d" % cap_index,"source_event_id":"evt:cap:%d" % cap_index,"sequence":cap_index,"event_type":"pet_fed","occurred_at":cap_index,"category":"CARE","valence":1,"importance":1,"details":{}})
	sequence_memory_pet.memory.next_sequence = 65; ok(not DomainStateScript.validate_pet(sequence_memory_pet), "memory store over limit rejected")
	# Sleep/wake are neutral routine memories with no relationship change.
	var sleep_memory_session = PetGameSessionScript.new(); sleep_memory_session.balance = BALANCE; sleep_memory_session.lifecycle = care_session.lifecycle; sleep_memory_session.care = care_session.care; sleep_memory_session.survival = SURVIVAL; sleep_memory_session.relationship_balance = RELATIONSHIP; sleep_memory_session.memory_config = MEMORY; sleep_memory_session.profile = fixture(); sleep_memory_session.reanchor(10.0)
	var sleep_relationship_before: Dictionary = sleep_memory_session.profile.active_pet.relationship.duplicate(true); ok(sleep_memory_session.care_action("sleep", 10.0).ok, "sleep projects routine memory"); eq(sleep_memory_session.profile.active_pet.memory.events[-1].event_type, "pet_sleep_started", "sleep event projects memory"); eq(sleep_memory_session.profile.active_pet.memory.events[-1].valence, 0, "sleep memory neutral"); eq(sleep_memory_session.profile.active_pet.memory.routine.sleep.count, 1, "sleep increments routine once"); eq(sleep_memory_session.profile.active_pet.relationship, sleep_relationship_before, "sleep changes no relationship"); ok(sleep_memory_session.care_action("wake", 10.0).ok, "wake projects routine memory"); eq(sleep_memory_session.profile.active_pet.memory.events[-1].event_type, "pet_woke", "wake event projects memory"); eq(sleep_memory_session.profile.active_pet.memory.routine.wake.count, 1, "wake increments routine once")
	# Schema-v5 egg/memorial migration retains lifecycle reservations and never backfills memory.
	for egg_state in ["INCUBATING", "READY", "HATCHING"]:
		var v5_egg_profile := DomainStateScript.new_profile("v5:%s" % egg_state, 1000); v5_egg_profile.schema_version = 5; v5_egg_profile.active_subject = "EGG"; v5_egg_profile.active_egg = DomainStateScript.new_egg("egg:v5:%s" % egg_state, 1000, 15400); v5_egg_profile.active_egg.schema_version = 5; v5_egg_profile.active_egg.state = egg_state
		if egg_state == "HATCHING": v5_egg_profile.active_egg.reserved_pet_id = "pet:v5:reserved"; v5_egg_profile.active_egg.reserved_pet_seed = 77; v5_egg_profile.active_egg.hatching_started_at = 15400
		var migrated_v5_egg: Dictionary = SaveMigratorScript.migrate(v5_egg_profile); eq(migrated_v5_egg.schema_version, 7, "v5 %s root migrates v7" % egg_state); eq(migrated_v5_egg.active_egg.state, egg_state, "v5 %s egg state preserved" % egg_state); eq(migrated_v5_egg.active_egg.egg_id, v5_egg_profile.active_egg.egg_id, "v5 %s egg identity preserved" % egg_state)
		if egg_state == "HATCHING": eq(migrated_v5_egg.active_egg.reserved_pet_id, "pet:v5:reserved", "v5 hatching reservation preserved")
	# Read actual centralized configuration rather than test-only copies.
	var relationship_config_file := FileAccess.open("res://data/balance/relationship_v1.json", FileAccess.READ); var relationship_file_config: Dictionary = JSON.parse_string(relationship_config_file.get_as_text()); relationship_config_file.close(); var memory_config_file := FileAccess.open("res://data/config/memory_v1.json", FileAccess.READ); var memory_file_config: Dictionary = JSON.parse_string(memory_config_file.get_as_text()); memory_config_file.close()
	eq(relationship_file_config.relationship_balance_version, 1.0, "relationship config declares v1"); eq(relationship_file_config.reward_cooldown_seconds, 300.0, "relationship config declares cooldown"); eq(relationship_file_config.rewards.touch.bond, 2.0, "relationship config declares touch reward"); eq(relationship_file_config.rescue.trust, 5.0, "relationship config declares rescue reward"); eq(memory_file_config.memory_version, 1.0, "memory config declares v1"); eq(memory_file_config.event_store_limit, 64.0, "memory config declares event cap"); eq(memory_file_config.working_memory_limit, 8.0, "memory config declares window"); eq(memory_file_config.episodic_min_importance, 3.0, "memory config declares episodic threshold")
	# Phase 5 corrective pass 2: strict version validation and exact JSON canonicalization.
	for memory_version_case in [1, 1.5, "1", true, 2, null]:
		var memory_version_pet: Dictionary = fixture().active_pet; memory_version_pet.memory.memory_version = memory_version_case; eq(DomainStateScript.validate_pet(memory_version_pet), memory_version_case is int and memory_version_case == 1, "memory version strict validation for %s" % str(memory_version_case))
	var whole_external := fixture(); whole_external.active_pet.memory.memory_version = 1.0; whole_external.active_pet.memory.next_sequence = 1.0; whole_external.active_pet.memory.events = [{"memory_id":"memory:whole","source_event_id":"evt:whole","sequence":0.0,"event_type":"pet_fed","occurred_at":1000.0,"category":"CARE","valence":1.0,"importance":1.0,"details":{}}]; whole_external.active_pet.memory.routine.feed = {"count":1.0,"meaningful_count":1.0,"last_at":1000.0}; whole_external.active_pet.memory.semantic.care_interaction_count = 1.0; whole_external.active_pet.relationship.relationship_version = 1.0; whole_external.active_pet.relationship.relationship_balance_version = 1.0; whole_external.active_pet.relationship.last_rewarded_at.feed = 1000.0
	var canonical_whole: Dictionary = SaveMigratorScript.migrate(whole_external); ok(DomainStateScript.validate_profile(canonical_whole), "exact whole JSON values canonicalize to valid profile"); ok(canonical_whole.active_pet.memory.memory_version is int and canonical_whole.active_pet.memory.next_sequence is int and canonical_whole.active_pet.memory.events[0].sequence is int and canonical_whole.active_pet.memory.events[0].occurred_at is int and canonical_whole.active_pet.memory.events[0].valence is int and canonical_whole.active_pet.memory.events[0].importance is int, "whole memory floats become integer authoritative fields"); ok(canonical_whole.active_pet.relationship.relationship_version is int and canonical_whole.active_pet.relationship.last_rewarded_at.feed is int, "whole relationship metadata canonicalizes")
	for fractional_value in [1.5, 1.000001, -0.000001]:
		var fractional_external := fixture(); fractional_external.active_pet.memory.next_sequence = fractional_value; var canonical_fractional: Dictionary = SaveMigratorScript.migrate(fractional_external); eq(canonical_fractional.active_pet.memory.next_sequence, fractional_value, "fractional %s is never canonicalized" % str(fractional_value)); ok(not DomainStateScript.validate_profile(canonical_fractional), "fractional %s fails validation after migration" % str(fractional_value)); ok(not LocalSaveRepositoryScript.save_profile(canonical_fractional), "fractional %s cannot save" % str(fractional_value))
	# Repository JSON round-trip restores strict integer contract fields.
	_reset(); var round_trip_profile: Dictionary = canonical_whole.duplicate(true); ok(LocalSaveRepositoryScript.save_profile(round_trip_profile), "strict integer memory fixture saves"); var loaded_round_trip: Dictionary = LocalSaveRepositoryScript.load_profile(); ok(DomainStateScript.validate_profile(loaded_round_trip), "strict integer memory fixture loads valid"); var loaded_memory: Dictionary = loaded_round_trip.active_pet.memory; ok(loaded_memory.memory_version is int and loaded_memory.next_sequence is int and loaded_memory.events[0].sequence is int and loaded_memory.events[0].occurred_at is int and loaded_memory.events[0].valence is int and loaded_memory.events[0].importance is int and loaded_memory.routine.feed.count is int and loaded_memory.routine.feed.meaningful_count is int and loaded_memory.semantic.care_interaction_count is int, "round-trip restores integer memory fields"); ok(loaded_round_trip.active_pet.relationship.relationship_version is int and loaded_round_trip.active_pet.relationship.relationship_balance_version is int and loaded_round_trip.active_pet.relationship.last_rewarded_at.feed is int, "round-trip restores integer relationship metadata")
	# Application-level survival projection is chunking-equivalent and exactly once.
	var survival_long = PetGameSessionScript.new(); survival_long.balance = BALANCE; survival_long.lifecycle = care_session.lifecycle; survival_long.care = care_session.care; survival_long.survival = SURVIVAL; survival_long.relationship_balance = RELATIONSHIP; survival_long.memory_config = MEMORY; survival_long.profile = death.duplicate(true); survival_long.advance_in_memory_to(11800)
	var survival_chunks = PetGameSessionScript.new(); survival_chunks.balance = BALANCE; survival_chunks.lifecycle = care_session.lifecycle; survival_chunks.care = care_session.care; survival_chunks.survival = SURVIVAL; survival_chunks.relationship_balance = RELATIONSHIP; survival_chunks.memory_config = MEMORY; survival_chunks.profile = death.duplicate(true); survival_chunks.advance_in_memory_to(4600); survival_chunks.advance_in_memory_to(8200); survival_chunks.advance_in_memory_to(11800)
	var long_survival: Array = _memory_events_by_types(survival_long.profile.active_pet.memory.events, ["pet_became_critical", "pet_died"]); var chunked_survival: Array = _memory_events_by_types(survival_chunks.profile.active_pet.memory.events, ["pet_became_critical", "pet_died"]); eq(long_survival, chunked_survival, "application survival memory chunking is deterministic"); eq(survival_long.profile.active_pet.life, survival_chunks.profile.active_pet.life, "application chunking preserves final death metadata"); eq(long_survival[0].event_type, "pet_became_critical", "critical memory precedes death memory"); eq(long_survival[1].event_type, "pet_died", "death memory follows critical memory"); eq(long_survival[1].category, "SURVIVAL", "death memory category"); eq(long_survival[1].importance, 4, "death memory importance"); eq(long_survival[1].valence, -1, "death memory valence"); eq(long_survival[1].details.death_cause, survival_long.profile.active_pet.life.death_cause, "death memory records cause"); eq(long_survival[1].details.died_at, survival_long.profile.active_pet.life.died_at, "death memory records timestamp")
	var critical_only = PetGameSessionScript.new(); critical_only.balance = BALANCE; critical_only.lifecycle = care_session.lifecycle; critical_only.care = care_session.care; critical_only.survival = SURVIVAL; critical_only.relationship_balance = RELATIONSHIP; critical_only.memory_config = MEMORY; critical_only.profile = critical.duplicate(true); critical_only.advance_in_memory_to(10000); var first_critical_memories: Array = _memory_events_by_types(critical_only.profile.active_pet.memory.events, ["pet_became_critical"]); critical_only.advance_in_memory_to(11000); var continued_critical_memories: Array = _memory_events_by_types(critical_only.profile.active_pet.memory.events, ["pet_became_critical"]); eq(first_critical_memories.size(), 1, "application critical projects one memory"); eq(continued_critical_memories.size(), 1, "continued critical creates no duplicate memory"); eq(continued_critical_memories[0], first_critical_memories[0], "critical memory identity remains stable")
	# Equal importance eviction removes the oldest sequence deterministically.
	var equal_priority_memory := memory_model.new_memory()
	for equal_index in range(64): equal_priority_memory = memory_model.project(equal_priority_memory, {"event_id":"evt:equal:%d" % equal_index,"event_type":"pet_sleep_started","occurred_at":equal_index,"payload":{}}, MEMORY)
	equal_priority_memory = memory_model.project(equal_priority_memory, {"event_id":"evt:equal:new","event_type":"pet_sleep_started","occurred_at":64,"payload":{}}, MEMORY); ok(not _has_memory_source(equal_priority_memory.events, "evt:equal:0"), "equal-importance eviction removes oldest record"); ok(_has_memory_source(equal_priority_memory.events, "evt:equal:1") and _has_memory_source(equal_priority_memory.events, "evt:equal:new"), "equal-importance eviction keeps newer records")
	# Favorite ties retain chronology until one action is strictly ahead.
	var favorite_memory := memory_model.new_memory(); favorite_memory = memory_model.project(favorite_memory, {"event_id":"evt:favorite:feed","event_type":"pet_fed","occurred_at":1,"payload":{"meaningful":true}}, MEMORY); eq(favorite_memory.semantic.favorite_interaction, "feed", "first meaningful feed is favorite"); favorite_memory = memory_model.project(favorite_memory, {"event_id":"evt:favorite:touch-one","event_type":"pet_touched","occurred_at":2,"payload":{"meaningful":true}}, MEMORY); eq(favorite_memory.semantic.favorite_interaction, "feed", "favorite tie preserves earlier feed"); favorite_memory = memory_model.project(favorite_memory, {"event_id":"evt:favorite:touch-two","event_type":"pet_touched","occurred_at":3,"payload":{"meaningful":true}}, MEMORY); eq(favorite_memory.semantic.favorite_interaction, "touch", "strictly higher touch becomes favorite")
	# Passive simulation never mutates relationship, including sleep/offline time.
	var invariant_session = PetGameSessionScript.new(); invariant_session.balance = BALANCE; invariant_session.lifecycle = care_session.lifecycle; invariant_session.care = care_session.care; invariant_session.survival = SURVIVAL; invariant_session.relationship_balance = RELATIONSHIP; invariant_session.memory_config = MEMORY; invariant_session.profile = fixture(); invariant_session.profile.active_pet.life.newborn_protection_until = 999999999; invariant_session.profile.active_pet.relationship.bond = 7.0; invariant_session.profile.active_pet.relationship.trust = 8.0; invariant_session.profile.active_pet.relationship.care_experience = 9.0; invariant_session.profile.active_pet.relationship.last_rewarded_at.feed = 1000; invariant_session.reanchor(10.0); var invariant_relationship: Dictionary = invariant_session.profile.active_pet.relationship.duplicate(true); invariant_session.advance_debug(86400, 20.0); eq(invariant_session.profile.active_pet.relationship, invariant_relationship, "one day passive progression preserves relationship"); invariant_session.advance_debug(604800, 30.0); eq(invariant_session.profile.active_pet.relationship, invariant_relationship, "seven day passive progression preserves relationship"); invariant_session.profile.active_pet.activity = {"state":"SLEEPING","sleep_started_at":int(invariant_session.profile.simulation.last_simulated_at)}; invariant_session.resume_at(int(invariant_session.profile.simulation.last_simulated_at) + 3600, 40.0); eq(invariant_session.profile.active_pet.relationship, invariant_relationship, "sleep offline reconciliation preserves relationship")
	# Schema-v5 migration preserves raw history without projecting it into memory.
	var v5_no_backfill := fixture(); v5_no_backfill.schema_version = 5; v5_no_backfill.active_pet.schema_version = 5; v5_no_backfill.active_pet.erase("memory"); v5_no_backfill.active_pet.relationship = {"bond":12.0,"trust":13.0,"care_experience":14.0}; v5_no_backfill.recent_events = [{"event_id":"evt:old-feed","event_type":"pet_fed"},{"event_id":"evt:old-touch","event_type":"pet_touched"},{"event_id":"evt:old-critical","event_type":"pet_became_critical"}]; var migrated_no_backfill: Dictionary = SaveMigratorScript.migrate(v5_no_backfill); eq(migrated_no_backfill.recent_events, v5_no_backfill.recent_events, "v5 raw recent events are preserved"); eq(migrated_no_backfill.active_pet.relationship.bond, 12.0, "v5 relationship numbers preserved"); eq(migrated_no_backfill.active_pet.memory.events, [], "v5 events do not backfill raw memories"); eq(migrated_no_backfill.active_pet.memory.routine.feed.count, 0, "v5 events do not backfill routine"); eq(migrated_no_backfill.active_pet.memory.semantic.care_interaction_count, 0, "v5 events do not backfill semantic summary")
	# A true v5 HATCHING reservation completes as exactly the reserved v6 pet.
	var v5_hatching_profile := DomainStateScript.new_profile("v5:hatching:completion", 1000); v5_hatching_profile.schema_version = 5; v5_hatching_profile.active_subject = "EGG"; v5_hatching_profile.active_egg = DomainStateScript.new_egg("egg:v5:completion", 1000, 15400); v5_hatching_profile.active_egg.schema_version = 5; v5_hatching_profile.active_egg.state = "HATCHING"; v5_hatching_profile.active_egg.reserved_pet_id = "pet:v5:completion"; v5_hatching_profile.active_egg.reserved_pet_seed = 23; v5_hatching_profile.active_egg.hatching_started_at = 15400; var migrated_v5_hatching: Dictionary = SaveMigratorScript.migrate(v5_hatching_profile); eq(migrated_v5_hatching.active_egg.reserved_pet_seed, 23, "v5 hatching seed preserved"); eq(migrated_v5_hatching.active_egg.hatching_started_at, 15400, "v5 hatching start preserved"); var v5_hatch_session = PetGameSessionScript.new(); v5_hatch_session.balance = BALANCE; v5_hatch_session.lifecycle = care_session.lifecycle; v5_hatch_session.care = care_session.care; v5_hatch_session.survival = SURVIVAL; v5_hatch_session.relationship_balance = RELATIONSHIP; v5_hatch_session.memory_config = MEMORY; v5_hatch_session.profile = migrated_v5_hatching; ok(v5_hatch_session.complete_hatching(16000, 10.0), "migrated v5 hatching completes"); eq(v5_hatch_session.profile.active_pet.identity.pet_id, "pet:v5:completion", "v5 hatching uses exact reservation"); eq(v5_hatch_session.profile.active_pet.schema_version, 7, "v5 hatching creates v7 pet"); eq(v5_hatch_session.profile.active_pet.relationship.bond, 0.0, "v5 hatching pet starts new relationship"); eq(v5_hatch_session.profile.active_pet.memory.events.size(), 1, "v5 hatching pet starts one hatch memory")
	var v5_memorial_profile := DomainStateScript.new_profile("v5:memorial:no-backfill", 1000); v5_memorial_profile.schema_version = 5; v5_memorial_profile.memorial_count = 1; var v5_dead_snapshot: Dictionary = valid_dead.duplicate(true); v5_dead_snapshot.schema_version = 5; v5_dead_snapshot.erase("memory"); v5_dead_snapshot.relationship = {"bond":21.0,"trust":22.0,"care_experience":23.0}; v5_memorial_profile.memorials = [{"schema_version":1,"memorial_id":"memorial:v5:no-backfill","memorialized_at":9000,"pet_snapshot":v5_dead_snapshot}]; v5_memorial_profile.recent_events = [{"event_id":"evt:old-death","event_type":"pet_died"}]; var migrated_v5_memorial: Dictionary = SaveMigratorScript.migrate(v5_memorial_profile); eq(migrated_v5_memorial.recent_events, v5_memorial_profile.recent_events, "v5 memorial profile events are preserved"); eq(migrated_v5_memorial.memorials[0].pet_snapshot.relationship.trust, 22.0, "v5 memorial relationship preserved"); eq(migrated_v5_memorial.memorials[0].pet_snapshot.memory.events, [], "v5 memorial receives no memory backfill"); eq(migrated_v5_memorial.memorials[0].pet_snapshot.memory.semantic.critical_count, 0, "v5 memorial semantic stays empty")
	# Views have exact ordering/source content and cannot mutate stored memory.
	var views_before: Dictionary = exact_views.duplicate(true)
	var exact_working_sources: Array = []
	for working_event in working:
		exact_working_sources.append(working_event.source_event_id)
	eq(exact_working_sources, ["evt:view:2","evt:view:3","evt:view:4","evt:view:5","evt:view:6","evt:view:7","evt:view:8","evt:view:9"], "working view returns exact latest source IDs")
	var episodic_sources: Array = []
	for episodic_event in memory_model.episodic_memory(exact_views, MEMORY):
		episodic_sources.append(episodic_event.source_event_id)
	eq(episodic_sources, ["evt:i3","evt:i4"], "episodic view returns exact source ordering")
	var emotional_sources: Array = []
	for emotional_event in memory_model.emotional_memory(exact_views):
		emotional_sources.append(emotional_event.source_event_id)
	eq(emotional_sources, ["evt:i3","evt:i4"], "emotional view returns exact source ordering")
	memory_model.working_memory(exact_views, MEMORY); memory_model.episodic_memory(exact_views, MEMORY); memory_model.emotional_memory(exact_views)
	eq(exact_views, views_before, "memory views are pure queries")
	# Inspector relationship/memory data is read-only and does not rebuild care controls.
	var memory_ui = FoundationScreenScript.new(); memory_ui.session_override = relationship_session; memory_ui._ready(); var memory_feed := memory_ui.lifecycle_button("Feed"); var memory_rebuilds: int = memory_ui.lifecycle_rebuild_count; var inspector_before: String = String(memory_ui.inspector.text); memory_ui.refresh(); ok(memory_ui.inspector.text.contains("Bond:") and memory_ui.inspector.text.contains("Trust:") and memory_ui.inspector.text.contains("Care Experience:") and memory_ui.inspector.text.contains("Memory Events:") and memory_ui.inspector.text.contains("Favorite Interaction:") and memory_ui.inspector.text.contains("Last Memory:"), "inspector displays all relationship and memory fields"); eq(memory_ui.lifecycle_button("Feed"), memory_feed, "relationship/memory refresh preserves feed control"); eq(memory_ui.lifecycle_rebuild_count, memory_rebuilds, "relationship/memory changes do not rebuild controls")
	relationship_session.profile.active_pet.vitals.hunger = 40.0; ok(relationship_session.care_action("feed", 620.0).ok, "meaningful feed updates inspector data"); memory_ui.refresh(); eq(memory_ui.lifecycle_button("Feed"), memory_feed, "care-time UI refresh preserves feed button"); eq(memory_ui.lifecycle_rebuild_count, memory_rebuilds, "care-time UI refresh does not rebuild lifecycle controls"); ok(memory_ui.inspector.text != inspector_before and memory_ui.inspector.text.contains("Last Memory: pet_fed"), "care-time inspector reflects new memory"); var read_only_relationship: Dictionary = relationship_session.profile.active_pet.relationship.duplicate(true); var read_only_memory: Dictionary = relationship_session.profile.active_pet.memory.duplicate(true); memory_ui.refresh(); memory_ui.refresh(); eq(relationship_session.profile.active_pet.relationship, read_only_relationship, "presentation refresh cannot mutate relationship"); eq(relationship_session.profile.active_pet.memory, read_only_memory, "presentation refresh cannot mutate memory")
	# Phase 6: deterministic, absolute-age growth. Growth stays pure and all
	# application-visible state is projected through the ordinary simulation path.
	var GROWTH: Dictionary = DefaultGrowthBalanceScript.load_config()
	eq(GROWTH.growth_balance_version, 1, "growth config version is v1"); eq(GROWTH.child_age_seconds, 172800, "growth config child threshold"); eq(GROWTH.adolescent_age_seconds, 604800, "growth config adolescent threshold"); eq(GROWTH.adult_age_seconds, 1814400, "growth config adult threshold"); ok(int(GROWTH.child_age_seconds) < int(GROWTH.adolescent_age_seconds) and int(GROWTH.adolescent_age_seconds) < int(GROWTH.adult_age_seconds), "growth thresholds are strictly increasing")
	eq(none.simulation.simulation_version, 6, "new profile uses simulation v6"); eq(none.simulation.growth_balance_version, 1, "new profile records growth balance version"); eq(p.active_pet.schema_version, 7, "new pet uses schema v7"); eq(p.active_pet.life.growth_stage, "NEWBORN", "new pet starts newborn"); eq(p.active_pet.growth.stage_started_at, p.active_pet.identity.born_at, "newborn growth starts at birth"); ok(DomainStateScript.validate_pet(p.active_pet), "new pet growth metadata validates")
	var growth_validation: Dictionary = p.active_pet.duplicate(true)
	for invalid_growth in [
		func(x): x.erase("growth"),
		func(x): x.growth.erase("growth_version"),
		func(x): x.growth.growth_version = 2,
		func(x): x.growth.growth_version = 1.5,
		func(x): x.growth.growth_balance_version = 0,
		func(x): x.growth.growth_balance_version = "1",
		func(x): x.growth.erase("stage_started_at"),
		func(x): x.growth.stage_started_at = 1000.0,
		func(x): x.growth.stage_started_at = 999
	]:
		var malformed_growth: Dictionary = growth_validation.duplicate(true); invalid_growth.call(malformed_growth); ok(not DomainStateScript.validate_pet(malformed_growth), "malformed growth metadata is rejected")
	var boundary_pet: Dictionary = fixture(); boundary_pet.active_pet.life.newborn_protection_until = 999999999
	var growth_before: Dictionary = SimulationKernelScript.simulate(boundary_pet, 1000, 173799, BALANCE, {}, {}, {}, GROWTH)
	eq(growth_before.new_state.active_pet.life.growth_stage, "NEWBORN", "one second before child remains newborn"); ok(not _has_event(growth_before.generated_events, "pet_grew"), "one second before child has no growth event")
	var growth_child: Dictionary = SimulationKernelScript.simulate(boundary_pet, 1000, 173800, BALANCE, {}, {}, {}, GROWTH)
	eq(growth_child.new_state.active_pet.life.growth_stage, "CHILD", "exact child threshold advances stage"); eq(growth_child.new_state.active_pet.growth.stage_started_at, 173800, "child transition has canonical timestamp"); var child_growth: Array = _events_by_type(growth_child.generated_events, "pet_grew"); eq(child_growth.size(), 1, "child transition emits one event"); eq(child_growth[0].payload, {"from_stage":"NEWBORN","to_stage":"CHILD","stage_started_at":173800,"growth_balance_version":1}, "child event payload is complete")
	var adolescent_source: Dictionary = growth_child.new_state
	eq(SimulationKernelScript.simulate(adolescent_source, 173800, 605799, BALANCE, {}, {}, {}, GROWTH).new_state.active_pet.life.growth_stage, "CHILD", "one second before adolescent remains child"); eq(SimulationKernelScript.simulate(adolescent_source, 173800, 605800, BALANCE, {}, {}, {}, GROWTH).new_state.active_pet.life.growth_stage, "ADOLESCENT", "exact adolescent threshold advances stage")
	var adult_source: Dictionary = SimulationKernelScript.simulate(adolescent_source, 173800, 605800, BALANCE, {}, {}, {}, GROWTH).new_state
	eq(SimulationKernelScript.simulate(adult_source, 605800, 1815399, BALANCE, {}, {}, {}, GROWTH).new_state.active_pet.life.growth_stage, "ADOLESCENT", "one second before adult remains adolescent"); var adult_result: Dictionary = SimulationKernelScript.simulate(adult_source, 605800, 1815400, BALANCE, {}, {}, {}, GROWTH); eq(adult_result.new_state.active_pet.life.growth_stage, "ADULT", "exact adult threshold advances stage"); ok(not _has_event(SimulationKernelScript.simulate(adult_result.new_state, 1815400, 1815400 + 365 * 86400, BALANCE, {}, {}, {}, GROWTH).generated_events, "pet_grew"), "adult is terminal")
	var long_growth: Dictionary = fixture(); long_growth.active_pet.life.newborn_protection_until = 999999999
	var long_result: Dictionary = SimulationKernelScript.simulate(long_growth, 1000, 1000 + 30 * 86400, BALANCE, {}, {}, {}, GROWTH)
	var long_events: Array = _events_by_type(long_result.generated_events, "pet_grew"); eq(long_result.new_state.active_pet.life.growth_stage, "ADULT", "long offline interval catches every stage"); eq(long_events.size(), 3, "long offline interval emits every growth transition"); eq([long_events[0].occurred_at, long_events[1].occurred_at, long_events[2].occurred_at], [173800, 605800, 1815400], "growth events retain absolute canonical timestamps")
	_reset(); var offline_growth_profile: Dictionary = long_growth.duplicate(true); ok(LocalSaveRepositoryScript.save_profile(offline_growth_profile), "persist incubated newborn for offline growth"); var offline_growth = PetGameSessionScript.new(); offline_growth.balance = BALANCE; offline_growth.lifecycle = care_session.lifecycle; offline_growth.care = care_session.care; offline_growth.survival = SURVIVAL; offline_growth.relationship_balance = RELATIONSHIP; offline_growth.memory_config = MEMORY; offline_growth.growth = GROWTH; offline_growth.initialize_session(1000 + 3 * 86400, 20.0); eq(offline_growth.profile.active_pet.life.growth_stage, "CHILD", "startup reconciliation grows pet offline"); eq(offline_growth.profile.active_pet.growth.stage_started_at, 173800, "offline growth retains threshold rather than login time"); eq(LocalSaveRepositoryScript.load_profile().active_pet.life.growth_stage, "CHILD", "offline growth reconciliation persists")
	var growth_chunks: Dictionary = long_growth.duplicate(true); var chunk_growth_events: Array = []
	var chunk_times := [1000 + 86400, 1000 + 3 * 86400, 1000 + 10 * 86400, 1000 + 30 * 86400]; var previous_growth_time := 1000
	for growth_time in chunk_times:
		var chunk_result: Dictionary = SimulationKernelScript.simulate(growth_chunks, previous_growth_time, growth_time, BALANCE, {}, {}, {}, GROWTH); growth_chunks = chunk_result.new_state; chunk_growth_events.append_array(_events_by_type(chunk_result.generated_events, "pet_grew")); previous_growth_time = growth_time
	eq(growth_chunks.active_pet.growth, long_result.new_state.active_pet.growth, "growth chunking preserves growth metadata"); eq(_event_signatures(chunk_growth_events), _event_signatures(long_events), "growth chunking preserves deterministic events")
	var growth_invariants: Dictionary = long_growth.duplicate(true); growth_invariants.active_pet.relationship.bond = 88.0; growth_invariants.active_pet.relationship.trust = 77.0; growth_invariants.active_pet.relationship.care_experience = 999.0; growth_invariants.active_pet.personality.playfulness = 0.1; var relationship_before_growth_transition: Dictionary = growth_invariants.active_pet.relationship.duplicate(true); var personality_before_growth_transition: Dictionary = growth_invariants.active_pet.personality.duplicate(true); var invariant_growth_result: Dictionary = SimulationKernelScript.simulate(growth_invariants, 1000, 173800, BALANCE, {}, {}, {}, GROWTH); eq(invariant_growth_result.new_state.active_pet.relationship, relationship_before_growth_transition, "growth transition does not mutate relationship"); eq(invariant_growth_result.new_state.active_pet.personality, personality_before_growth_transition, "growth transition does not mutate personality")
	# Runtime growth version governs math and event identity without pure-call governance mutation.
	var growth_v2 := GROWTH.duplicate(true); growth_v2.growth_balance_version = 2; growth_v2.child_age_seconds = 7200; growth_v2.adolescent_age_seconds = 14400; growth_v2.adult_age_seconds = 21600
	var runtime_growth: Dictionary = fixture(); runtime_growth.simulation.growth_balance_version = 1; runtime_growth.active_pet.life.newborn_protection_until = 999999999
	var runtime_v1: Dictionary = SimulationKernelScript.simulate(runtime_growth, 1000, 8200, BALANCE, {}, {}, {}, GROWTH); var runtime_v2: Dictionary = SimulationKernelScript.simulate(runtime_growth, 1000, 8200, BALANCE, {}, {}, {}, growth_v2)
	eq(runtime_v2.new_state.active_pet.life.growth_stage, "CHILD", "runtime growth v2 threshold changes math"); eq(runtime_v2.new_state.active_pet.growth.growth_balance_version, 2, "transition records supplied runtime growth version"); ok(_events_by_type(runtime_v2.generated_events, "pet_grew")[0].event_id.contains("growth:v6:g2:"), "growth event identity reflects runtime version"); eq(_events_by_type(runtime_v2.generated_events, "pet_grew")[0].payload.growth_balance_version, 2, "growth event payload reflects runtime version"); ok(runtime_v1.generated_events[-1].event_id != runtime_v2.generated_events[-1].event_id and runtime_v2.generated_events[-1].event_id.contains(":g2:"), "simulation event identity includes runtime growth version"); eq(runtime_v2.new_state.simulation.growth_balance_version, 1, "pure simulation preserves persisted growth governance")
	# Application projection creates ordered lifecycle memories exactly once without care semantics.
	var growth_session = PetGameSessionScript.new(); growth_session.balance = BALANCE; growth_session.lifecycle = care_session.lifecycle; growth_session.care = care_session.care; growth_session.survival = SURVIVAL; growth_session.relationship_balance = RELATIONSHIP; growth_session.memory_config = MEMORY; growth_session.growth = GROWTH; growth_session.profile = long_growth.duplicate(true); growth_session.advance_in_memory_to(173800)
	var projected_growth: Dictionary = growth_session.profile.active_pet.memory.events[-1]; eq(projected_growth.event_type, "pet_grew", "growth projects a lifecycle memory"); eq(projected_growth.category, "LIFECYCLE", "growth memory category"); eq(projected_growth.importance, 4, "growth memory importance"); eq(projected_growth.valence, 1, "growth memory positive valence"); eq(projected_growth.details, child_growth[0].payload, "growth memory retains transition payload")
	var routine_before_growth: Dictionary = growth_session.profile.active_pet.memory.routine.duplicate(true); var semantic_before_growth: Dictionary = growth_session.profile.active_pet.memory.semantic.duplicate(true); var growth_memory_count: int = growth_session.profile.active_pet.memory.events.size(); growth_session.advance_in_memory_to(173900); eq(growth_session.profile.active_pet.memory.events.size(), growth_memory_count, "growth reconciliation does not duplicate memory"); eq(growth_session.profile.active_pet.memory.routine, routine_before_growth, "growth does not mutate routine memory"); eq(growth_session.profile.active_pet.memory.semantic, semantic_before_growth, "growth does not mutate semantic care memory")
	var memory_long = PetGameSessionScript.new(); memory_long.balance = BALANCE; memory_long.lifecycle = care_session.lifecycle; memory_long.care = care_session.care; memory_long.survival = SURVIVAL; memory_long.relationship_balance = RELATIONSHIP; memory_long.memory_config = MEMORY; memory_long.growth = GROWTH; memory_long.profile = long_growth.duplicate(true); memory_long.advance_in_memory_to(1000 + 30 * 86400); eq(_memory_events_by_types(memory_long.profile.active_pet.memory.events, ["pet_grew"]).map(func(e): return e.details.to_stage), ["CHILD", "ADOLESCENT", "ADULT"], "multi-stage growth memories preserve order")
	# Activity and survival state do not gate age; death is the only biological cutoff.
	var sleeping_growth: Dictionary = long_growth.duplicate(true); sleeping_growth.active_pet.activity = {"state":"SLEEPING","sleep_started_at":1000}; var sleep_growth_result: Dictionary = SimulationKernelScript.simulate(sleeping_growth, 1000, 173800, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(sleep_growth_result.new_state.active_pet.life.growth_stage, "CHILD", "sleeping pet grows by age"); eq(sleep_growth_result.new_state.active_pet.activity.state, "SLEEPING", "growth preserves sleep activity")
	var critical_growth: Dictionary = long_growth.duplicate(true); critical_growth.active_pet.survival = {"condition":"CRITICAL","critical_started_at":1000}; var critical_growth_result: Dictionary = SimulationKernelScript.simulate(critical_growth, 1000, 173800, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(critical_growth_result.new_state.active_pet.life.growth_stage, "CHILD", "critical alive pet grows by age"); eq(critical_growth_result.new_state.active_pet.survival.condition, "CRITICAL", "growth preserves critical state")
	var growth_before_death: Dictionary = death.duplicate(true); growth_before_death.active_pet.life.newborn_protection_until = 0; var predeath_growth_result: Dictionary = SimulationKernelScript.simulate(growth_before_death, 1000, 200000, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(predeath_growth_result.new_state.active_pet.life.growth_stage, "NEWBORN", "death before child threshold freezes newborn growth"); ok(not _has_event(predeath_growth_result.generated_events, "pet_grew"), "death before threshold emits no later growth")
	var same_second_growth := GROWTH.duplicate(true); same_second_growth.growth_balance_version = 3; same_second_growth.child_age_seconds = 7200; same_second_growth.adolescent_age_seconds = 999999; same_second_growth.adult_age_seconds = 1999999
	var same_second: Dictionary = SimulationKernelScript.simulate(growth_before_death, 1000, 11800, BALANCE, {}, care_session.care, SURVIVAL, same_second_growth); eq(same_second.new_state.active_pet.life.growth_stage, "CHILD", "growth at death second is retained"); ok(_event_index(same_second.generated_events, "pet_grew") < _event_index(same_second.generated_events, "pet_died"), "same-second growth precedes death deterministically")
	var growth_then_death := same_second_growth.duplicate(true); growth_then_death.growth_balance_version = 4; growth_then_death.child_age_seconds = 3600; var before_death_growth: Dictionary = SimulationKernelScript.simulate(growth_before_death, 1000, 11800, BALANCE, {}, care_session.care, SURVIVAL, growth_then_death); eq(before_death_growth.new_state.active_pet.life.growth_stage, "CHILD", "growth before later death remains in dead snapshot"); ok(_event_index(before_death_growth.generated_events, "pet_grew") < _event_index(before_death_growth.generated_events, "pet_died"), "growth-before-death chronology is ordered")
	var frozen_growth: Dictionary = same_second.new_state.active_pet.growth.duplicate(true); var frozen_stage := String(same_second.new_state.active_pet.life.growth_stage); var dead_growth_later: Dictionary = SimulationKernelScript.simulate(same_second.new_state, 11800, 11800 + 365 * 86400, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(dead_growth_later.new_state.active_pet.life.growth_stage, frozen_stage, "dead growth stage freezes forever"); eq(dead_growth_later.new_state.active_pet.growth, frozen_growth, "dead growth metadata freezes forever")
	# v6 migration installs growth metadata but lets a living pet catch up at zero elapsed; dead history stays frozen.
	var v6_alive: Dictionary = fixture(); v6_alive.schema_version = 6; v6_alive.active_pet.schema_version = 6; v6_alive.active_pet.erase("growth"); v6_alive.simulation.simulation_version = 5; v6_alive.simulation.erase("growth_balance_version"); v6_alive.simulation.last_simulated_at = 1000 + 10 * 86400; v6_alive.active_pet.life.newborn_protection_until = 999999999
	var migrated_v6_alive: Dictionary = SaveMigratorScript.migrate(v6_alive); ok(DomainStateScript.validate_profile(migrated_v6_alive), "v6 alive profile migrates validly to v7"); eq(migrated_v6_alive.active_pet.growth.stage_started_at, 1000, "v6 newborn migration starts growth safely at birth"); var migrated_catchup: Dictionary = SimulationKernelScript.simulate(migrated_v6_alive, 1000 + 10 * 86400, 1000 + 10 * 86400, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(migrated_catchup.new_state.active_pet.life.growth_stage, "ADOLESCENT", "zero elapsed v6 reconciliation catches up alive growth"); eq(_events_by_type(migrated_catchup.generated_events, "pet_grew").size(), 2, "zero elapsed catch-up emits historical transitions")
	var v6_dead: Dictionary = dead_result.new_state.duplicate(true); v6_dead.schema_version = 6; v6_dead.active_pet.schema_version = 6; v6_dead.active_pet.erase("growth"); v6_dead.simulation.simulation_version = 5; v6_dead.simulation.erase("growth_balance_version"); var migrated_v6_dead: Dictionary = SaveMigratorScript.migrate(v6_dead); var migrated_dead_later: Dictionary = SimulationKernelScript.simulate(migrated_v6_dead, 11800, 11800 + 365 * 86400, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(migrated_dead_later.new_state.active_pet.life.growth_stage, "NEWBORN", "v6 dead history never retroactively grows"); ok(not _has_event(migrated_dead_later.generated_events, "pet_grew"), "v6 dead history emits no growth event")
	var v6_memorial: Dictionary = DomainStateScript.new_profile("v6:memorial:growth", 1000); v6_memorial.schema_version = 6; v6_memorial.memorial_count = 1; var v6_snapshot: Dictionary = v6_dead.active_pet.duplicate(true); v6_memorial.memorials = [{"schema_version":1,"memorial_id":"memorial:v6:growth","memorialized_at":11800,"pet_snapshot":v6_snapshot}]; var migrated_v6_memorial: Dictionary = SaveMigratorScript.migrate(v6_memorial); eq(migrated_v6_memorial.memorials[0].pet_snapshot.life.growth_stage, "NEWBORN", "v6 memorial preserves frozen stage"); ok(DomainStateScript.validate_profile(migrated_v6_memorial), "v6 memorial gains valid growth metadata")
	for egg_state in ["INCUBATING", "READY", "HATCHING"]:
		var v6_egg_profile := DomainStateScript.new_profile("v6:egg:%s" % egg_state, 1000); v6_egg_profile.schema_version = 6; v6_egg_profile.simulation.simulation_version = 5; v6_egg_profile.simulation.erase("growth_balance_version"); v6_egg_profile.active_subject = "EGG"; v6_egg_profile.active_egg = DomainStateScript.new_egg("egg:v6:%s" % egg_state, 1000, 15400); v6_egg_profile.active_egg.schema_version = 6; v6_egg_profile.active_egg.state = egg_state
		if egg_state == "HATCHING": v6_egg_profile.active_egg.reserved_pet_id = "pet:v6:reserved"; v6_egg_profile.active_egg.reserved_pet_seed = 31; v6_egg_profile.active_egg.hatching_started_at = 15400
		var migrated_v6_egg: Dictionary = SaveMigratorScript.migrate(v6_egg_profile); eq(migrated_v6_egg.schema_version, 7, "v6 %s root migrates v7" % egg_state); eq(migrated_v6_egg.active_egg.state, egg_state, "v6 %s lifecycle state preserved" % egg_state); eq(migrated_v6_egg.active_egg.schema_version, 7, "v6 %s egg schema migrates" % egg_state)
	var v6_hatching_profile := DomainStateScript.new_profile("v6:hatching:completion", 1000); v6_hatching_profile.schema_version = 6; v6_hatching_profile.simulation.simulation_version = 5; v6_hatching_profile.simulation.erase("growth_balance_version"); v6_hatching_profile.active_subject = "EGG"; v6_hatching_profile.active_egg = DomainStateScript.new_egg("egg:v6:completion", 1000, 15400); v6_hatching_profile.active_egg.schema_version = 6; v6_hatching_profile.active_egg.state = "HATCHING"; v6_hatching_profile.active_egg.reserved_pet_id = "pet:v6:reserved"; v6_hatching_profile.active_egg.reserved_pet_seed = 31; v6_hatching_profile.active_egg.hatching_started_at = 15400
	var v6_hatching = PetGameSessionScript.new(); v6_hatching.balance = BALANCE; v6_hatching.lifecycle = care_session.lifecycle; v6_hatching.care = care_session.care; v6_hatching.survival = SURVIVAL; v6_hatching.relationship_balance = RELATIONSHIP; v6_hatching.memory_config = MEMORY; v6_hatching.growth = GROWTH; v6_hatching.profile = SaveMigratorScript.migrate(v6_hatching_profile); ok(v6_hatching.complete_hatching(16000, 10.0), "migrated v6 hatching completes"); eq(v6_hatching.profile.active_pet.identity.pet_id, "pet:v6:reserved", "migrated hatching keeps reserved identity"); eq(v6_hatching.profile.active_pet.growth.stage_started_at, 16000, "migrated hatching newborn growth starts at birth"); ok(not _has_event(v6_hatching.profile.recent_events, "pet_grew"), "hatching creates no growth event at birth")
	# Stage changes update presentation text and inspector only; care controls keep their stable signature.
	var growth_ui_session = PetGameSessionScript.new(); growth_ui_session.balance = BALANCE; growth_ui_session.lifecycle = care_session.lifecycle; growth_ui_session.care = care_session.care; growth_ui_session.survival = SURVIVAL; growth_ui_session.relationship_balance = RELATIONSHIP; growth_ui_session.memory_config = MEMORY; growth_ui_session.growth = GROWTH; growth_ui_session.profile = long_growth.duplicate(true); growth_ui_session.reanchor(10.0)
	var growth_screen = FoundationScreenScript.new(); growth_screen.session_override = growth_ui_session; growth_screen._ready(); var growth_feed := growth_screen.lifecycle_button("Feed"); var growth_rebuilds: int = growth_screen.lifecycle_rebuild_count; growth_ui_session.advance_in_memory_to(173800); growth_screen.refresh(); eq(growth_screen.lifecycle_button("Feed"), growth_feed, "growth stage preserves feed node"); eq(growth_screen.lifecycle_rebuild_count, growth_rebuilds, "growth stage does not rebuild care controls"); ok(growth_screen.lifecycle_status.text.contains("Child Pet"), "UI shows current child stage"); ok(growth_screen.inspector.text.contains("Growth stage: CHILD") and growth_screen.inspector.text.contains("Stage Started At: 173800"), "UI inspector shows growth metadata")
	# A backward reconciliation cannot reverse a fully grown pet.
	var backward_growth: Dictionary = adult_result.new_state.duplicate(true); var backward_stage_at: int = int(backward_growth.active_pet.growth.stage_started_at); var backward_result: Dictionary = SimulationKernelScript.simulate(backward_growth, 1815400, 1000, BALANCE, {}, care_session.care, SURVIVAL, GROWTH); eq(backward_result.new_state.active_pet.life.growth_stage, "ADULT", "backward clock never regresses growth"); eq(backward_result.new_state.active_pet.growth.stage_started_at, backward_stage_at, "backward clock preserves stage timestamp")
	memory_ui.free(); rescue_memory.free(); survival_memory_session.free(); hatch_memory_session.free()
	growth_screen.free(); growth_ui_session.free(); v6_hatching.free(); memory_long.free(); growth_session.free(); offline_growth.free()
	for value in [relation_clamp_session, rescue_clamp, low_energy, v2_failure, care_authority, rescue_authority, sleep_memory_session, survival_long, survival_chunks, critical_only, invariant_session, v5_hatch_session]: value.free()
	relationship_session.free(); no_op.free(); version_session.free(); fail_relation.free()
	v4_hatching_session.free(); historical_screen.free(); historical_ui_session.free(); critical_screen.free(); critical_ui_session.free(); permanent_session.free()
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
func _event_index(events: Array, event_type: String) -> int:
	for index in range(events.size()):
		if String(events[index].get("event_type", "")) == event_type: return index
	return -1
func _count_events(events: Array, event_type: String) -> int:
	var count: int = 0
	for event in events:
		if String(event.get("event_type", "")) == event_type: count += 1
	return count
func _events_by_type(events: Array, event_type: String) -> Array:
	var output: Array = []
	for event in events:
		if String(event.get("event_type", "")) == event_type: output.append(event.duplicate(true))
	return output
func _event_signatures(events: Array) -> Array:
	var output: Array = []
	for event in events:
		output.append({"event_id":event.get("event_id", ""), "event_type":event.get("event_type", ""), "occurred_at":event.get("occurred_at", 0), "payload":event.get("payload", {}).duplicate(true)})
	return output
func _has_memory_source(events: Array, source_event_id: String) -> bool:
	for event in events:
		if String(event.get("source_event_id", "")) == source_event_id: return true
	return false
func _memory_events_by_types(events: Array, types: Array) -> Array:
	var output: Array = []
	for event in events:
		if String(event.get("event_type", "")) in types: output.append(event.duplicate(true))
	return output
func _reset() -> void:
	for path in [LocalSaveRepositoryScript.PROFILE_PATH, LocalSaveRepositoryScript.BACKUP_PATH, LocalSaveRepositoryScript.TEMP_PATH, LocalSaveRepositoryScript.BACKUP_TEMP_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
