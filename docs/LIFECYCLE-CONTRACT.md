# Lifecycle Contract

Lifecycle: `NEW GAME → EGG → INCUBATING → READY → HATCHING → ALIVE → NEWBORN → CHILD → ADOLESCENT → ADULT → DEAD → MEMORIAL`. Phase 2 implements through NEWBORN only.

`life_state` (`ALIVE`/`DEAD`) and `growth_stage` are separate. A profile has at most one active subject; active egg and pet cannot coexist. Egg state has no `born_at`. INCUBATING becomes READY at its persisted threshold without creating a pet. HATCHING reserves one pet identity durably; completion builds and atomically saves a PET candidate before replacing memory. Failed completion remains HATCHING. Birth time is completion time and newborn-protection metadata lasts 12h.
