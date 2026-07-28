extends RefCounted

signal scenario_started(summary: Dictionary)
signal command_queued(command: Dictionary)
signal command_rejected(result: Dictionary)
signal turn_phase_completed(phase: String, entries: Array)
signal turn_completed(summary: Dictionary)
signal battle_resolved(result: Dictionary)
signal province_occupied(result: Dictionary)
signal diplomacy_changed(result: Dictionary)
signal country_eliminated(country_id: String)
signal save_completed(path: String)
signal load_completed(path: String)
