# Codex 1 → Codex 2 integration

```gdscript
const GameSession = preload("res://src/core/game_session.gd")
var game := GameSession.new()
var result := game.start_scenario(
    "res://data/scenarios/sample_campaign.json", "AUR")
game.submit_command("recruit", {"target_id": 1, "amount": 500})
var turn_result := game.end_turn()
var snapshot := game.get_public_snapshot()
game.save("user://campaign.json")
game.load("user://campaign.json")
```

Supported command types: `recruit`, `move`, `attack`, `develop`, `build_fort`,
`change_tax`, `declare_war`, `offer_peace`, `improve_relations`,
`form_alliance`, `break_alliance`, `create_vassal`, `release_vassal`.

Every command returns `{valid, reason?}` and queued commands also return `command`.
Peace payload example:

```gdscript
{"target_id":"BOR", "payload":{"terms":{
  "province_ids":[4], "reparations":50, "vassalize":false
}}}
```

Signals are exposed through `game.events`: `scenario_started`, `command_queued`,
`command_rejected`, `turn_phase_completed`, `turn_completed`, `battle_resolved`,
`province_occupied`, `diplomacy_changed`, `country_eliminated`, `save_completed`,
and `load_completed`. Codex 2 should connect UI presentation to these signals and
read snapshots. It should not mutate dictionaries returned by the core.

Autosave phase emits a structured request in the turn result; UI/session hosting
code decides the actual autosave path and calls `save()`.
