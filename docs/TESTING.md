# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests retain Phase 1 timing/persistence coverage and add v2→v3 migration, exact-once egg issuance, offline readiness, deterministic egg-ready events, touch persistence, HATCHING recovery, and both hatching transaction failure paths. No presentation scene is loaded by pure-domain tests.
