# Simulation Contract

`SimulationKernel.simulate(profile, from_timestamp, to_timestamp, balance, lifecycle)` accepts explicit data. For an incubating egg it changes only `INCUBATING → READY` at the persisted 4h threshold and emits deterministic `egg_ready`; READY never auto-hatches. For pets it retains Phase 1 passive needs. Foreground monotonic anchors retain fractional remainders; offline/resume/debug share this kernel.
