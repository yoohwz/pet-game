# Lifecycle Contract

Lifecycle: `NEW GAME → EGG → INCUBATING → READY → HATCHING → ALIVE → NEWBORN → CRITICAL → DEAD → MEMORIAL → optional EGG`. Critical is survival condition, not life or growth state. Growth remains unimplemented.

`life_state` (`ALIVE`/`DEAD`) and `growth_stage` are separate. A profile has at most one active subject; active egg and pet cannot coexist. Egg state has no `born_at`. INCUBATING/READY have no reservation fields. HATCHING requires a reserved pet ID, seed and start timestamp. INCUBATING becomes READY at its persisted threshold without creating a pet. Completion builds and atomically saves a PET candidate before replacing memory; failed completion remains HATCHING. A backward wall clock clamps birth to the current simulation timeline and records an anomaly.

For an ALIVE pet, activity is independent of life/growth state: `AWAKE` has no sleep timestamp; `SLEEPING` has a persisted start timestamp. Survival is `STABLE` or `CRITICAL`; rescue clears CRITICAL only once both hunger and hydration are above zero, without health recovery. DEAD is permanent and frozen. A dead pet is memorialized only by an explicit candidate transaction; a replacement egg is likewise explicit and preserves all memorials.
