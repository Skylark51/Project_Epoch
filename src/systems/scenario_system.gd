extends RefCounted

const Loader = preload("res://src/data/data_loader.gd")
const Validator = preload("res://src/data/data_validator.gd")
const EastAsiaDataLoader = preload("res://src/data/east_asia_data_loader.gd")

func load_scenario(path: String, player_country_id: String = "") -> Dictionary:
	var scenario := Loader.load_dictionary(path)
	if scenario.has("_error"):
		return {"ok": false, "errors": [scenario._error]}
	if scenario.has("data_files"):
		return _load_east_asia_scenario(path, scenario, player_country_id)
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
func _load_east_asia_scenario(path: String, scenario: Dictionary, player_country_id: String) -> Dictionary:
	var source_loader := EastAsiaDataLoader.new()
	var loaded: Dictionary = source_loader.load_scenario(path)
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "errors": loaded.get("errors", ["동아시아 시나리오 로드 실패"])}
	var dataset: Dictionary = loaded.get("dataset", {})
	var indexes: Dictionary = loaded.get("indexes", {})
	var playable_ids: Array = scenario.get("playable_country_ids", [])
	var source_provinces: Array = dataset.get("provinces", {}).get("provinces", [])
	var province_id_map := {}
	var included_provinces: Array[Dictionary] = []
	for province_value in source_provinces:
		if province_value is not Dictionary:
			continue
		var province: Dictionary = province_value
		if String(province.get("owner_faction_id", "")) not in playable_ids:
			continue
		province_id_map[String(province.get("province_id", ""))] = included_provinces.size() + 1
		included_provinces.append(province)

	var countries: Array[Dictionary] = []
	var colors := ["#496E9C", "#A55B4B", "#C59B45", "#577D62", "#8464A0", "#4E8E88", "#8C6D4F", "#6F7895", "#B07955", "#708B4D", "#9A5F75"]
	var country_groups: Dictionary = dataset.get("political_groups", {}).get("country_groups", {})
	for country_value in dataset.get("countries", {}).get("countries", []):
		if country_value is not Dictionary:
			continue
		var source: Dictionary = country_value
		var country_id := String(source.get("id", ""))
		if country_id not in playable_ids:
			continue
		var starting_ids: Array = source.get("starting_province_ids", [])
		if starting_ids.is_empty() or not province_id_map.has(String(starting_ids[0])):
			continue
		var population := 0
		for province in included_provinces:
			if String(province.get("owner_faction_id", "")) == country_id:
				population += int(province.get("population", 0))
		var administration := int(source.get("administration_capacity", 30))
		countries.append({
			"id": country_id,
			"name": source.get("name", country_id),
			"color": colors[countries.size() % colors.size()],
			"capital_province_id": int(province_id_map[String(starting_ids[0])]),
			"government_id": source.get("government_type", "tribal_confederation"),
			"treasury": 120.0 + float(administration) * 2.0,
			"debt": 0.0,
			"manpower": maxi(800, int(population / 40.0)),
			"stability": float(source.get("legitimacy_hidden", 55.0)),
			"war_exhaustion": 0.0,
			"technology": {
				"administration": clampi(int(administration / 25.0), 1, 3),
				"economy": 1 if administration < 50 else 2,
				"military": 2 if "mounted_warfare" in source.get("technology_tags", []) else 1,
			},
			"technology_tags": source.get("technology_tags", []).duplicate(true),
			"authority_hidden": source.get("authority_hidden", 55.0),
			"legitimacy_hidden": source.get("legitimacy_hidden", 55.0),
			"administration_capacity": administration,
			"governance_groups": country_groups.get(country_id, []).duplicate(true),
			"tax_rate": 0.24,
			"ai_profile": "aggressive" if String(source.get("government_type", "")) == "military_governorate" else "balanced",
			"alive": true,
		})

	var provinces: Array[Dictionary] = []
	var point_index: Dictionary = indexes.get("strategic_points", {})
	var character_index: Dictionary = indexes.get("characters", {})
	for source in included_provinces:
		var source_id := String(source.get("province_id", ""))
		var numeric_id := int(province_id_map[source_id])
		var point_names: Array[String] = []
		var has_port := false
		var has_mountain := false
		var fort_level := 0
		for point_id_value in source.get("strategic_point_ids", []):
			var point: Dictionary = point_index.get(String(point_id_value), {})
			if point.is_empty():
				continue
			point_names.append(String(point.get("name", point_id_value)))
			var point_type := String(point.get("point_type", ""))
			has_port = has_port or point_type == "port"
			has_mountain = has_mountain or point_type in ["mountain_fortress", "mountain_pass"]
			if point_type in ["fortress", "mountain_fortress"]:
				fort_level = maxi(fort_level, 2 if point_type == "mountain_fortress" else 1)
		var resources: Dictionary = source.get("resources", {})
		var resource_total := 0.0
		for value in resources.values():
			resource_total += float(value)
		var governor: Dictionary = character_index.get(String(source.get("governor_character_id", "")), {})
		var neighbor_ids: Array[int] = []
		for neighbor_value in source.get("neighbors", []):
			var neighbor_id := String(neighbor_value)
			if province_id_map.has(neighbor_id):
				neighbor_ids.append(int(province_id_map[neighbor_id]))
		var owner_id := String(source.get("owner_faction_id", ""))
		var is_capital := false
		for country in countries:
			if String(country.get("id", "")) == owner_id and int(country.get("capital_province_id", -1)) == numeric_id:
				is_capital = true
				break
		var public_order := float(source.get("public_order_hidden", 60.0))
		var personality_traits: Array = governor.get("personality_traits", ["pragmatic"])
		provinces.append({
			"id": numeric_id,
			"source_province_id": source_id,
			"name": source.get("name", source_id),
			"owner_id": owner_id,
			"controller_id": source.get("controller_faction_id", owner_id),
			"population": int(source.get("population", 0)),
			"economy": maxf(12.0, resource_total / 12.0),
			"development": clampi(int(float(source.get("population", 0)) / 26000.0), 1, 3),
			"tax_efficiency": 0.5 + public_order / 200.0,
			"manpower": maxi(500, int(float(source.get("population", 0)) / 45.0)),
			"terrain": "coast" if has_port else ("hills" if has_mountain else "plains"),
			"fort_level": fort_level,
			"unrest": maxf(0.0, 100.0 - public_order),
			"army": 1400 if is_capital else 700,
			"neighbors": neighbor_ids,
			"capital": is_capital,
			"coastal": has_port,
			"polygon": _east_asia_polygon(source_id, numeric_id),
			"control_progress_hidden": source.get("control_progress_hidden", 100.0),
			"strategic_point_ids": source.get("strategic_point_ids", []).duplicate(true),
			"strategic_point_names": point_names,
			"governor_character_id": source.get("governor_character_id", ""),
			"governor_name": governor.get("name", "지방관"),
			"governor_type": governor.get("governor_type", source.get("governor_type", "appointed_governor")),
			"governor_personality": String(personality_traits[0]) if not personality_traits.is_empty() else "pragmatic",
			"governor_loyalty": governor.get("loyalty_hidden", 60.0),
			"governor_ambition": governor.get("ambition_hidden", 40.0),
			"governor_administration": governor.get("administration", 50.0),
			"governor_military": governor.get("military", 45.0),
		})

	var normalized_scenario := {
		"id": scenario.get("scenario_id", "prototype_east_asia"),
		"name": scenario.get("name", "고대 동아시아 기반 시나리오"),
	}
	var validation := Validator.validate(countries, provinces, normalized_scenario)
	if not validation.valid:
		return {"ok": false, "errors": validation.errors, "warnings": validation.warnings}
	var selected := player_country_id
	if selected.is_empty():
		selected = String(scenario.get("default_player_country_id", countries[0].id))
	if countries.all(func(country: Dictionary) -> bool: return String(country.id) != selected):
		return {"ok": false, "errors": ["선택한 국가가 시나리오에 없습니다: %s" % selected]}
	var armies: Array[Dictionary] = []
	for province in provinces:
		var soldiers := int(province.get("army", 0))
		if soldiers > 0:
			armies.append({
				"id": "army_%s" % province.id,
				"army_id": "army_%s" % province.id,
				"owner_id": province.owner_id,
				"province_id": int(province.id),
				"soldiers": soldiers,
				"morale": 1.0,
				"organization": 1.0,
				"supply": 1.0,
				"movement_points": 1,
				"commander_bonus": 0.0,
			})
	var balance := {
		"economy": Loader.load_dictionary("res://data/balance/economy.json"),
		"military": Loader.load_dictionary("res://data/balance/military.json"),
		"diplomacy": Loader.load_dictionary("res://data/balance/diplomacy.json"),
	}
	return {"ok": true, "state": {
		"schema_version": 2,
		"scenario_id": normalized_scenario.id,
		"turn": 1,
		"date": scenario.get("start_date", {"year": 300, "month": 1, "day": 1}),
		"player_country_id": selected,
		"random_seed": int(scenario.get("seed", 20260729)),
		"countries": countries,
		"provinces": provinces,
		"armies": armies,
		"relations": {},
		"treaties": [],
		"wars": [],
		"balance": balance,
		"metadata": {
			"scenario_name": normalized_scenario.name,
			"source": "east_asia_world_foundation",
			"prototype": true,
		},
	}, "warnings": loaded.get("warnings", [])}

