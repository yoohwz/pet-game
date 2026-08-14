# Phase 4 Implementation Report

Status: PASS

Repository: `yoohwz/pet-game`

Base: `main @ 4caeed32f033eada56a0637bbd5a2de22daf4f35`

Branch: `codex/phase-4-survival-death`

Schema: v5; simulation: v5; survival balance: v1.

## Survival

The pure simulation kernel receives explicit survival configuration and integrates only semantic boundaries: newborn-protection expiry, hunger/hydration zero, CRITICAL entry and death. Hunger zero costs 2 health/hour, hydration zero costs 4 health/hour, and rates combine. Transition timestamps are deterministic and chunking-independent. Simulation identity now includes survival balance semantics.

Newborn protection remains lifecycle-owned (12 hours). During protection, needs continue to progress but deprivation causes no health damage. CRITICAL is a survival condition; care can clear it only after hunger and hydration are both above zero. Care never restores health.

## Death and memorials

At health zero a pet becomes permanently DEAD with deterministic `died_at` and one of `STARVATION`, `DEHYDRATION`, or `COMBINED_DEPRIVATION`. The pet is frozen thereafter. Startup persists offline reconciliation but does not memorialize or create an egg unattended.

`memorialize_pet()` uses a candidate save to preserve a dead snapshot and then clears the active pet. `request_new_egg()` is another explicit candidate transaction; it preserves memorial history and reuses the accepted Phase 2 incubation flow.

## Migration and UI

v4 profiles migrate to v5 with `survival_balance_version = 1`, a stable survival block on existing pets, and an empty memorial array when absent. Egg and HATCHING reservation data are retained. The placeholder UI has stable signatures for STABLE, CRITICAL, DEAD and memorial states, with explicit Memorialize Pet and New Egg controls.

## Tests

Command: `godot --headless --path . -s res://tests/test_runner.gd`

Result: **291 passed, 0 failed**.

Coverage includes Phase 0–3 regression, protection, zero-need boundary timing, damage rates, deterministic critical/death timestamps, offline death, death freezing, rescue, dead-care rejection, memorial persistence failure safety, explicit new egg and v4→v5 migration/validation.

## Architecture and scope

Domain → filesystem/clock/UI/network: NO.

Phase 4 adds no growth, memory, relationship learning, inventory, online features, revival, or final art.

## Acceptance Review Corrective Pass

Previous verdict: `REWORK REQUIRED`

Pre-correction review HEAD: `1ffd73a755284b97973416f8e46c883df57bb4e4`

- Memorial bookkeeping preserves legacy history: `memorial_count` is incremented independently from durable snapshot count.
- DEAD UI displays name, birth, death time and death cause; MEMORIAL UI reads its latest durable snapshot and handles historical count-only states safely.
- The acceptance matrix now covers causes, chunking, critical event uniqueness/order, partial rescue, permanent death, migration, survival version semantics, candidate failures and stable UI transitions.
