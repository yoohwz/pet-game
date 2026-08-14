# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. Tests retain Phase 0–6 coverage and add Phase 7 real-rules loading, deterministic English/Vietnamese intent/topic/reaction classification, normalization, priority/question/OTHER fallbacks, input-state rejection, canonical `pet_heard_message` persistence, Memory v2 LANGUAGE projection/validation/migration, repeat/familiar-topic cues, bounded raw language eviction with durable summaries, candidate-failure authority, and stable awake/sleeping language controls/diagnostics. A pass exits 0; any failure exits non-zero.
