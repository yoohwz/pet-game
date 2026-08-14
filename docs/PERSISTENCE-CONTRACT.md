# Persistence Contract

Local `user://profile.json` is schema v4 and atomically includes optional pet activity state. v3 pets migrate to AWAKE with no sleep timestamp; v3 eggs/HATCHING reservations are preserved. Explicit care/sleep actions use candidate-save semantics: a persistence failure cannot commit the care effect or activity transition. Startup reconciles sleeping pets offline. Existing validated-temp and known-good backup guarantees remain.
