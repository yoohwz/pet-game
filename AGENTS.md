# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps/configuration and never reads a system clock. Foreground time comes from Application monotonic anchors; offline/resume time comes from Application wall reconciliation. Preserve egg/pet distinction: READY never creates a pet; HATCHING reserves identity; only successful atomic completion creates immutable pet identity/birth time. Foreground ticks are in-memory only, while autosave and lifecycle/debug boundaries persist explicitly.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Backup rotation may use only validated data; a failed replacement must preserve at least one known-good copy. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
