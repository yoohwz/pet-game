# Persistence Contract

Local `user://profile.json` is schema v3 and atomically contains simulation, optional egg, and optional pet together. v2 NONE migrates with no egg and is issued one egg by Application at current wall time; v2 PET is preserved and never receives a concurrent egg. HATCHING stores its reserved identity before any pet exists. Completion saves a PET candidate atomically; save failure leaves the durable HATCHING state intact. Existing validated temp/backup recovery protections remain.
