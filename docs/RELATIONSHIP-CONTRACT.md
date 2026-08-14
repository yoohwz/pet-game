# Relationship Contract

Relationship v1 persists bond and trust in `0..100`, plus cumulative non-negative care experience. Meaningful care has a per-action 300-second simulated-time cooldown: feed/drink/wash must improve their need; touch/play are meaningful on success. Sleep/wake create routine memory but grant no relationship reward.

Eligible rewards use centralized relationship balance v1 and record the actual runtime balance version. Event and memory delta fields are the actual applied post-clamp changes (for example, bond 99 plus a requested +2 records +1); they are never merely configured amounts. A CRITICAL→STABLE rescue receives its independent bonus once, using the same actual-delta rule. There is no passive decay, negative relationship change, growth effect, or personality mutation. Care candidates atomically save biological, relationship, event, and memory changes together.
