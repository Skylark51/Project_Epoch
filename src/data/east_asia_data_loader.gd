class_name EastAsiaDataLoader
extends RefCounted

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/prototype_east_asia.json"
const GOVERNMENT_PROFILE_PATH := "res://data/governance/government_profiles.json"
const REBELLION_RULES_PATH := "res://data/governance/east_asia_rebellion_rules.json"
const REQUIRED_GROUP_TYPES := [
	"aristocracy",
	"military",
	"bureaucracy",
	"religious_estate",
	"local_populace",
]

var dataset: Dictionary = {}
var indexes: Dictionary = {}
var last_validation: Dictionary = {}

func load_prototype() -> Dictionary:
	return load_scenario(DEFAULT_SCENARIO_PATH)

func load_scenario(scenario_path: String) -> Dictionary:
	var scenario_result := _load_json(scenario_path)
	if not bool(scenario_result.get("ok", false)):
		return scenario_result
	var scenario: Dictionary = scenario_result.data
	var loaded := {"scenario": scenario}
	var errors: Array[String] = []
	for key_value in scenario.get("data_files", {}).keys():
		var key := String(key_value)
		var path := String(scenario.data_files[key])
		var result := _load_json(path)
		if not bool(result.get("ok", false)):
			errors.append(String(result.get("error", "Failed to load %s" % path)))
		else:
			loaded[key] = result.data

	# The foundation schema extends the legacy governance files without changing
	# the regression fixtures consumed by the existing prototype.
	var government_result := _load_json(GOVERNMENT_PROFILE_PATH)
	var rebellion_result := _load_json(REBELLION_RULES_PATH)
	if bool(government_result.get("ok", false)):
		loaded["government_types"] = government_result.data
	else:
		errors.append(String(government_result.get("error", "Failed to load government profiles")))
	if bool(rebellion_result.get("ok", false)):
		loaded["rebellion_rules"] = rebellion_result.data
	else:
		errors.append(String(rebellion_result.get("error", "Failed to load rebellion rules")))

	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	dataset = loaded
	indexes = _build_indexes(dataset)
	last_validation = validate_dataset(dataset, indexes)
	if not bool(last_validation.get("ok", false)):
		return last_validation
	return {
		"ok": true,
		"dataset": dataset,
		"indexes": indexes,
		"counts": last_validation.counts,
		"warnings": last_validation.warnings,
	}

