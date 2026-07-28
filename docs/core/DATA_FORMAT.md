# Data and modding format

Data is separate from code under `data/{countries,provinces,scenarios,governments,balance,events,ai_profiles}`.
The included `sample_campaign` uses three countries and nine Provinces. IDs are
stable; Province neighbor relations must be symmetric; each living country has one
capital and every owner/controller must exist.

Save schema version 1 stores scenario ID, turn/date, countries, Provinces, armies,
relations, treaties, wars, queued commands, balance snapshot and random seed.
`SaveManager.migrate()` upgrades version 0 by adding the command queue.

`src/importers/aocii_importer.gd` inspects a user-selected ZIP-compatible EGG locally
and classifies paths. `convert_records()` maps already decoded records into the
Project Epoch schema. No original assets are copied or shipped. No accessible
`AoCII(1).egg` was found during this work, so field mapping is conservative and the
independent sample remains the executable fallback.
