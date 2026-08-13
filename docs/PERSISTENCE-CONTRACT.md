# Persistence Contract

Local data uses `user://profile.json`, with future `active/`, `memorials/`, `backup/`, and `sync/` paths. Root structures carry `schema_version: 1`. Save serializes and validates, writes/flushed a temp file, copies an existing valid canonical save to backup, then atomically renames temp to canonical. Corrupt/missing primary is distinguishable and a valid backup recovers. `SaveMigrator` is the migration seam; no hypothetical migration is implemented.
