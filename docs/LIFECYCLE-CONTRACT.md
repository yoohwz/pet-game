# Lifecycle Contract

Future lifecycle: `NEW GAME → EGG → INCUBATING → READY → HATCHING → ALIVE → NEWBORN → CHILD → ADOLESCENT → ADULT → DEAD → MEMORIAL`.

`life_state` (`ALIVE`/`DEAD`) and `growth_stage` are separate. A profile has at most one active subject; active egg and pet cannot coexist. Egg state has no `born_at`. A pet is created once, its `pet_id`/`born_at` are immutable, dead pets are not simulated, and `DEAD → ALIVE` is invalid. Future hatching persists HATCHING, plays presentation, creates/persists exactly one pet, then removes egg idempotently. Future death calculates exact time, persists DEAD, emits once, and creates an idempotent memorial.
