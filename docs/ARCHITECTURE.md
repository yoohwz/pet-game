# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain is pure/near-pure state, rules, events and simulation, and receives the balance dictionary explicitly. It must not import scenes, filesystem, networking, wall-clock APIs, animation, or random application services. Application owns monotonic anchors, in-memory advancement, explicit persistence boundaries, and wall-clock startup/resume reconciliation. Presentation invokes only application debug APIs.
