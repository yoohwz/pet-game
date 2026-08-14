# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps/configuration and never reads a system clock. Schema v7 adds deterministic Growth v1: age from `born_at` transitions NEWBORN → CHILD → ADOLESCENT → ADULT at centralized 2d/7d/21d thresholds. Growth is independent of care, relationship, personality, sleep and CRITICAL while ALIVE; death freezes it. Every `pet_grew` record is a canonical schema-v1 `DomainEvent` made through `DomainEvent.make`, with no alternate event envelope. Growth events and their lifecycle memories are deterministic, and simulation identity includes passive, care, survival and growth balance semantics. Pets retain AWAKE/SLEEPING activity, STABLE/CRITICAL survival, relationship v1 and bounded memory v1. Care commands are Application candidate transactions with durable care/sleep events; relationship/memory projection is atomic and uses simulated timestamps. Presentation keeps lifecycle controls stable across frames and displays read-only summaries. Foreground ticks are in-memory only, while autosave and lifecycle/debug boundaries persist explicitly.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Backup rotation may use only validated data; a failed replacement must preserve at least one known-good copy. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
