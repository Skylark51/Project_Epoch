class_name EastAsiaWorldFoundation
extends RefCounted

const DataLoaderScript = preload("res://src/data/east_asia_data_loader.gd")
const ProvinceControlScript = preload("res://src/systems/east_asia_province_control_system.gd")
const RebellionScript = preload("res://src/systems/east_asia_rebellion_system.gd")

var loader := DataLoaderScript.new()
var province_control := ProvinceControlScript.new()
var rebellion := RebellionScript.new()

func load_prototype() -> Dictionary:
	return loader.load_prototype()

func register_with_governance(governance: Object) -> Dictionary:
	return loader.register_with_governance(governance)

func evaluate_province_control(province_id: String, factors: Dictionary) -> Dictionary:
	var province := loader.get_province(province_id)
	if province.is_empty():
		return {"ok": false, "error": "Unknown province %s" % province_id}
	return {"ok": true, "result": province_control.evaluate_world_control(province, factors)}

func decide_governor_response(province_id: String, war_context: Dictionary) -> Dictionary:
	var province := loader.get_province(province_id)
	if province.is_empty():
		return {"ok": false, "error": "Unknown province %s" % province_id}
	var governor := loader.get_character(String(province.get("governor_character_id", "")))
	if governor.is_empty():
		return {"ok": false, "error": "Province %s has no governor" % province_id}
	return {"ok": true, "result": province_control.decide_governor_response(governor, province, war_context)}

func coalition_eligibility(faction_id: String, groups: Array[Dictionary], context: Dictionary) -> Dictionary:
	var enriched := context.duplicate(true)
	enriched["faction_id"] = faction_id
	return rebellion.coalition_eligibility_with_rules(groups, enriched, loader.dataset.get("rebellion_rules", {}))

func create_coalition_rebellions(coalition: Dictionary, groups_by_id: Dictionary, origin_provinces: Array) -> Array[Dictionary]:
	return rebellion.create_separate_rebellions_from_coalition(coalition, groups_by_id, origin_provinces)

func evaluate_rebel_statehood(rebel_state: Dictionary, world_context: Dictionary) -> Dictionary:
	return rebellion.evaluate_statehood_with_rules(rebel_state, world_context, loader.dataset.get("rebellion_rules", {}))

func choose_rebel_state_identity(rebel_state: Dictionary, controlled_point_ids: Array, context: Dictionary = {}) -> Dictionary:
	return rebellion.choose_state_identity_from_catalog(
		rebel_state,
		loader.dataset.get("state_identity_candidates", {}),
		controlled_point_ids,
		context
	)

func api_snapshot() -> Dictionary:
	return {
		"scenario_id": String(loader.dataset.get("scenario", {}).get("scenario_id", "")),
		"counts": loader.last_validation.get("counts", {}).duplicate(true),
		"country_ids": loader.indexes.get("countries", {}).keys(),
		"province_ids": loader.indexes.get("provinces", {}).keys(),
	}
