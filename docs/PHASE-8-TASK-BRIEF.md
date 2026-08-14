# Phase 8 Task Brief — Product Polish / Playable MVP Shell

Status: **LOCKED FOR CODEX DISCOVERY / IMPLEMENTATION NOT STARTED**

Repository: `yoohwz/pet-game`

Baseline: `main @ 1aedff62c6d1c0e012d3152b9bbc50464ac7b1e1`

Working branch: `codex/phase-8-product-polish`

## Mission

Transform the current developer-oriented foundation screen into a coherent, playable, portrait-first MVP shell without adding new gameplay systems or changing any accepted Phase 0–7 domain semantics.

Phase 8 is a presentation/productization pass. A player opening the app should be able to understand the current egg/pet state, see the companion, inspect important needs, perform the currently valid lifecycle/care/language actions, receive clear non-verbal feedback, and move through death/memorial/new-egg states without seeing raw engineering diagnostics by default.

## Locked version decisions

Phase 8 does **not** introduce a persistence or simulation semantic change.

Keep exactly:

- `schema_version = 8`
- `simulation_version = 6`
- `memory_version = 2`
- `language_version = 1`
- `language_rules_version = 1`
- Growth v1
- Relationship v1
- Survival v1
- Care v1

No schema migration is required for Phase 8.

## Source authority and invariants

All accepted Phase 0–7 contracts remain authoritative.

In particular:

- `Presentation → Application → Domain`; Infrastructure is called by Application.
- Presentation must not implement biological, relationship, memory, growth, survival, language-classification, persistence or lifecycle rules.
- Existing `PetGameSession` commands remain the authority for all mutations.
- Existing deterministic simulation/event/memory semantics must not change.
- Language v1 remains English-only and offline.
- No generated pet dialogue.
- Death remains permanent.
- Debug Time Machine must continue to use the production simulation path.
- Existing candidate persistence guarantees remain unchanged.

## Current presentation baseline

The current project already uses a portrait baseline of `360 × 640`, nearest-neighbor texture behavior and `presentation/scenes/main.tscn`, but the visible screen is still a programmatic developer foundation UI with raw inspector data and debug time controls mixed into the main experience.

Phase 8 must productize this layer rather than invent new Domain/Application behavior.

## Product shell layout

The normal player-facing screen should contain these conceptual zones in a clear portrait hierarchy:

1. **Companion header**
   - current companion label/name when a pet exists;
   - lifecycle/growth state in readable user-facing English;
   - explicit CRITICAL indicator when applicable;
   - no raw schema/version/timestamp diagnostics.

2. **Companion stage**
   - a centered visual stage for the egg/pet/memorial;
   - use a deterministic procedural/pixel-placeholder visual, not final art;
   - logical visual target remains compatible with the future ~32×32 pixel pet canvas;
   - nearest-neighbor/integer-aligned presentation where applicable;
   - visual differences must exist for egg, living growth stages, sleeping, critical, dead and memorial states;
   - reaction feedback may alter the placeholder expression/cue transiently in Presentation only.

3. **Status / needs**
   - for a living pet, display hunger, hydration, energy, hygiene, mood and health in a compact readable form;
   - values derive only from the authoritative profile;
   - values remain in `0..100` and should be displayed without false precision;
   - CRITICAL must be communicated with text/iconography, not color alone;
   - sleeping state remains visibly distinguishable.

4. **Context actions**
   - show only actions already allowed by the accepted lifecycle/care contracts;
   - reuse the existing Application commands;
   - action availability must not be re-derived differently from Application authority;
   - touch targets should be mobile-friendly, with a practical minimum target around 44 logical pixels where layout allows;
   - care controls should remain stable across ordinary value-only refreshes and rebuild only when the lifecycle control signature truly changes.

5. **Language interaction**
   - visible only for ALIVE/AWAKE pet states, matching Phase 7;
   - English-only input;
   - Send uses `speak_to_pet` exactly;
   - show non-verbal reaction feedback;
   - intent/topics/rule IDs are engineering diagnostics and should move to the developer panel rather than dominate the normal player UI;
   - no generated pet sentence may be shown.

6. **Developer tools**
   - raw inspector, schema/timestamps/event diagnostics and Time Machine controls must be hidden from the normal player-facing surface by default;
   - retain them behind a clearly separated developer/debug panel or debug-only affordance;
   - debug controls must remain usable in development/tests;
   - toggling or refreshing debug UI must never mutate authoritative state.

The implementation may use a root `ScrollContainer` or equivalent safe layout so the full experience remains reachable at 360×640 without inaccessible controls.

## Lifecycle presentation matrix

### INCUBATING egg

Show:

- egg placeholder;
- `Incubating` status;
- remaining time in a human-readable countdown;
- `Touch Egg` action.

Do not expose Hatch before READY.

### READY egg

Show:

- ready egg placeholder/state;
- `Ready to hatch` status;
- `Touch Egg`;
- `Hatch Egg`.

