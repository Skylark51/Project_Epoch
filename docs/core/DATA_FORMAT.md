# Data and modding format

Data is separate from code under `data/{countries,provinces,scenarios,governments,balance,events,ai_profiles}`.
The included `sample_campaign` uses three countries and nine Provinces. IDs are
stable; Province neighbor relations must be symmetric; each living country has one
capital and every owner/controller must exist.

Save schema version 2 stores scenario ID, turn/date, countries, Provinces, armies,
relations, treaties, wars, queued commands, balance snapshot, random seed and the
versioned `governance_state` envelope in one `user://autosave.json` file.
`SaveManager.migrate()` upgrades version 0 by adding the command queue, then upgrades
version 1 by adding an empty governance state for safe legacy loading.

`src/importers/aocii_importer.gd` inspects a user-selected ZIP-compatible EGG locally
and classifies paths. `convert_records()` maps already decoded records into the
Project Epoch schema. No original assets are copied or shipped. No accessible
`AoCII(1).egg` was found during this work, so field mapping is conservative and the
independent sample remains the executable fallback.
