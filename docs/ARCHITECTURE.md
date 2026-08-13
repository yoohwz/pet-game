# Architecture

`Presentation → Application → Domain`; Infrastructure implements persistence for Application. Domain owns validation and awake/sleep passive simulation with explicit configs. Application owns care commands, clock synchronization, results/reasons and candidate persistence. Presentation owns stable action controls and non-persistent reaction text; it never applies biological rules.
