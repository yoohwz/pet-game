# Simulation Contract

`SimulationKernel.simulate(profile, from_timestamp, to_timestamp, balance, lifecycle, care)` accepts explicit data. AWAKE pets deplete hunger/hydration/energy/hygiene; SLEEPING pets deplete hunger/hydration/hygiene while recovering energy to 100 over 8h. Mood and health remain unchanged; no survival/death behavior exists. Deterministic simulation IDs include simulation, passive-balance and care-balance versions plus subject/from/to.
