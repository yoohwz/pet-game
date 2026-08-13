# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain is pure/near-pure state, rules, events and simulation, and receives the balance dictionary explicitly. It must not import scenes, filesystem, networking, wall-clock APIs, animation, or random application services. Application selects text balance data, owns monotonic session anchors and wall-clock startup/resume reconciliation, and coordinates autosave. Presentation invokes only application debug APIs.
