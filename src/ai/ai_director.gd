extends RefCounted

const Evaluator = preload("res://src/ai/ai_country_evaluator.gd")
const EconomyPlanner = preload("res://src/ai/ai_economy_planner.gd")
const DiplomacyPlanner = preload("res://src/ai/ai_diplomacy_planner.gd")
const MilitaryPlanner = preload("res://src/ai/ai_military_planner.gd")
const PeacePlanner = preload("res://src/ai/ai_peace_planner.gd")
var evaluator := Evaluator.new()
var economy := EconomyPlanner.new()
var diplomacy := DiplomacyPlanner.new()
var military := MilitaryPlanner.new()
var peace := PeacePlanner.new()

func plan_all(state) -> Array:
	var commands := []
	for country_id in state.countries:
		if country_id == state.player_country_id or not state.is_country_alive(country_id):
			continue
		var evaluation := evaluator.evaluate(state, country_id)
		commands.append_array(peace.plan(state, evaluation))
		commands.append_array(diplomacy.plan(state, evaluation))
		commands.append_array(economy.plan(state, evaluation))
		commands.append_array(military.plan(state, evaluation))
	return commands
