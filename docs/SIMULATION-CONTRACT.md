# Simulation Contract

`SimulationKernel.simulate(profile, from_timestamp, to_timestamp)` takes explicit UTC seconds and produces new state plus events deterministically. It is frame-rate, presentation and network independent. Offline reconciliation calls this same path using saved `last_simulated_at`. Negative wall time yields zero elapsed and increments `clock_anomaly_count`; no state moves backwards. The kernel uses additive formula-style advancement, not per-second loops. Segmented and one-step advances must match within 0.0001.
