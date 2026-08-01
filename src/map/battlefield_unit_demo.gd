class_name BattlefieldUnitDemo
extends RefCounted

## Visual-only fallback for the prototype scenario. It never writes to game
## state and disappears as soon as the core supplies real army groups.

static func fallback_groups(provinces: Dictionary, world_map) -> Array[Dictionary]:
	if world_map == null:
		return []
	var by_source := _province_by_source(provinces)
	var groups: Array[Dictionary] = []
	var specs := [
		{
			"id": "demo_goguryeo_shieldwall",
			"source_province_id": "guknae_basin",
			"owner_id": "goguryeo",
			"soldiers": 1360,
			"visual_type": "infantry",
			"facing": 1,
			"units": [{"unit_id": "spearman", "strength": 900}, {"unit_id": "shield_infantry", "strength": 460}]
		},
		{
			"id": "demo_frontier_bowline",
			"source_province_id": "qingzhou_corridor",
			"owner_id": "northern_china_frontier",
			"soldiers": 1120,
			"visual_type": "archer",
			"facing": -1,
			"units": [{"unit_id": "archer", "strength": 820}, {"unit_id": "levy_infantry", "strength": 300}]
		}
	]
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var province: Dictionary = by_source.get(String(spec.source_province_id), {})
		var world_position := _province_position(province)
		if province.is_empty() or not _is_land(world_map, world_position):
			push_warning("Battlefield unit demo skipped invalid land anchor: %s" % String(spec.source_province_id))
			continue
		var group := spec.duplicate(true)
		group.erase("source_province_id")
		group["world_position"] = world_position
		group["is_demo"] = true
		groups.append(group)
	return groups


static func _province_by_source(provinces: Dictionary) -> Dictionary:
	var result := {}
	for province_value in provinces.values():
		if province_value is not Dictionary:
			continue
		var province: Dictionary = province_value
		var source_id := String(province.get("source_province_id", ""))
		if not source_id.is_empty():
			result[source_id] = province
	return result


static func _province_position(province: Dictionary) -> Vector2:
	var center = province.get("map_center", [])
	if center is Array and center.size() >= 2:
		return Vector2(float(center[0]), float(center[1]))
	if center is Vector2:
		return center
	return Vector2.ZERO


static func _is_land(world_map, world_position: Vector2) -> bool:
	var tile: Vector2i = world_map.tile_at_world(world_position)
	var terrain: int = int(world_map.terrain_id(tile.x, tile.y))
	return terrain >= 3 and terrain != 12 and terrain != 13
