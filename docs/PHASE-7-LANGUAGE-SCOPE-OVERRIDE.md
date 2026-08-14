# Phase 7 Language Scope Override — English-Only v1

Status: **AUTHORITATIVE OVERRIDE FOR PHASE 7 CORRECTIVE PASS**

Repository: `yoohwz/pet-game`

Applies to: `docs/PHASE-7-TASK-BRIEF.md` and all Phase 7 implementation/contracts/tests.

## Decision

Phase 7 Language v1 is **English-only**.

The earlier requirement to support both English and Vietnamese is superseded by this file. For Phase 7 v1:

- English is the only required natural-language lexicon.
- Vietnamese phrases, Vietnamese topic aliases, Vietnamese diacritic variants, accentless Vietnamese variants, and Vietnamese-specific tests are out of scope.
- Do not add a second natural language during Phase 7 corrective work.
- The architecture must remain extensible so another language can be added later as a new ruleset/version without redesigning Domain/Application/Memory.

## Unchanged requirements

All other locked Phase 7 requirements remain authoritative, including:

- schema v8;
- simulation v6 unchanged;
- Memory v2;
- Language v1 / language-rules v1;
- fully offline deterministic rules/lexicon engine;
- no LLM, ML inference, embeddings, vector DB, network API, model download, generated pet dialogue, speech recognition or TTS;
- bounded local language memory and semantic projections;
- canonical intent/topic/sentiment/reaction/memory-cue model;
- `speak_to_pet` candidate transaction and persistence authority;
- language must not mutate relationship, personality, care, vitals, survival, growth, activity or lifecycle;
- DEAD/SLEEPING rejection;
- memorial preservation and replacement-pet isolation;
- complete Phase 0–6 regression.

## Matching semantics

Rules remain phrase/token lexicons, not arbitrary substring matching.

- Single-token lexicon entries must match complete normalized tokens only.
- Multi-token phrase entries may match contiguous complete-token sequences inside a message.
- Lexicon fragments must not match inside unrelated words.

Examples that must **not** produce false topics merely through substrings:

- `this` must not match USER because it contains `i`;
- `banana` must not match FOOD because it contains `an`;
- `member` must not match PET because it contains `em`;
- `display` must not match PLAY because it contains `play` as part of another word.

## Normalization semantics

Normalization must deterministically collapse supported whitespace forms, including ordinary spaces, tabs, newlines and carriage returns, into single spaces after punctuation normalization.

Examples:

- `hello   pet` → `hello pet`
- `hello\tpet` → `hello pet`
- `hello\npet` → `hello pet`
- `hello\r\npet` → `hello pet`

## Versioned memory config

Memory v2 must use an honestly named/versioned resource such as `data/config/memory_v2.json`. Do not leave `memory_v1.json` declaring `memory_version = 2`.

## Acceptance authority

For the Phase 7 corrective re-review, this override takes precedence over any earlier English+Vietnamese wording in `docs/PHASE-7-TASK-BRIEF.md` until that task brief is synchronized in the corrective commit.
