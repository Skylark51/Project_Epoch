extends RefCounted

const CURRENT_SCHEMA_VERSION := 2
var schema_version := CURRENT_SCHEMA_VERSION
var scenario_id := ""
var turn := 1
var date := {"year": 1000, "month": 1, "day": 1}
var player_country_id := ""
var random_seed := 1
var countries := {}
var provinces := {}
var armies := {}
var relations := {}
var treaties: Array = []
var wars := {}
var balance := {}
var command_queue := {"commands": [], "next_id": 1}
var governance_state := {}
var notifications: Array = []
var ui_preferences := {}
var metadata := {}

func from_dict(data: Dictionary) -> void:
	schema_version = CURRENT_SCHEMA_VERSION
	scenario_id = str(data.get("scenario_id", ""))
	turn = int(data.get("turn", 1))
	date = data.get("date", date).duplicate(true)
	player_country_id = str(data.get("player_country_id", ""))
	random_seed = int(data.get("random_seed", 1))
	countries = _key_by_id(data.get("countries", {}), false)
	provinces = _key_by_id(data.get("provinces", {}), true)
	armies = _key_by_id(data.get("armies", {}), false)
	relations = data.get("relations", {}).duplicate(true)
	treaties = data.get("treaties", []).duplicate(true)
	wars = _key_by_id(data.get("wars", {}), false)
	balance = data.get("balance", {}).duplicate(true)
	command_queue = data.get("command_queue", command_queue).duplicate(true)
	governance_state = data.get("governance_state", {}).duplicate(true)
	notifications = data.get("notifications", []).duplicate(true)
	ui_preferences = data.get("ui_preferences", {}).duplicate(true)
	metadata = data.get("metadata", {}).duplicate(true)

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version, "scenario_id": scenario_id, "turn": turn,
		"date": date.duplicate(true), "player_country_id": player_country_id,
		"random_seed": random_seed, "countries": countries.duplicate(true),
		"provinces": provinces.duplicate(true), "armies": armies.duplicate(true),
		"relations": relations.duplicate(true), "treaties": treaties.duplicate(true),
		"wars": wars.duplicate(true), "balance": balance.duplicate(true),
		"command_queue": command_queue.duplicate(true),
		"governance_state": governance_state.duplicate(true),
		"notifications": notifications.duplicate(true),
		"ui_preferences": ui_preferences.duplicate(true),
		"metadata": metadata.duplicate(true)
	}

func owned_provinces(country_id: String) -> Array[int]:
	var result: Array[int] = []
	for id in provinces:
		if str(provinces[id].get("owner_id", "")) == country_id:
			result.append(int(id))
	return result

func controlled_provinces(country_id: String) -> Array[int]:
	var result: Array[int] = []
	for id in provinces:
		if str(provinces[id].get("controller_id", "")) == country_id:
			result.append(int(id))
	return result

func is_country_alive(country_id: String) -> bool:
	return countries.has(country_id) and not owned_provinces(country_id).is_empty()

static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _key_by_id(value: Variant, numeric: bool) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value:
			result[int(key) if numeric else str(key)] = value[key].duplicate(true)
	elif value is Array:
		for item in value:
			var key: Variant = int(item.get("id", -1)) if numeric else str(item.get("id", ""))
			result[key] = item.duplicate(true)
	return result
