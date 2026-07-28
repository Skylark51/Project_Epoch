extends RefCounted

const FILES := {
	"regions": "res://data/world/regions.json",
	"factions": "res://data/world/factions.json",
	"terrains": "res://data/world/terrains.json",
	"buildings": "res://data/world/buildings.json",
	"settlements": "res://data/world/settlements.json",
	"networks": "res://data/world/networks.json",
	"balance": "res://data/world/world_balance.json"
}

func load_catalog() -> Dictionary:
	var catalog := {}
	var errors: Array[String] = []
	for key in FILES:
		var result := _load_json(FILES[key])
		if not result.ok:
			errors.append(result.error)
		else:
			catalog[key] = result.data
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var validation := validate_catalog(catalog)
	if not validation.ok:
		return validation
	return {"ok": true, "catalog": catalog, "warnings": validation.warnings}

func validate_catalog(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var faction_ids := {}
	for item in catalog.factions.get("factions", []):
		var faction: Dictionary = item
		var id := String(faction.get("faction_id", ""))
		if id.is_empty() or faction_ids.has(id):
			errors.append("Faction ID missing or duplicated: %s" % id)
		faction_ids[id] = true
	var region_ids := {}
	for item in catalog.regions.get("regions", []):
		var region: Dictionary = item
		var id := String(region.get("id", ""))
		if id.is_empty() or region_ids.has(id):
			errors.append("Region ID missing or duplicated: %s" % id)
		region_ids[id] = region
		for field in ["historical_name","display_name","modern_reference","region_group","terrain",
			"elevation_class","coast","resource_tags","initial_controller","historical_certainty",
			"adjacent_region_ids","x","y"]:
			if not region.has(field):
				errors.append("Region %s missing field: %s" % [id, field])
		if String(region.get("historical_certainty", "")) not in ["confirmed","probable","approximate","fictionalized"]:
			errors.append("Region %s has invalid historical_certainty" % id)
		if not faction_ids.has(String(region.get("initial_controller", ""))):
			errors.append("Region %s references missing faction" % id)
		if not catalog.terrains.terrains.has(String(region.get("terrain", ""))):
			errors.append("Region %s references missing terrain" % id)
	for id in region_ids:
		var region: Dictionary = region_ids[id]
		for adjacent_value in region.adjacent_region_ids:
			var adjacent := String(adjacent_value)
			if not region_ids.has(adjacent):
				errors.append("Region %s references missing adjacent region %s" % [id, adjacent])
			elif id not in region_ids[adjacent].adjacent_region_ids:
				errors.append("Asymmetric adjacency: %s - %s" % [id, adjacent])
	var building_ids := {}
	for item in catalog.buildings.get("buildings", []):
		var building: Dictionary = item
		var id := String(building.get("id", ""))
		if id.is_empty() or building_ids.has(id):
			errors.append("Building ID missing or duplicated: %s" % id)
		building_ids[id] = true
	if region_ids.size() < 40:
		warnings.append("World catalog has fewer than 40 regions")
	if faction_ids.size() < 12:
		errors.append("At least 12 factions are required")
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot open %s" % path}
	var parser := JSON.new()
	var code := parser.parse(file.get_as_text())
	if code != OK:
		return {"ok": false, "error": "%s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "%s root must be an object" % path}
	return {"ok": true, "data": parser.data}
