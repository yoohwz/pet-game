# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps/configuration and never reads a system clock. Schema v8 retains deterministic Growth v1 and adds Memory v2 language projections. Pets retain AWAKE/SLEEPING activity, STABLE/CRITICAL survival, relationship v1 and bounded per-pet memory. `speak_to_pet` is an Application candidate transaction for ALIVE/AWAKE pets: it synchronizes simulated time, applies only local rules v1, persists a `pet_heard_message`, then projects MEMORY LANGUAGE data atomically. It never changes biology, relationship, personality, growth, lifecycle, or survival. The pure Domain language model has no I/O and produces deterministic intents/topics/sentiment/reaction/memory cues; Presentation only displays non-persistent diagnostics and keeps care controls stable. No LLM, network, generated dialogue, or unbounded transcript is allowed.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Backup rotation may use only validated data; a failed replacement must preserve at least one known-good copy. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
