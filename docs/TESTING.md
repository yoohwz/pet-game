# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests cover schema v1→v2 migration, passive one/eight/twenty-four-hour decay, clamping, mood/health/dead-pet boundaries, chunking/event determinism, monotonic and wall-clock application paths, v2 active-pet round trip, and backup/replacement-failure recovery. No presentation scene is loaded by pure-domain tests.
