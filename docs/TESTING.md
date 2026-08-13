# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests cover schema v1→v2 migration, passive need math, persistence recovery, and application timing: irregular monotonic ticks preserve fractional remainders/cadence independence, foreground ticks do not save, 30-second autosave does, pause/startup/resume/debug persist, and debug re-anchors before later active progression. No presentation scene is loaded by pure-domain tests.
