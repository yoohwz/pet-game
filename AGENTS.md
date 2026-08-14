# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps/configuration and never reads a system clock. Schema v5 pets have AWAKE/SLEEPING activity plus STABLE/CRITICAL survival state; care commands are Application candidate transactions with durable care/sleep events. Survival uses explicit passive, care and survival balance semantics; death is permanent and memorial/new-egg actions are explicit Application transactions. Presentation keeps lifecycle controls stable across frames; reaction text is non-persistent. Foreground ticks are in-memory only, while autosave and lifecycle/debug boundaries persist explicitly.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Backup rotation may use only validated data; a failed replacement must preserve at least one known-good copy. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
