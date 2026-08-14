# Phase 7 Task Brief — Offline Language Understanding

Status: **LOCKED FOR CODEX DISCOVERY / IMPLEMENTATION NOT STARTED**

Repository: `yoohwz/pet-game`

Baseline: `main @ 22994bc287bf047d848a7cda65725a5a776a7aea`

Working branch: `codex/phase-7-offline-language`

## Mission

Add a small, deterministic, fully offline language-understanding layer that lets the player type to an ALIVE/AWAKE pet. The pet does **not** answer with generated text. It classifies the message into a bounded intent/topic/sentiment model, produces a non-verbal reaction key, remembers the interaction locally, and can alter the reaction cue when a retained phrase or familiar topic is recognized from prior conversations.

Phase 7 must make the pet feel as if it listens and remembers without introducing an LLM, network dependency, cloud service, model download, chatbot behavior, personality learning, or relationship farming.

## Locked architectural decisions

- Schema becomes **v8**.
- Biological simulation remains **v6**; language does not change passive/survival/growth simulation.
- Memory becomes **v2** because it gains a `LANGUAGE` category and persistent language semantic projections.
- Language model/version is **v1**; language rules version is **v1**.
- Phase 7 uses a deterministic rules/lexicon engine only. **No local LLM, remote API, embedding model, vector database, ML inference, or model asset is allowed in Phase 7.**
- V1 rules support basic **English and Vietnamese** phrase/token lexicons in one local config. No statistical language detection is required. Vietnamese diacritics are preserved; common accentless variants may be supplied explicitly in the rules file.
- The pet never emits generated dialogue. Presentation may show a short developer reaction label/key, but it is not pet speech.
- Language interactions do not change bond, trust, care experience, vitals, survival, growth, personality, activity, or lifecycle state.

## Source authority and invariants

Phase 0–6 accepted contracts remain authoritative. In particular:

- `Presentation → Application → Domain`; Infrastructure is called by Application.
- Domain may not read filesystem, wall clock, monotonic clock, UI, or network.
- Local `user://` persistence remains authoritative and atomic.
- Memory remains bounded, sequence-ordered, idempotent, and per-pet.
- Relationship remains changed only by accepted Phase 5 care/rescue semantics.
- Death freezes pet memory/state and there is no revive.
- A replacement pet inherits no prior-pet relationship, memory, or language state.
- Growth remains age-driven and independent from language.

## New local rules config

Create `data/language/language_rules_v1.json` and an Application loader such as `application/language/default_language_rules.gd`.

Required configuration:

- `language_rules_version = 1`
- `max_input_chars = 256`
- `repeat_window_messages = 8`
- `familiar_topic_threshold = 3` prior mentions
- deterministic intent rules with explicit priorities
- deterministic topic lexicons
- deterministic intent → sentiment/reaction mapping

Rules are data, not scattered constants in UI/Application code.

## Text normalization v1

Pure Domain normalization must:

1. preserve the original text for local memory;
2. trim leading/trailing whitespace;
3. lowercase deterministically;
4. normalize supported punctuation to spaces for phrase/token matching;
5. collapse repeated whitespace;
6. preserve Unicode letters and Vietnamese diacritics;
7. never call locale/network/system services.

Do not silently truncate. Empty/whitespace-only input is rejected. Input longer than `max_input_chars` is rejected.

## Intent taxonomy v1

Canonical intents:

- `GREETING`
- `AFFECTION`
- `PRAISE`
- `PLAY_INVITE`
- `FOOD_OFFER`
- `GOODNIGHT`
- `APOLOGY`
- `USER_SAD`
- `USER_HAPPY`
- `QUESTION`
- `OTHER`

Classification is deterministic. If several rules match, choose the highest explicit rule priority; ties use a stable rule-id/order tie-break. `QUESTION` may be a fallback when no higher intent wins and the original input contains a terminal question mark. `OTHER` is the final fallback.

## Topic taxonomy v1

Canonical topics:

- `FOOD`
- `PLAY`
- `SLEEP`
- `PET`
- `USER`

A message may have zero or multiple topics. Topic order must be canonical/stable, not hash/dictionary order.

## Sentiment v1

Classifier output uses only integer `-1`, `0`, `+1`. Sentiment is a deterministic property of the winning intent/rule, not a probabilistic score.

## Non-verbal reaction keys v1

Canonical reaction keys:

- `ACKNOWLEDGE`
- `AFFECTIONATE`
- `HAPPY`
- `EXCITED`
- `EAGER`
- `SLEEPY`
- `FORGIVING`
- `COMFORTING`
- `CURIOUS`
- `LISTENING`

Reaction selection is deterministic from the classified intent. The reaction is an animation/UI cue, **not generated dialogue**.

## Memory-aware cue v1

Canonical memory cues:

- `NONE`
- `RECOGNIZED_REPEAT`
- `FAMILIAR_TOPIC`

The cue is calculated from authoritative memory **before projecting the current message**.

`RECOGNIZED_REPEAT` wins when the current normalized text exactly matches a retained `pet_heard_message` normalized text among the latest `repeat_window_messages` language memories.

