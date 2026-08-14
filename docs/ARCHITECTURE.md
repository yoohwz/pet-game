# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain owns validation and formula-based awake/sleep/survival simulation with explicit passive, care and survival configs. Application owns care, rescue, memorial and new-egg commands, clock synchronization, results/reasons and candidate persistence. Presentation owns stable state controls and non-persistent reaction text; it never applies biological rules. Domain has no filesystem, clock, UI or network dependency.
