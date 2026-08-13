# Repository Contract

## Architecture
Keep dependencies `Presentation → Application → Domain`; Infrastructure is called by Application. Never introduce Domain → UI, filesystem, or network dependencies.

## Time and lifecycle
Domain logic receives explicit timestamps and never reads a system clock. Preserve egg/pet distinction, immutable pet identity and birth time, and the invalid `DEAD → ALIVE` transition.

## Scope and dependencies
Implement only the active phase. Prefer explicit state and small deterministic abstractions. Do not add third-party dependencies without an active-task justification.

## Persistence and tests
Persistent schema changes require versioning, compatibility assessment, migration when needed, and tests. Simulation, persistence, and lifecycle changes must update headless tests.

## Git
Use dedicated branches, preserve `main`, commit coherent changes, push reviewable branches, never force-push without explicit authorization, and do not merge before the designated acceptance gate.
