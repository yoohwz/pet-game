# Growth Contract

Growth v1 is deterministic real elapsed biological age, calculated from the explicit simulation timeline and `pet.identity.born_at`. It is never driven by care, relationship, care experience, personality, mood or memory count.

Stages are monotonic: NEWBORN before 172800 seconds, CHILD at 172800, ADOLESCENT at 604800 and ADULT at 1814400. Thresholds are centralized in `growth_v1.json`; boundary timestamps are absolute from birth. Offline reconciliation and chunked simulation must emit every crossed transition at its canonical timestamp. A pet grows while sleeping or CRITICAL while it remains ALIVE. At an equal timestamp, `pet_grew` is ordered before CRITICAL and death; once DEAD, all growth state is frozen.

Each pet persists `growth_version`, `growth_balance_version` and `stage_started_at`; age itself is derived and is not stored. `pet_grew` IDs are deterministic and project once into a positive importance-4 LIFECYCLE memory without changing routine/semantic care, relationship or personality. v6 ALIVE pets gain growth metadata and can catch up at zero elapsed reconciliation. DEAD pets and memorial snapshots only gain metadata and never receive retrospective growth.
