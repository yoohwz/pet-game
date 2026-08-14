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

Result: **384 passed, 0 failed**.

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

## Acceptance Review Corrective Pass 2

Previous verdict: `REWORK REQUIRED`

Pre-correction review HEAD: `c26c4c41cddb31a063461b4f50fcfedb7c442627`

### Production Fix 1 — CRITICAL sleeping warning

Resolved: YES. `PET:ALIVE:CRITICAL:SLEEPING` displays both its sleeping state and CRITICAL warning while retaining the Wake-only control contract.

### Production Fix 2 — Historical memorial action consistency

Application eligibility remains snapshot-backed (`memorial_count > 0` and non-empty `memorials`). Presentation distinguishes historical-only memorials, shows their history safely, and hides New Egg when it would be rejected.

### Acceptance completion

Direct executable coverage now includes permanent death through resume/debug/backward-clock paths, dead-care rejection, complete survival validation, v4 egg/HATCHING migration and completion, critical→death chronology, memorial/new-egg failure authority, no unattended memorial, New Egg 4-hour/offline READY behavior, and the full critical/dead/memorial UI transition matrix.

## Acceptance Review Corrective Pass 3

Previous verdict: `REWORK REQUIRED`

Pre-correction review HEAD: `90fb3a23ef7349f5d69d1bf81487eea39dcc34a5`

### Gap 1 — Memorial failure authority

Production code changed: NO.

Direct failure injection proves `PERSIST_FAILED` leaves the active DEAD pet, count, snapshots, recent events, and persisted recovery state unchanged; no authoritative `pet_memorialized` event is created.

### Gap 2 — Double memorialization

After one successful transaction, a second call is rejected with active subject remaining NONE. It does not increment the count, append a snapshot, or emit another `pet_memorialized` event.

### Gap 3 — New Egg failure authority

Direct failure injection on a snapshot-backed memorial proves `PERSIST_FAILED` leaves NONE/null active state, memorial history, count, and event history unchanged; no `egg_received` becomes authoritative.

### Gap 4 — Replacement Egg lifecycle

The explicit replacement egg has a fresh durable ID, `source = new_cycle` event, and the normal 4-hour incubation. A fresh Application session reconciles it to READY after 8 hours, persists READY, and never begins HATCHING or creates a pet unattended.

### Regression

Full suite: **384 passed, 0 failed**.

Project validation: PASS. Phase 0–3 and Phase 4 core: PASS. Architecture and scope: PASS.