Otherwise `FAMILIAR_TOPIC` wins when any current topic already has at least `familiar_topic_threshold` prior semantic mentions. Topic-count tie behavior must be deterministic.

Otherwise use `NONE`.

This is the Phase 7 proof that prior conversations can affect a later reaction without an LLM.

## Domain language model

Prefer a pure abstraction such as `domain/language/language_model.gd` responsible for:

- validation/normalization helpers;
- deterministic intent classification;
- topic extraction;
- sentiment/reaction selection;
- memory-cue calculation from supplied memory state;
- no persistence or UI.

A successful understanding result should expose at least:

- `language_version = 1`
- `language_rules_version`
- `normalized_text`
- `intent`
- `topics`
- `sentiment`
- `reaction`
- `memory_cue`
- optional stable `matched_rule_id` for audit/tests.

## Application command

Add an explicit Application command such as:

`PetGameSession.speak_to_pet(text: String, monotonic_now: float) -> Dictionary`

Required order:

1. synchronize active monotonic simulation using the normal production path;
2. reject if no active pet;
3. reject if pet is DEAD;
4. reject if pet is SLEEPING;
5. validate input length/content;
6. clone candidate state;
7. classify using the current pre-message memory state;
8. create canonical Application event `pet_heard_message` with schema-v1 envelope and durable event ID;
9. append/project the event into candidate memory;
10. persist candidate atomically;
11. replace authoritative profile only after successful save;
12. return the structured understanding/reaction result.

Required rejection reasons:

- `NO_PET`
- `PET_DEAD`
- `PET_SLEEPING`
- `EMPTY_MESSAGE`
- `MESSAGE_TOO_LONG`
- `PERSIST_FAILED`

Rejected/failed messages create no authoritative language event or memory mutation.

## Canonical event

Event type: `pet_heard_message`.

Subject: active `pet_id`.

Payload must include:

- `text` — original accepted text
- `normalized_text`
- `intent`
- `topics`
- `sentiment`
- `reaction`
- `memory_cue`
- `language_version = 1`
- `language_rules_version = 1`
- optional `matched_rule_id`

The event uses the same schema-v1 Application/Domain event envelope as accepted events. Do not introduce another event format.

## Memory v2

Upgrade Memory to `memory_version = 2`.

Add allowed category `LANGUAGE`.

Map `pet_heard_message` to:

- category `LANGUAGE`
- importance `1`
- valence = the validated payload sentiment (`-1/0/+1`)

The retained memory record stores the complete event payload, including the original text. Raw conversation history is therefore bounded by the existing event-store eviction policy; no second unbounded chat transcript is allowed.

Language memories must not mutate care routine counters or care semantic counters.

## Memory semantic language projection

Extend persistent `memory.semantic` with a language substructure:

```yaml
language:
  message_count: 0
  repeated_message_count: 0
  intent_counts:
    GREETING: 0
    AFFECTION: 0
    PRAISE: 0
    PLAY_INVITE: 0
    FOOD_OFFER: 0
    GOODNIGHT: 0
    APOLOGY: 0
    USER_SAD: 0
    USER_HAPPY: 0
    QUESTION: 0
    OTHER: 0
  topic_counts:
    FOOD: 0
    PLAY: 0
    SLEEP: 0
    PET: 0
    USER: 0
  last_message_at: null
  last_intent: null
  last_topics: []
```

Projection rules:

- every accepted `pet_heard_message` increments `message_count` once;
- increment exactly one intent counter;
- increment each unique recognized topic once per message;
- increment `repeated_message_count` when payload `memory_cue == RECOGNIZED_REPEAT`;
- update last-message fields;
- summaries never roll back when raw language records are evicted.

Add a pure helper/query for latest retained language memories used by repeat detection. Do not assume the latest 8 overall memories are all language events.

## Migration v7 → v8

Root:

- `schema_version = 8`
- keep `simulation_version = 6`
- no biological simulation bump

Every active pet and every memorial pet snapshot:

- pet schema becomes v8;
- Memory v1 becomes Memory v2;
- preserve all existing memory event IDs, source IDs, sequences, categories, details, routine projections, care semantic projections, and `next_sequence`;
- add fresh zeroed `semantic.language` state;
- do **not** backfill language summaries from unrelated historical events.

Egg lifecycle data migrates unchanged except schema version.

Legacy v1–v7 migration chain must still end in a valid schema-v8 profile.

DEAD/memorial history remains frozen; migration must not invent language events.

## Validation

Domain validation must enforce:

- schema v8;
- Memory v2 exactly;
- existing memory invariants unchanged;
- `LANGUAGE` as an allowed category;
- semantic.language required and correctly shaped;
- all counters strict non-negative integers;
- intent/topic key sets fixed and complete;
- `last_message_at` null or int;
- `last_intent` null or canonical intent;
- `last_topics` Array containing unique canonical topics in canonical order;
- for retained `pet_heard_message`: payload language version/rules version, text/normalized text strings, canonical intent/topics, sentiment `-1/0/+1`, canonical reaction and memory cue.

