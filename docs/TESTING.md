# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests retain Phase 1 coverage and add exhaustive egg/root lifecycle validation, real startup-offline INCUBATING→READY persistence, deterministic ready events, touch, HATCHING recovery/failure safety, and backward-clock birth clamping. No presentation scene is loaded by pure-domain tests.
