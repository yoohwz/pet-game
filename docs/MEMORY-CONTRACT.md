# Memory Contract

Schema v6 gives each pet a local-only memory v1. Raw records are identified as `memory:<source_event_id>`, sequence-ordered, idempotently projected, and capped at 64 by lowest-importance then oldest-sequence eviction. Working (latest 8), episodic (importance ≥3), and emotional (non-neutral) memories are pure views; routine and semantic summaries are persistent projections.

Only pet events are recorded: hatch, care/routine actions, CRITICAL, stabilization and death. There is no migration backfill, language generation, or cross-pet inheritance. Death freezes memory; a memorial preserves the complete snapshot.
