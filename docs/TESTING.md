# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests live in `tests/` and cover pure-domain profile/lifecycle/time/determinism/event behavior plus persistence round-trip, backup recovery, and debug production-path reuse. No presentation scene is loaded by pure-domain tests.