Do not auto-hatch.

### HATCHING

Show:

- hatching state;
- `Continue Hatching` only as the lifecycle progression action.

### ALIVE / AWAKE

Show:

- current growth-stage companion placeholder;
- six needs;
- current care actions;
- language input;
- current reaction feedback when present.

### ALIVE / SLEEPING

Show:

- sleeping companion state;
- needs remain readable;
- `Wake` as the context action;
- language input hidden;
- no implicit wake.

### ALIVE / CRITICAL

Keep the normal applicable awake/sleeping controls, but visibly and textually communicate CRITICAL status.

Phase 8 must not alter rescue semantics.

### DEAD

Show:

- dead companion placeholder/state;
- clear permanent-death status;
- final growth stage;
- death cause in user-readable form;
- `Memorialize Pet` action;
- no care or language controls.

### MEMORIAL

When a snapshot-backed memorial exists and no active subject exists, show a memorial summary including at least:

- pet name/label;
- final growth stage;
- born/died timestamps in a readable presentation form or a stable fallback if human date formatting is intentionally deferred;
- death cause;
- `New Egg` only when the existing Application eligibility allows it.

Historical-count-only memorial state must not expose an impossible New Egg action.

### NONE

No impossible pet/egg actions.

## Companion placeholder visual contract

Phase 8 must not depend on final pixel artwork.

Prefer a small Presentation abstraction such as `CompanionView` that renders a deterministic procedural placeholder with Godot primitives or locally authored zero-cost placeholder assets.

Requirements:

- no network asset download;
- no paid asset dependency;
- no external font dependency;
- no final sprite-production requirement;
- distinct visible state for `EGG`, `NEWBORN`, `CHILD`, `ADOLESCENT`, `ADULT`, sleeping and dead;
- CRITICAL remains an overlay/state indicator rather than a new biological state;
- memorial may reuse the final frozen companion representation with memorial framing;
- visual state is derived from the profile and never persisted separately.

Reaction keys from existing care/language outcomes may drive transient Presentation-only cues, but must not write into Domain/Infrastructure.

## User-facing feedback

Replace developer-style or verbose diagnostic feedback on the normal surface with concise fixed UI feedback.

Allowed examples include fixed labels such as:

- `Fed`
- `Drank`
- `Played`
- `Clean`
- `Sleeping`
- `Awake`
- `Reaction: HAPPY`

These are UI status labels, not generated pet speech.

Do not create conversational sentences spoken by the pet.

Application rejection reasons must still map to clear user-facing feedback without changing the underlying reason codes.

## Developer panel

Retain technical observability needed for development and acceptance tests, including as applicable:

- schema version;
- simulation timestamp / clock anomaly count;
- pet ID;
- growth metadata;
- relationship values;
- memory counts / last memory;
- recent events;
- Phase 7 language diagnostics;
- Time Machine controls `+10m`, `+1h`, `+8h`, `+1d`, `+7d`.

The panel is hidden by default from the player layout.

Tests may use a stable explicit seam to show it when needed.

## Theme / visual language

Create one consistent lightweight UI theme suitable for a pixel-oriented mobile pet MVP.

Requirements:

- built-in/default Godot font is acceptable;
- no font files or third-party visual packages;
- consistent panel spacing, button sizing and hierarchy;
- nearest-neighbor settings remain intact;
- critical/dead states remain readable without relying only on color;
- the UI must remain usable without final art.

The exact palette is Presentation-owned and not a gameplay contract.

## Project identity

Update the visible application/project naming away from `Pet Game Foundation` to the neutral working product name `Pet Game`.

Update README wording so it no longer claims the screen contains no pet gameplay.

Do not invent a commercial brand, store listing, icon set or marketing identity in Phase 8.

## Presentation architecture

A focused Presentation refactor is allowed and expected if it reduces the monolithic developer-screen structure.

Recommended decomposition may include abstractions such as:

- `CompanionView`
- needs/status view
- context action view
- language view
- developer panel
- a top-level screen/controller

However:

- do not move Domain rules into those views;
- do not duplicate Application action eligibility semantics;
- do not add a second authoritative UI state model;
- do not break accepted command/event/persistence contracts.

Maintain compatibility test seams where reasonable. If `FoundationScreen` is internally refactored or renamed, preserve a compatibility wrapper or update all tests deliberately with equivalent coverage; do not silently delete existing lifecycle/button stability evidence.

## Read-only refresh contract

Ordinary UI refresh must remain read-only.

Repeated refreshes must not change:

- profile data;
- simulation timestamps;
- memory;
- relationship;
- language summaries;
- persistence write count.

Only explicit user/debug actions may invoke Application commands.

## No new persistence writes from animation

Presentation animation/tween/placeholder reactions must not trigger autosaves or candidate writes by themselves.

## Mandatory test matrix

At minimum add executable coverage for:

### Project / viewport

