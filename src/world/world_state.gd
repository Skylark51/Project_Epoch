extends RefCounted

const SAVE_VERSION := 2
var save_version := SAVE_VERSION
var turn := 1
var date := {"year": 400, "month": 1}
var selected_faction_id := "GOG"
var regions := {}
var settlements := {}
var factions := {}
var terrains := {}
var buildings := {}
var connections := {}
var balance := {}
var influence := {}
var construction_queues := {}
var automation := {}
var camera_bookmarks := {}
var debug_log: Array[Dictionary] = []

func initialize(catalog: Dictionary, player_faction_id: String = "GOG") -> void:
	selected_faction_id = player_faction_id
	terrains = catalog.terrains.terrains.duplicate(true)
	balance = catalog.balance.duplicate(true)
	for item in catalog.factions.factions:
		var faction: Dictionary = item.duplicate(true)
		var id := String(faction.faction_id)
		factions[id] = faction
		faction["resources"] = faction.get("starting_resources", {}).duplicate(true)
	for item in catalog.regions.regions:
		var region: Dictionary = item.duplicate(true)
		var id := String(region.id)
		regions[id] = region
		region["controller_id"] = String(region.initial_controller)
		region["border_state"] = "controlled"
		region["influence_owner_id"] = String(region.initial_controller)
	for item in catalog.buildings.buildings:
		var building: Dictionary = item.duplicate(true)
		buildings[String(building.id)] = building
	for item in catalog.networks.connections:
		var connection: Dictionary = item.duplicate(true)
		connections[String(connection.id)] = connection
	_build_initial_settlements(catalog.settlements)
	for settlement_id in settlements:
		construction_queues[settlement_id] = []
		automation[settlement_id] = {"enabled": false, "focus": "balanced", "reserve_ratio": balance.get("auto_manager_reserve_ratio", 0.25)}
	log_event("world", "World initialized", {"regions": regions.size(), "factions": factions.size()})

func to_dict() -> Dictionary:
	return {"save_version":save_version,"turn":turn,"date":date.duplicate(true),
		"selected_faction_id":selected_faction_id,"regions":regions.duplicate(true),
		"settlements":settlements.duplicate(true),"factions":factions.duplicate(true),
		"terrains":terrains.duplicate(true),"buildings":buildings.duplicate(true),
		"connections":connections.duplicate(true),"balance":balance.duplicate(true),
		"influence":influence.duplicate(true),"construction_queues":construction_queues.duplicate(true),
		"automation":automation.duplicate(true),"camera_bookmarks":camera_bookmarks.duplicate(true),
		"debug_log":debug_log.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	save_version = int(data.get("save_version", SAVE_VERSION))
	turn = int(data.get("turn", 1))
	date = data.get("date", {"year":400,"month":1}).duplicate(true)
	selected_faction_id = String(data.get("selected_faction_id", "GOG"))
	regions = data.get("regions", {}).duplicate(true)
	settlements = data.get("settlements", {}).duplicate(true)
	factions = data.get("factions", {}).duplicate(true)
	terrains = data.get("terrains", {}).duplicate(true)
	buildings = data.get("buildings", {}).duplicate(true)
	connections = data.get("connections", {}).duplicate(true)
	balance = data.get("balance", {}).duplicate(true)
	influence = data.get("influence", {}).duplicate(true)
	construction_queues = data.get("construction_queues", {}).duplicate(true)
	automation = data.get("automation", {}).duplicate(true)
	camera_bookmarks = data.get("camera_bookmarks", {}).duplicate(true)
	debug_log = []
	for item in data.get("debug_log", []):
		debug_log.append(item)

func log_event(category: String, message: String, detail: Dictionary = {}) -> void:
	debug_log.append({"turn":turn,"category":category,"message":message,"detail":detail.duplicate(true)})
	if debug_log.size() > 300:
		debug_log.pop_front()

func _build_initial_settlements(config: Dictionary) -> void:
	var capitals: Array = config.get("capital_settlements", [])
	var fortress_ids: Array = config.get("mountain_fortresses", [])
	var defaults: Dictionary = config.get("default_resources", {})
	var overrides: Dictionary = config.get("overrides", {})
	for region in regions.values():
		var settlement_value: Variant = region.get("initial_settlement", null)
		if settlement_value == null or String(settlement_value).is_empty():
			continue
		var id := String(settlement_value)
		var override: Dictionary = overrides.get(id, {})
		var population := int(override.get("population", defaults.get("population", 900)))
		var tier := String(override.get("tier", "capital" if id in capitals else ("township" if population >= 3500 else "village")))
		var settlement_type := String(override.get("settlement_type", "mountain_fortress" if id in fortress_ids else "flat_city"))
		var resources := defaults.duplicate(true)
		resources.population = population
		settlements[id] = {
			"id":id,"name":String(override.get("name", region.display_name)),"region_id":String(region.id),
			"faction_id":String(region.controller_id),"tier":tier,"settlement_type":settlement_type,
			"resources":resources,"buildings":override.get("buildings", []).duplicate(true),
			"garrison":160 if settlement_type == "mountain_fortress" else 100,
			"damage":0.0,"sieges":{},"culture_strength":1.0,"auto_managed":false
		}
