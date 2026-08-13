# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. Tests retain Phase 0–2 coverage and add Phase 3 migration/activity validation, care clamps/rejections, persistence failures, offline sleep, sleep chunking, interaction timeline ordering, semantic event IDs, stable awake/sleep controls, and reaction feedback. A pass exits 0; any failure exits non-zero.
