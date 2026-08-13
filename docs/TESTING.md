# Testing

Run `godot --headless --path . -s res://tests/test_runner.gd`. A passing suite exits 0; any assertion failure exits non-zero and prints `FAIL:`. Tests retain Phase 1/2 coverage and add direct lifecycle presentation tests: unchanged states preserve button references/rebuild count, while INCUBATING→READY→HATCHING→PET transitions rebuild controls exactly when required. No third-party UI framework is used.
