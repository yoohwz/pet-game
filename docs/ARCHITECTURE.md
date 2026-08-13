# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain owns deterministic egg threshold transition and validation but has no clock/random/filesystem/UI dependency. Application owns issuance, durable IDs, hatching candidates, wall/monotonic coordination. Presentation rebuilds the small lifecycle panel from Application state so state transitions are visible without a scene restart.