Keep exact-whole JSON canonicalization for strict integer fields. Do not add approximate coercion.

## Relationship, personality, biology and growth

A language interaction grants **zero** bond/trust/care-experience and does not alter `last_rewarded_at`.

It must not mutate:

- hunger/hydration/energy/hygiene/mood/health;
- survival condition;
- activity state;
- growth stage/metadata;
- personality.

Language is not a care action and cannot rescue CRITICAL.

## Death / sleep / replacement semantics

- DEAD: `PET_DEAD`, no event/memory.
- SLEEPING: `PET_SLEEPING`, no event/memory and no implicit wake.
- CRITICAL but ALIVE/AWAKE: message is accepted normally; language does not heal/rescue.
- Memorial snapshot preserves final Memory v2 including retained language memories and language semantic summary.
- Replacement pet starts with fresh Memory v2 language summary and no inherited messages.

## Presentation v1

Add a simple developer-facing text input and Send control for an ALIVE/AWAKE pet. Do not introduce final chat artwork.

After a successful message, display read-only diagnostics such as:

- intent
- topics
- reaction key
- memory cue

Do not render generated pet sentences.

Language-memory changes must not rebuild existing care/lifecycle controls. DEAD/SLEEPING availability must follow the Application contract.

## Mandatory test matrix

At minimum cover:

### Rules/config
- real config loads;
- version/max length/repeat window/familiar threshold exact;
- fixed intent/topic/reaction sets;
- deterministic priorities.

### Normalization/classification
- trim/lower/whitespace/punctuation normalization;
- English examples for every intent;
- Vietnamese examples for every intent;
- `QUESTION` fallback;
- `OTHER` fallback;
- deterministic multi-match priority;
- stable topic order;
- sentiment and reaction mapping.

### Input rejection
- empty;
- whitespace-only;
- >256 chars;
- no pet;
- DEAD;
- SLEEPING;
- all leave authoritative language memory unchanged.

### Successful message
- canonical schema-v1 `pet_heard_message`;
- correct subject/timestamp/payload;
- Memory category LANGUAGE, importance 1, valence from sentiment;
- text and normalized text preserved;
- semantic language counters update exactly once;
- care routine/semantic summaries unchanged;
- relationship/personality/vitals/survival/growth unchanged.

### Memory-aware reaction
- first phrase → `NONE`;
- exact retained repeat → `RECOGNIZED_REPEAT`;
- repeat search is limited to latest configured language messages;
- familiar topic triggers only from prior semantic count threshold;
- repeat wins over familiar-topic cue;
- current message is not counted when deciding its own cue.

### Eviction / bounded memory
- language messages obey existing 64-record cap;
- low-importance language records evict before retained importance-3/4 lifecycle/survival records when applicable;
- semantic language counts survive raw eviction;
- `next_sequence` remains lifetime-monotonic.

### Candidate failure
- injected persistence failure returns `PERSIST_FAILED`;
- no authoritative event, memory record, semantic counter, or reaction history mutation.

### Migration
- v7 active ALIVE with non-empty Memory v1 → valid v8 Memory v2 preserving all old memory exactly and zero language summary;
- v7 DEAD active pet → no language backfill;
- v7 memorial snapshot → preserved memory plus zero language summary;
- v7 INCUBATING/READY/HATCHING → preserved;
- migrated HATCHING completion → v8 newborn with fresh Memory v2;
- legacy v1–v6 chain still valid.

### Death / memorial / new pet
- accepted language memories freeze after death;
- memorial preserves exact language records/summary;
- replacement pet has no inherited language records or counts.

### UI
- input/send availability by state;
- successful send updates reaction diagnostics;
- care-control node identity/rebuild count remains stable;
- UI refresh is read-only.

### Regression
- all Phase 0–6 tests remain green.

## Evidence and delivery

Create/update:

- `docs/LANGUAGE-CONTRACT.md`
- Product/Architecture/Memory/Persistence/Testing/Roadmap contracts as required
- `docs/reviews/PHASE-7-IMPLEMENTATION-REPORT.md`
- `docs/reviews/evidence/phase-7-tests.txt`
- `docs/reviews/evidence/phase-7-project-validation.txt`

Run:

- `godot --headless --path . -s res://tests/test_runner.gd`
- `godot --headless --path . --editor --quit`
- `godot --headless --path . --quit-after 1`

Current accepted baseline is **855 passed / 0 failed**. Phase 7 must retain 0 failures and increase executable coverage.

Push implementation to `codex/phase-7-offline-language` and open a PR against `main`. Do not merge. Phase 7 remains an IMPLEMENTED CANDIDATE until independent ChatGPT Acceptance Review passes and the human gate approves merge.

## Explicit non-goals

- generated pet dialogue;
- local or remote LLM;
- embeddings/vector search;
- online API/network access;
- speech-to-text/text-to-speech;
- personality learning/mutation;
- language-driven relationship rewards;
- language-driven growth;
- language-driven care/rescue;
- long-term unbounded transcripts;
- cloud sync/community;
- inventory/currency;
- final art/animation system.
