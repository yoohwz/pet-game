# Presentation Contract

Phase 8 presents the accepted offline game through a 360×640 portrait-first shell. `FoundationScreen` is a read-only projection of the authoritative `PetGameSession` profile: it owns layout, concise fixed feedback, stable controls and a deterministic procedural `CompanionView`, but no lifecycle, simulation, language, relationship, memory or persistence rules.

The normal surface shows a companion header/stage, readable six-need values for an ALIVE pet, and only the context actions already exposed by the Application contract. Visual state is derived each refresh: EGG, NEWBORN, CHILD, ADOLESCENT, ADULT, SLEEPING, DEAD and MEMORIAL are distinct; CRITICAL is a text-bearing overlay. Rendering, placeholder reactions and animations never write profile state or trigger persistence.

English input is visible only for ALIVE/AWAKE pets and calls `speak_to_pet`; the player receives a fixed non-verbal reaction label. No generated pet dialogue is displayed. Technical language diagnostics, raw profile data, event history and the Time Machine live in Developer Tools, hidden by default. Showing, hiding or refreshing that panel is read-only; its existing controls still call `advance_debug`.

Lifecycle controls rebuild only when the lifecycle/activity/survival signature changes. Value, reaction, language, relationship and memory refreshes preserve existing care-control nodes. Snapshot-backed memorials may expose New Egg only where the existing Application command permits it; historical-count-only memorials expose no impossible action.
