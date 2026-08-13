# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain is pure/near-pure state, rules, events and simulation. It must not import scenes, Controls, filesystem, networking, wall-clock APIs, animation, or remote services. Application obtains wall and monotonic time, coordinates persistence and invokes Domain. Presentation only uses application APIs. Future MemoryService, LanguageInterpreter and CommunityGateway are documented seams, not Phase 0 runtime classes.