- project name is `Pet Game`;
- main viewport baseline remains `360 × 640`;
- nearest-neighbor rendering settings remain enabled as accepted;
- main scene boots successfully.

### Normal player surface

- raw inspector/debug timestamps are not visible by default;
- Time Machine controls are not part of the normal player surface;
- developer panel can be exposed through the explicit development/test seam;
- developer-panel refresh is read-only.

### Companion stage

- egg renders an egg presentation state;
- NEWBORN, CHILD, ADOLESCENT and ADULT map to distinct presentation states;
- sleeping maps to a sleeping visual state without changing activity;
- CRITICAL overlay/indicator appears while life remains ALIVE;
- DEAD maps to a dead visual state;
- memorial maps to memorial presentation;
- changing the visual state never mutates the profile.

### Needs

- ALIVE pet displays all six needs;
- values reflect authoritative profile updates after refresh;
- display does not mutate values;
- DEAD/EGG/MEMORIAL do not expose misleading live-care meters if the chosen design hides them.

### Lifecycle controls

Cover complete state matrix:

- INCUBATING → Touch Egg only;
- READY → Touch Egg + Hatch Egg;
- HATCHING → Continue Hatching;
- ALIVE/STABLE/AWAKE → care controls + language;
- ALIVE/CRITICAL/AWAKE → care controls + language + visible critical indicator;
- ALIVE/SLEEPING → Wake only and language hidden;
- DEAD → Memorialize only;
- MEMORIAL snapshot-backed → New Egg;
- historical-count-only memorial → no impossible New Egg;
- NONE → no impossible actions.

### Control stability

- value-only need changes keep context action node identity where lifecycle signature is unchanged;
- language interactions do not rebuild care controls;
- relationship/memory/reaction refresh does not rebuild lifecycle controls;
- lifecycle signature changes rebuild exactly as intended.

### Care feedback

For each existing care action, verify successful command still routes through `PetGameSession` and updates user-facing fixed feedback without changing accepted event/state semantics.

Rejected actions show a mapped user-facing status and preserve the original Application reason behavior.

### Language presentation

- ALIVE/AWAKE English input visible;
- sleeping/dead/egg/memorial/none hidden;
- successful send displays non-verbal reaction feedback;
- no generated pet dialogue;
- technical intent/topics/matched-rule diagnostics are hidden from normal surface and available only in developer diagnostics if retained;
- language send preserves care-control identity.

### Debug Time Machine

- hidden from normal player surface;
- development/test panel exposes existing controls;
- controls use existing `advance_debug` production path;
- debug time advancement still drives egg readiness, needs, growth, survival and death according to accepted semantics;
- debug controls do not implement alternate simulation math.

### Read-only rendering

- repeated normal refresh leaves authoritative profile exactly unchanged;
- repeated debug-panel refresh leaves profile unchanged;
- visual placeholder/reaction updates do not change profile or persistence count.

### Portrait usability

At 360×640:

- primary content hierarchy instantiates without errors;
- interactive controls remain reachable through the selected layout/scroll strategy;
- buttons use practical mobile target sizing;
- no required lifecycle action is permanently hidden behind a non-scrollable overflow.

### Regression

- retain all Phase 0–7 assertions;
- Phase 7 English-only language behavior remains unchanged;
- schema remains v8 and simulation v6;
- no new migration.

## Evidence and delivery

Create/update:

- `docs/PRESENTATION-CONTRACT.md`
- `docs/PRODUCT-CONTRACT.md`
- `docs/ARCHITECTURE.md`
- `docs/TESTING.md`
- `docs/ROADMAP.md`
- `README.md`
- `docs/reviews/PHASE-8-IMPLEMENTATION-REPORT.md`
- `docs/reviews/evidence/phase-8-tests.txt`
- `docs/reviews/evidence/phase-8-project-validation.txt`

Run:

- `godot --headless --path . -s res://tests/test_runner.gd`
- `godot --headless --path . --editor --quit`
- `godot --headless --path . --quit-after 1`

Accepted Phase 7 baseline is **1002 passed / 0 failed**. Phase 8 must retain 0 failures and increase executable coverage.

Push implementation to `codex/phase-8-product-polish` and open a PR against `main`. Do not merge.

## Explicit non-goals

Phase 8 does not include:

- new care mechanics;
- new lifecycle states;
- schema or simulation changes;
- pet naming flow;
- inventory;
- currency;
- achievements;
- quests;
- breeding/genetics/evolution choices;
- new relationship mechanics;
- personality learning;
- generated dialogue;
- additional natural languages;
- LLM/ML inference;
- speech recognition/TTS;
- online/community/cloud sync;
- backend services;
- final pixel-art sprite production;
- final animation asset production;
- music/sound production;
- haptics;
- mobile store packaging/signing;
- analytics/ads/monetization;
- commercial branding/marketing assets.

Phase 9 remains the optional online phase and must not begin until Phase 8 passes independent acceptance and Human Gate merge.