func validate_dataset(source: Dictionary = dataset, source_indexes: Dictionary = indexes) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var ix := source_indexes if not source_indexes.is_empty() else _build_indexes(source)
	var countries: Dictionary = ix.get("countries", {})
	var provinces: Dictionary = ix.get("provinces", {})
	var characters: Dictionary = ix.get("characters", {})
	var houses: Dictionary = ix.get("houses", {})
	var regions: Dictionary = ix.get("regions", {})
	var points: Dictionary = ix.get("strategic_points", {})
	var governments: Dictionary = ix.get("government_types", {})
	var group_ids: Dictionary = {}

	_validate_unique_index_sizes(source, ix, errors)

	for region_value in regions.values():
		var region: Dictionary = region_value
		var region_id := String(region.get("region_id", ""))
		var parent_id := String(region.get("parent_region_id", ""))
		if parent_id != "" and not regions.has(parent_id):
			errors.append("Region %s references missing parent %s" % [region_id, parent_id])
		for child_value in region.get("subregions", []):
			var child_id := String(child_value)
			if not regions.has(child_id):
				errors.append("Region %s references missing subregion %s" % [region_id, child_id])
			elif String(regions[child_id].get("parent_region_id", "")) != region_id:
				errors.append("Region %s and subregion %s are not reciprocal" % [region_id, child_id])
		for province_value in region.get("province_ids", []):
			if not provinces.has(String(province_value)):
				errors.append("Region %s references missing province %s" % [region_id, province_value])

	for country_value in countries.values():
		var country: Dictionary = country_value
		var country_id := String(country.get("id", ""))
		if not governments.has(String(country.get("government_type", ""))):
			errors.append("Country %s references missing government type" % country_id)
		if not characters.has(String(country.get("ruler_character_id", ""))):
			errors.append("Country %s references missing ruler" % country_id)
		for province_value in country.get("starting_province_ids", []):
			var province_id := String(province_value)
			if not provinces.has(province_id):
				errors.append("Country %s references missing starting province %s" % [country_id, province_id])
			elif String(provinces[province_id].get("owner_faction_id", "")) != country_id:
				errors.append("Country %s does not own listed starting province %s" % [country_id, province_id])
		if not country.has("religion_profile"):
			errors.append("Country %s is missing religion_profile" % country_id)

	for province_value in provinces.values():
		var province: Dictionary = province_value
		var province_id := String(province.get("province_id", ""))
		for field in [
			"name", "region_id", "owner_faction_id", "controller_faction_id",
			"claimant_faction_ids", "control_progress_hidden", "control_stage",
			"governor_character_id", "governor_type", "core_settlement_id",
			"strategic_point_ids", "population", "resources", "culture_profile",
			"public_order_hidden", "rebellion_risk_hidden", "neighbors",
		]:
			if not province.has(field):
				errors.append("Province %s is missing field %s" % [province_id, field])
		if not regions.has(String(province.get("region_id", ""))):
			errors.append("Province %s references missing region" % province_id)
		for faction_key in ["owner_faction_id", "controller_faction_id"]:
			if not countries.has(String(province.get(faction_key, ""))):
				errors.append("Province %s references missing %s" % [province_id, faction_key])
		for claimant_value in province.get("claimant_faction_ids", []):
			if not countries.has(String(claimant_value)):
				errors.append("Province %s references missing claimant %s" % [province_id, claimant_value])
		var point_ids: Array = province.get("strategic_point_ids", [])
		if point_ids.size() < 5 or point_ids.size() > 8:
			errors.append("Province %s must have 5-8 strategic points" % province_id)
		for point_value in point_ids:
			var point_id := String(point_value)
			if not points.has(point_id):
				errors.append("Province %s references missing strategic point %s" % [province_id, point_id])
			elif String(points[point_id].get("province_id", "")) != province_id:
				errors.append("Strategic point %s belongs to another province" % point_id)
		if String(province.get("core_settlement_id", "")) not in point_ids:
			errors.append("Province %s core settlement is not a strategic point" % province_id)
		var governor_id := String(province.get("governor_character_id", ""))
		if not characters.has(governor_id):
			errors.append("Province %s has no valid named governor" % province_id)
		else:
			var governor: Dictionary = characters[governor_id]
			if String(governor.get("province_id", "")) != province_id:
				errors.append("Governor %s references another province" % governor_id)
			if String(governor.get("faction_id", "")) != String(province.get("owner_faction_id", "")):
				errors.append("Governor %s references another faction" % governor_id)
		for neighbor_value in province.get("neighbors", []):
			var neighbor_id := String(neighbor_value)
			if not provinces.has(neighbor_id):
				errors.append("Province %s references missing neighbor %s" % [province_id, neighbor_id])
			elif province_id not in provinces[neighbor_id].get("neighbors", []):
				errors.append("Asymmetric province adjacency: %s - %s" % [province_id, neighbor_id])

	for character_value in characters.values():
		var character: Dictionary = character_value
		var character_id := String(character.get("character_id", ""))
		if not houses.has(String(character.get("house_id", ""))):
			errors.append("Character %s references missing house" % character_id)
		if not countries.has(String(character.get("faction_id", ""))):
			errors.append("Character %s references missing faction" % character_id)
		var province_id := String(character.get("province_id", ""))
		if province_id != "" and not provinces.has(province_id):
			errors.append("Character %s references missing province" % character_id)

	for house_value in houses.values():
		var house: Dictionary = house_value
		if not countries.has(String(house.get("faction_id", ""))):
			errors.append("House %s references missing faction" % String(house.get("house_id", "")))

	var country_groups: Dictionary = source.get("political_groups", {}).get("country_groups", {})
	for country_id_value in countries.keys():
		var country_id := String(country_id_value)
		var groups: Array = country_groups.get(country_id, [])
		if groups.size() != REQUIRED_GROUP_TYPES.size():
			errors.append("Country %s must have five political groups" % country_id)
		var seen_types: Array[String] = []
		for group_value in groups:
			if group_value is not Dictionary:
				errors.append("Country %s has a non-object political group" % country_id)
				continue
			var group: Dictionary = group_value
			var group_id := String(group.get("group_id", ""))
			var group_type := String(group.get("group_type", ""))
			if group_ids.has(group_id):
				errors.append("Duplicate political group id %s" % group_id)
			group_ids[group_id] = true
			seen_types.append(group_type)
			for field in [
				"name", "influence_hidden", "satisfaction_hidden",
				"rebellion_risk_hidden", "mobilization_capacity", "active_causes",
				"demands", "reform_stance", "representative_character_id",
			]:
				if not group.has(field):
					errors.append("Political group %s is missing field %s" % [group_id, field])
			var representative_id := String(group.get("representative_character_id", ""))
			if not characters.has(representative_id):
				errors.append("Political group %s references missing representative" % group_id)
			elif String(characters[representative_id].get("faction_id", "")) != country_id:
				errors.append("Political group %s representative belongs to another faction" % group_id)
		for required_type in REQUIRED_GROUP_TYPES:
			if required_type not in seen_types:
				errors.append("Country %s is missing political group type %s" % [country_id, required_type])

	for point_value in points.values():
		var point: Dictionary = point_value
		if not provinces.has(String(point.get("province_id", ""))):
			errors.append("Strategic point %s references missing province" % String(point.get("point_id", "")))

	var identity_data: Dictionary = source.get("state_identity_candidates", {})
	for capital_value in identity_data.get("capital_candidates", []):
		if capital_value is Dictionary and not points.has(String(capital_value.get("point_id", ""))):
			errors.append("Capital candidate references missing strategic point %s" % String(capital_value.get("point_id", "")))

	if not bool(source.get("countries", {}).get("religion_balance_rule", {}).get("equal_performance_within_tier_and_type", false)):
		errors.append("Religion balance rule must preserve equal performance within tier and type")

	if String(source.get("scenario", {}).get("start_period", "")) != "undetermined_ancient_east_asia":
		warnings.append("Prototype scenario should remain independent from a fixed start year")

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"counts": {
			"regions": regions.size(),
			"countries": countries.size(),
			"provinces": provinces.size(),
			"strategic_points": points.size(),
			"characters": characters.size(),
			"houses": houses.size(),
			"political_groups": group_ids.size(),
			"government_types": governments.size(),
		},
	}

