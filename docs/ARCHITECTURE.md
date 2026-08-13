# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain owns deterministic egg threshold transition but has no clock/random/filesystem/UI dependency. Application owns initial issuance, durable random IDs, player-present hatching candidate transactions, and wall/monotonic coordination. Infrastructure atomically saves the root lifecycle state.
