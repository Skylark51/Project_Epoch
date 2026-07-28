extends RefCounted

const Loader = preload("res://src/data/data_loader.gd")
const Validator = preload("res://src/data/data_validator.gd")

func load_scenario(path: String, player_country_id: String = "") -> Dictionary:
	var scenario := Loader.load_dictionary(path)
	if scenario.has("_error"):
		return {"ok": false, "errors": [scenario._error]}
	var countries := Loader.load_array(str(scenario.get("countries_path", "")), "countries")
	var provinces := Loader.load_array(str(scenario.get("provinces_path", "")), "provinces")
	var validation := Validator.validate(countries, provinces, scenario)
	if not validation.valid:
		return {"ok": false, "errors": validation.errors, "warnings": validation.warnings}
	var selected := player_country_id
	if selected.is_empty():
		selected = str(scenario.get("default_player_country_id", countries[0].id))
	var country_ids := countries.map(func(item: Dictionary) -> String: return str(item.id))
	if selected not in country_ids:
		return {"ok": false, "errors": ["선택한 국가가 시나리오에 없습니다: %s" % selected]}
	var armies: Array[Dictionary] = []
	for province in provinces:
		var soldiers := int(province.get("army", 0))
		if soldiers > 0:
			armies.append({
				"id": "army_%s" % province.id, "army_id": "army_%s" % province.id,
				"owner_id": province.owner_id, "province_id": int(province.id),
				"soldiers": soldiers, "morale": 1.0, "organization": 1.0,
				"supply": 1.0, "movement_points": 1, "commander_bonus": 0.0
			})
	var balance := {
		"economy": Loader.load_dictionary("res://data/balance/economy.json"),
		"military": Loader.load_dictionary("res://data/balance/military.json"),
		"diplomacy": Loader.load_dictionary("res://data/balance/diplomacy.json")
	}
	return {"ok": true, "state": {
		"schema_version": 1, "scenario_id": scenario.id, "turn": 1,
		"date": scenario.get("start_date", {"year": 1000, "month": 1, "day": 1}),
		"player_country_id": selected, "random_seed": int(scenario.get("seed", 1)),
		"countries": countries, "provinces": provinces, "armies": armies,
		"relations": scenario.get("relations", {}), "treaties": scenario.get("treaties", []),
		"wars": scenario.get("wars", []), "balance": balance,
		"metadata": {"scenario_name": scenario.get("name", scenario.id)}
	}, "warnings": validation.warnings}
