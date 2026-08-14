# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps/configuration and never reads a system clock. Schema v6 pets have AWAKE/SLEEPING activity, STABLE/CRITICAL survival, relationship v1 and bounded memory v1. Care commands are Application candidate transactions with durable care/sleep events; relationship/memory projection is atomic and uses simulated timestamps. Relationship deltas stored in events/memory are actual post-clamp changes, never requested reward amounts. Only real care/routine events update routine counts: a `pet_stabilized` record may name its causal action but does not double-count it. Memory schema/version and integer fields validate strictly; the persistence boundary only canonicalizes mathematically exact whole JSON floats, never tolerated near-integers. Survival uses explicit passive, care and survival balance semantics; death is permanent and memorial/new-egg actions are explicit Application transactions. Presentation keeps lifecycle controls stable across frames and displays read-only summaries. Foreground ticks are in-memory only, while autosave and lifecycle/debug boundaries persist explicitly.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Backup rotation may use only validated data; a failed replacement must preserve at least one known-good copy. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