func _east_asia_polygon(source_id: String, fallback_index: int) -> Array:
	var centers := {
		"liaodong_corridor": Vector2(115, 135),
		"guknae_basin": Vector2(275, 125),
		"pyongyang_basin": Vector2(285, 245),
		"qingzhou_corridor": Vector2(75, 385),
		"han_river_basin": Vector2(305, 365),
		"yeongsan_basin": Vector2(190, 500),
		"gyeongju_basin": Vector2(445, 455),
		"daegaya_basin": Vector2(335, 475),
		"aragaya_basin": Vector2(285, 555),
		"guya_basin": Vector2(395, 555),
		"tsukushi_plain": Vector2(650, 505),
		"kibi_plain": Vector2(840, 430),
		"yamato_basin": Vector2(1030, 465),
	}
	var fallback := Vector2(70 + (fallback_index % 4) * 220, 80 + int(fallback_index / 4.0) * 150)
	var center: Vector2 = centers.get(source_id, fallback)
	var width := 72.0
	var height := 52.0
	return [
		[center.x - width, center.y],
		[center.x - width * 0.45, center.y - height],
		[center.x + width * 0.45, center.y - height],
		[center.x + width, center.y],
		[center.x + width * 0.45, center.y + height],
		[center.x - width * 0.45, center.y + height],
	]
