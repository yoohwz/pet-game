# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain owns deterministic egg threshold transition and validation but has no clock/random/filesystem/UI dependency. Application owns issuance, durable IDs, hatching candidates, wall/monotonic coordination. Presentation rebuilds lifecycle controls only when the lifecycle signature changes; dynamic labels refresh without replacing action nodes.