func register_with_governance(governance: Object) -> Dictionary:
	if dataset.is_empty():
		var loaded := load_prototype()
		if not bool(loaded.get("ok", false)):
			return loaded
	if not governance.has_method("register_faction") or not governance.has_method("register_province") or not governance.has_method("register_group"):
		return {"ok": false, "error": "Governance target does not expose the registration API"}
	for country_value in dataset.countries.get("countries", []):
		var country: Dictionary = country_value
		var faction := country.duplicate(true)
		faction["faction_id"] = String(country.get("id", ""))
		governance.register_faction(faction)
	for province_value in dataset.provinces.get("provinces", []):
		governance.register_province(province_value)
	for country_id_value in dataset.political_groups.get("country_groups", {}).keys():
		var country_id := String(country_id_value)
		for group_value in dataset.political_groups.country_groups[country_id]:
			governance.register_group(country_id, group_value)
	return {
		"ok": true,
		"factions": dataset.countries.get("countries", []).size(),
		"provinces": dataset.provinces.get("provinces", []).size(),
		"political_groups": indexes.get("political_groups", {}).size(),
	}

func get_country(country_id: String) -> Dictionary:
	return indexes.get("countries", {}).get(country_id, {}).duplicate(true)

func get_province(province_id: String) -> Dictionary:
	return indexes.get("provinces", {}).get(province_id, {}).duplicate(true)

func get_character(character_id: String) -> Dictionary:
	return indexes.get("characters", {}).get(character_id, {}).duplicate(true)

func get_strategic_point(point_id: String) -> Dictionary:
	return indexes.get("strategic_points", {}).get(point_id, {}).duplicate(true)

func _build_indexes(source: Dictionary) -> Dictionary:
	var result := {
		"regions": _index_array(source.get("regions", {}).get("regions", []), "region_id"),
		"countries": _index_array(source.get("countries", {}).get("countries", []), "id"),
		"provinces": _index_array(source.get("provinces", {}).get("provinces", []), "province_id"),
		"strategic_points": _index_array(source.get("provinces", {}).get("strategic_points", []), "point_id"),
		"characters": _index_array(source.get("characters", {}).get("characters", []), "character_id"),
		"houses": _index_array(source.get("characters", {}).get("houses", []), "house_id"),
		"government_types": _index_array(source.get("government_types", {}).get("government_types", []), "id"),
		"political_groups": {},
	}
	for groups_value in source.get("political_groups", {}).get("country_groups", {}).values():
		for group_value in groups_value:
			if group_value is Dictionary:
				result.political_groups[String(group_value.get("group_id", ""))] = group_value
	return result

func _index_array(values: Array, id_field: String) -> Dictionary:
	var result := {}
	for value in values:
		if value is Dictionary:
			result[String(value.get(id_field, ""))] = value
	return result

func _validate_unique_index_sizes(source: Dictionary, ix: Dictionary, errors: Array[String]) -> void:
	var definitions := [
		["regions", source.get("regions", {}).get("regions", [])],
		["countries", source.get("countries", {}).get("countries", [])],
		["provinces", source.get("provinces", {}).get("provinces", [])],
		["strategic_points", source.get("provinces", {}).get("strategic_points", [])],
		["characters", source.get("characters", {}).get("characters", [])],
		["houses", source.get("characters", {}).get("houses", [])],
		["government_types", source.get("government_types", {}).get("government_types", [])],
	]
	for definition in definitions:
		var key := String(definition[0])
		var values: Array = definition[1]
		if ix.get(key, {}).size() != values.size() or ix.get(key, {}).has(""):
			errors.append("%s contains a missing or duplicate id" % key)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Cannot find %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot open %s" % path}
	var parser := JSON.new()
	var code := parser.parse(file.get_as_text())
	if code != OK:
		return {"ok": false, "error": "%s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if parser.data is not Dictionary:
		return {"ok": false, "error": "%s root must be an object" % path}
	return {"ok": true, "data": parser.data}
