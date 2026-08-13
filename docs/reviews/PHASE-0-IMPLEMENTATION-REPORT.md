# Phase 0 Implementation Report

## Status

PASS

## Repository

Repository: `yoohwz/pet-game`  
Remote: `https://github.com/yoohwz/pet-game.git`  
Base branch: `main`  
Working branch: `codex/phase-0-foundation`  
Base SHA: `688dc7a0d346aa94151ad65e6fece2d099cac6d4`  
Implementation SHA: `1421b2c6a6cd22eca41ff8bbff1dba78472fb115`  
Final report commit: `0c76c3b5cb90000b738ba74cf55e440b36619a65`  
Pull request: [#1](https://github.com/yoohwz/pet-game/pull/1)

Repository status: clean before this report commit.

## Godot

Version: `4.7.1.stable.official.a13da4feb`  
Installation: installed during task from the official Homebrew cask.

## Implemented Milestones

- P0.1: Godot skeleton, contracts, roadmap, repository instructions.
- P0.2: constrained profile, egg, pet identity/life, vital, relationship, personality and simulation state primitives.
- P0.3–P0.4: application-owned clocks and deterministic explicit-time kernel.
- P0.5: JSON profile save, schema v1, temp-write/backup/rename recovery and migration seam.
- P0.6: stable event shape and unique IDs.
- P0.7: dependency-free headless assertions and 18 foundational checks.
- P0.8–P0.9: debug time controls using production reconciliation and state inspector.
- P0.10–P0.11: parse/startup smoke validation, evidence, committed review candidate.

## Architecture

Domain dependencies: GDScript value types only; no node, filesystem, network, UI or clock calls.  
Application responsibilities: owns wall/monotonic clocks, reconciliation and persistence coordination.  
Infrastructure responsibilities: local JSON save/recovery and migration seam.  
Presentation responsibilities: placeholder debug controls and inspection only.

## Clock and Simulation

Wall clock: `ClockProvider.wall_utc()` uses Unix UTC in Application. Monotonic time is separately supplied by `monotonic_seconds()`. Negative clock movement produces zero elapsed and increments an anomaly count. `SimulationKernel.simulate(profile, from, to)` is deterministic and additive; 24 hourly advances equal one 24-hour advance within 0.0001.

## Persistence and Events

`user://profile.json` is validated before save; temp and backup-temp representations are revalidated, then all critical directory/copy/rename results are checked. Only a valid canonical profile rotates into `user://backup/profile.json.bak`; a corrupt canonical cannot poison a valid backup. Load falls back to a valid backup. Schema version is 1 and `SaveMigrator` is the deliberately minimal seam. Events contain explicit durable `event_id`, `event_type`, `occurred_at`, `subject_id`, `payload`, and `schema_version`; simulation IDs derive deterministically from their coordinates.

## Debug Tooling

The foundation screen exposes +10m, +1h, +8h, +1d and +7d. `advance_debug()` calls `reconcile_to()`, the normal production entry point. The inspector shows profile/simulation fields, reserved pet values, anomalies and recent events.

## Tests

Exact command:

```sh
godot --headless --path . -s res://tests/test_runner.gd
```

Result: **26 passed, 0 failed**.

| Evidence | Result |
| --- | --- |
| Project boot / parse | PASS |
| Profile round trip | PASS |
| Negative elapsed | PASS |
| Determinism | PASS |
| 24 × 1h vs 1 × 24h | PASS |
| Atomic save / backup recovery | PASS |
| Event serialization | PASS |
| Debug production-path reuse | PASS |

See `docs/reviews/evidence/` for concise command output.

## Acceptance Review Corrective Pass

Previous review verdict: **REWORK REQUIRED**
Pre-correction review HEAD: `c894cf6cc38fa188d5525aad263bf6bf7cd0250b`
Corrective implementation commit: `e3b3f516d9ca79eb017281e13896de9e822fcfc3`
Evidence/report commit: this documentation delivery commit (the final branch HEAD is authoritative).

### 1. Event identity across process restarts

Resolved. `DomainEvent.make()` now requires an explicit durable ID and has no process-local sequence/default-ID path. The simulation kernel derives its `simulation_advanced` event identity from subject and interval coordinates, preserving retry determinism. Tests verify explicit JSON round-trip preservation, distinct explicit IDs, same-coordinate deterministic equality, and different-coordinate inequality. Future non-deterministic application events are documented to obtain globally unique IDs outside pure Domain simulation.

### 2. Persistence last-known-good preservation

Resolved. New state and temp files are validated; directory, copy, and rename errors are checked. Backup rotation occurs only from a validated canonical profile through a validated backup temp. A corrupt canonical is not copied over an existing valid backup. The test-only replacement hook exercises failure after temp validation and verifies that `load_profile()` still finds a valid state.

## Files and Scope

Important additions: `domain/`, `application/`, `infrastructure/persistence/`, `presentation/`, `tests/`, contracts, and evidence. Dependencies added: none. Phase 1+ gameplay: **NO**. Networking, AI, backend and final pet art: **NO**.

## Known Limitations

This is intentionally a foundation: no egg gameplay, hatching transaction, need decay, death mechanics, memory, language, online systems or production art. Future hatching/death transaction safety is documented in lifecycle and persistence contracts.

## Recommended Next Step

Phase 1 — Offline Simulation, only after independent Phase 0 Acceptance Review.
