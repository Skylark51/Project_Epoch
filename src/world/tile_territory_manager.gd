class_name TileTerritoryManager
extends RefCounted

const STATE_VERSION := 2
const INITIAL_POPULATION := 120
const INITIAL_CLAIM_RADIUS := 1
const CITY_EXCLUSION_RADIUS := 2
const MIN_CITY_CENTER_DISTANCE := CITY_EXCLUSION_RADIUS + 1

var _state: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	_state = {
		"data_version": STATE_VERSION,
		"tiles": {},
		"settlements": {},
		"regions": {},
		"next_settlement_id": 1,
	}


func load_snapshot(source: Dictionary) -> void:
	if source.is_empty():
		reset()
		return
	_state = source.duplicate(true)
	var source_version := int(_state.get("data_version", 1))
	_state["data_version"] = source_version if source_version > STATE_VERSION else STATE_VERSION
	for key in ["tiles", "settlements", "regions"]:
		if _state.get(key, {}) is not Dictionary:
			_state[key] = {}
	_state["next_settlement_id"] = _normalized_next_settlement_id(
		int(_state.get("next_settlement_id", 1))
	)


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func has_capital(owner_id: String) -> bool:
	for settlement_value in _state.get("settlements", {}).values():
		if settlement_value is Dictionary:
			var settlement_record: Dictionary = settlement_value
			if (
				String(settlement_record.get("owner_id", "")) == owner_id
				and bool(settlement_record.get("is_capital", false))
			):
				return true
	return false


func can_found_initial_city(world_map, tile: Vector2i, owner_id: String) -> Dictionary:
	if has_capital(owner_id):
		return {
			"ok": false,
			"reason_code": "capital_exists",
			"reason": "이미 첫 도시가 세워져 있습니다.",
		}
	return can_found_city(world_map, tile, owner_id)


func can_found_city(world_map, tile: Vector2i, owner_id: String) -> Dictionary:
	if world_map == null:
		return {
			"ok": false,
			"reason_code": "world_map_unavailable",
			"reason": "세계 지도가 아직 준비되지 않았습니다.",
		}
	if owner_id.is_empty():
		return {
			"ok": false,
			"reason_code": "owner_missing",
			"reason": "도시를 세울 국가가 선택되지 않았습니다.",
		}
	if not world_map.contains(tile.x, tile.y):
		return {
			"ok": false,
			"reason_code": "out_of_bounds",
			"reason": "지도 바깥에는 도시를 세울 수 없습니다.",
		}
	var terrain_id := int(world_map.terrain_id(tile.x, tile.y))
	if not _is_settleable_terrain(terrain_id):
		return {
			"ok": false,
			"reason_code": "terrain_blocked",
			"reason": "바다·호수·산악 타일에는 도시를 세울 수 없습니다.",
		}
	var spacing := _city_spacing_check(tile)
	if not bool(spacing.get("ok", false)):
		return spacing
	if not tile_state(world_map, tile).is_empty():
		return {
			"ok": false,
			"reason_code": "tile_claimed",
			"reason": "이미 다른 영토가 차지한 타일입니다.",
		}
	if not settlement_at(world_map, tile).is_empty() or _static_city_occupies(world_map, tile):
		return {
			"ok": false,
			"reason_code": "city_occupied",
			"reason": "이미 도시가 존재하는 타일입니다.",
		}
	return {
		"ok": true,
		"reason_code": "ok",
		"minimum_city_center_distance": MIN_CITY_CENTER_DISTANCE,
	}


func found_initial_city(
	world_map,
	tile: Vector2i,
	owner_id: String,
	city_name: String,
	founded_turn := 1
) -> Dictionary:
	var validation := can_found_initial_city(world_map, tile, owner_id)
	if not bool(validation.get("ok", false)):
		return validation
	return _found_validated_city(
		world_map,
		tile,
		owner_id,
		city_name,
		{
			"is_capital": true,
			"settlement_type": "small_town",
			"population": INITIAL_POPULATION,
			"founded_turn": founded_turn,
		}
	)


func found_city(
	world_map,
	tile: Vector2i,
	owner_id: String,
	city_name: String,
	options: Dictionary = {}
) -> Dictionary:
	var validation := can_found_city(world_map, tile, owner_id)
	if not bool(validation.get("ok", false)):
		return validation
	return _found_validated_city(world_map, tile, owner_id, city_name, options)


func tile_state(world_map, tile: Vector2i) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {}
	return _state.get("tiles", {}).get(_tile_key(world_map, tile), {}).duplicate(true)


func settlement_at(world_map, tile: Vector2i) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {}
	for settlement_value in _state.get("settlements", {}).values():
		if settlement_value is Dictionary:
			var settlement_record: Dictionary = settlement_value
			if (
				int(settlement_record.get("column", -1)) == tile.x
				and int(settlement_record.get("row", -1)) == tile.y
			):
				return settlement_record.duplicate(true)
	return {}


func settlement(settlement_id: String) -> Dictionary:
	return _state.get("settlements", {}).get(settlement_id, {}).duplicate(true)


func region(region_id: String) -> Dictionary:
	return _state.get("regions", {}).get(region_id, {}).duplicate(true)


func region_at(world_map, tile: Vector2i) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {}
	return region(_region_id(world_map, tile))


func city_center_distance(first: Vector2i, second: Vector2i) -> int:
	return maxi(absi(first.x - second.x), absi(first.y - second.y))


func validate_state(world_map) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if world_map == null:
		errors.append("world_map_unavailable")
		return {"ok": false, "errors": errors, "warnings": warnings}
	if int(_state.get("data_version", 0)) > STATE_VERSION:
		errors.append("unsupported_state_version")
	var tiles: Dictionary = _state.get("tiles", {})
	var settlements: Dictionary = _state.get("settlements", {})
	var occupied_centers: Dictionary = {}
	for tile_key_value in tiles.keys():
		var tile_key := String(tile_key_value)
		var tile_value = tiles[tile_key_value]
		if tile_value is not Dictionary:
			errors.append("tile_record_not_dictionary:%s" % tile_key)
			continue
		var tile_record: Dictionary = tile_value
		var tile := Vector2i(
			int(tile_record.get("column", -1)),
			int(tile_record.get("row", -1))
		)
		if not world_map.contains(tile.x, tile.y):
			errors.append("tile_out_of_bounds:%s" % tile_key)
			continue
		if tile_key != _tile_key(world_map, tile):
			errors.append("tile_key_mismatch:%s" % tile_key)
		if String(tile_record.get("owner_id", "")).is_empty():
			errors.append("tile_owner_missing:%s" % tile_key)
		if String(tile_record.get("region_id", "")) != _region_id(world_map, tile):
			errors.append("tile_region_mismatch:%s" % tile_key)
		var linked_settlement_id := String(tile_record.get("settlement_id", ""))
		if not linked_settlement_id.is_empty():
			if not settlements.has(linked_settlement_id):
				errors.append("tile_settlement_missing:%s" % tile_key)
			else:
				var linked_settlement: Dictionary = settlements[linked_settlement_id]
				if (
					int(linked_settlement.get("column", -1)) != tile.x
					or int(linked_settlement.get("row", -1)) != tile.y
				):
					errors.append("tile_settlement_center_mismatch:%s" % tile_key)
	for settlement_key_value in settlements.keys():
		var settlement_key := String(settlement_key_value)
		var settlement_value = settlements[settlement_key_value]
		if settlement_value is not Dictionary:
			errors.append("settlement_record_not_dictionary:%s" % settlement_key)
			continue
		var settlement_record: Dictionary = settlement_value
		if String(settlement_record.get("id", "")) != settlement_key:
			errors.append("settlement_id_mismatch:%s" % settlement_key)
		if String(settlement_record.get("owner_id", "")).is_empty():
			errors.append("settlement_owner_missing:%s" % settlement_key)
		var center := Vector2i(
			int(settlement_record.get("column", -1)),
			int(settlement_record.get("row", -1))
		)
		if not world_map.contains(center.x, center.y):
			errors.append("settlement_out_of_bounds:%s" % settlement_key)
			continue
		var center_key := _tile_key(world_map, center)
		if occupied_centers.has(center_key):
			errors.append(
				"duplicate_city_center:%s:%s"
				% [String(occupied_centers[center_key]), settlement_key]
			)
		else:
			occupied_centers[center_key] = settlement_key
		var center_record: Dictionary = tiles.get(center_key, {})
		if center_record.is_empty():
			errors.append("settlement_center_tile_missing:%s" % settlement_key)
		elif String(center_record.get("settlement_id", "")) != settlement_key:
			errors.append("settlement_center_link_mismatch:%s" % settlement_key)
		if String(settlement_record.get("region_id", "")) != _region_id(world_map, center):
			errors.append("settlement_region_mismatch:%s" % settlement_key)
		for claimed_key_value in settlement_record.get("claimed_tile_keys", []):
			var claimed_key := String(claimed_key_value)
			if not tiles.has(claimed_key):
				errors.append(
					"settlement_claimed_tile_missing:%s:%s"
					% [settlement_key, claimed_key]
				)
				continue
			var claimed_tile: Dictionary = tiles[claimed_key]
			if String(claimed_tile.get("owner_id", "")) != String(
				settlement_record.get("owner_id", "")
			):
				errors.append(
					"settlement_claim_owner_mismatch:%s:%s"
					% [settlement_key, claimed_key]
				)
	var settlement_ids: Array = settlements.keys()
	for first_index in range(settlement_ids.size()):
		var first_id := String(settlement_ids[first_index])
		var first_value = settlements[first_id]
		if first_value is not Dictionary:
			continue
		var first_record: Dictionary = first_value
		var first_center := Vector2i(
			int(first_record.get("column", -1000000)),
			int(first_record.get("row", -1000000))
		)
		for second_index in range(first_index + 1, settlement_ids.size()):
			var second_id := String(settlement_ids[second_index])
			var second_value = settlements[second_id]
			if second_value is not Dictionary:
				continue
			var second_record: Dictionary = second_value
			var second_center := Vector2i(
				int(second_record.get("column", -2000000)),
				int(second_record.get("row", -2000000))
			)
			if city_center_distance(first_center, second_center) <= CITY_EXCLUSION_RADIUS:
				errors.append("city_spacing_violation:%s:%s" % [first_id, second_id])
	for region_key_value in _state.get("regions", {}).keys():
		var region_key := String(region_key_value)
		var region_value = _state.regions[region_key_value]
		if region_value is not Dictionary:
			errors.append("region_record_not_dictionary:%s" % region_key)
			continue
		var region_record: Dictionary = region_value
		for settlement_id_value in region_record.get("settlement_ids", []):
			var settlement_id := String(settlement_id_value)
			if not settlements.has(settlement_id):
				errors.append("region_settlement_missing:%s:%s" % [region_key, settlement_id])
			elif String(settlements[settlement_id].get("region_id", "")) != region_key:
				errors.append("region_settlement_mismatch:%s:%s" % [region_key, settlement_id])
	if int(_state.get("next_settlement_id", 0)) < 1:
		errors.append("next_settlement_id_invalid")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"tile_count": tiles.size(),
		"settlement_count": settlements.size(),
		"region_count": _state.get("regions", {}).size(),
	}


func _found_validated_city(
	world_map,
	tile: Vector2i,
	owner_id: String,
	city_name: String,
	options: Dictionary
) -> Dictionary:
	var settlement_id := _take_next_settlement_id()
	var region_id := _region_id(world_map, tile)
	var claimed_keys: Array[String] = []
	for row in range(tile.y - INITIAL_CLAIM_RADIUS, tile.y + INITIAL_CLAIM_RADIUS + 1):
		for column in range(
			tile.x - INITIAL_CLAIM_RADIUS,
			tile.x + INITIAL_CLAIM_RADIUS + 1
		):
			if not world_map.contains(column, row):
				continue
			var claim_tile := Vector2i(column, row)
			if not _can_claim_around_city(world_map, claim_tile):
				continue
			var key := _tile_key(world_map, claim_tile)
			var current: Dictionary = _state.tiles.get(key, {})
			if (
				not current.is_empty()
				and String(current.get("owner_id", "")) != owner_id
			):
				continue
			_state.tiles[key] = _make_tile_record(
				world_map,
				claim_tile,
				owner_id,
				settlement_id if claim_tile == tile else ""
			)
			claimed_keys.append(key)
	claimed_keys.sort()
	var settlement_record := {
		"id": settlement_id,
		"name": (
			city_name.strip_edges()
			if not city_name.strip_edges().is_empty()
			else "이름 없는 소도시"
		),
		"owner_id": owner_id,
		"column": tile.x,
		"row": tile.y,
		"region_id": region_id,
		"province_id": int(world_map.province_id(tile.x, tile.y)),
		"settlement_type": String(options.get("settlement_type", "small_town")),
		"stage": maxi(1, int(options.get("stage", 1))),
		"population": maxi(0, int(options.get("population", INITIAL_POPULATION))),
		"is_capital": bool(options.get("is_capital", false)),
		"founded_turn": maxi(1, int(options.get("founded_turn", 1))),
		"claimed_tile_keys": claimed_keys,
	}
	_state.settlements[settlement_id] = settlement_record
	_rebuild_regions()
	return {
		"ok": true,
		"reason_code": "ok",
		"settlement": settlement_record.duplicate(true),
		"claimed_tile_count": claimed_keys.size(),
		"region_count": _state.regions.size(),
		"minimum_city_center_distance": MIN_CITY_CENTER_DISTANCE,
	}


func _city_spacing_check(tile: Vector2i) -> Dictionary:
	var nearest_id := ""
	var nearest_distance := 1000000000
	for settlement_value in _state.get("settlements", {}).values():
		if settlement_value is not Dictionary:
			continue
		var settlement_record: Dictionary = settlement_value
		var center := Vector2i(
			int(settlement_record.get("column", -1000000)),
			int(settlement_record.get("row", -1000000))
		)
		var distance := city_center_distance(tile, center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = String(settlement_record.get("id", ""))
	if nearest_distance <= CITY_EXCLUSION_RADIUS:
		return {
			"ok": false,
			"reason_code": "city_spacing",
			"reason": "기존 도시 중심에서 최소 %d타일 떨어져야 합니다." % MIN_CITY_CENTER_DISTANCE,
			"blocking_settlement_id": nearest_id,
			"distance": nearest_distance,
			"minimum_city_center_distance": MIN_CITY_CENTER_DISTANCE,
		}
	return {
		"ok": true,
		"nearest_settlement_id": nearest_id,
		"distance": nearest_distance if not nearest_id.is_empty() else -1,
		"minimum_city_center_distance": MIN_CITY_CENTER_DISTANCE,
	}


func _make_tile_record(
	world_map,
	tile: Vector2i,
	owner_id: String,
	settlement_id: String
) -> Dictionary:
	return {
		"column": tile.x,
		"row": tile.y,
		"owner_id": owner_id,
		"region_id": _region_id(world_map, tile),
		"province_id": int(world_map.province_id(tile.x, tile.y)),
		"terrain_id": int(world_map.terrain_id(tile.x, tile.y)),
		"settlement_id": settlement_id,
		"worked": bool(tile_state(world_map, tile).get("worked", false)),
	}


func _rebuild_regions() -> void:
	var regions: Dictionary = {}
	for tile_value in _state.get("tiles", {}).values():
		if tile_value is not Dictionary:
			continue
		var tile_record: Dictionary = tile_value
		var region_id := String(tile_record.get("region_id", ""))
		if region_id.is_empty():
			continue
		if not regions.has(region_id):
			regions[region_id] = {
				"region_id": region_id,
				"province_id": int(tile_record.get("province_id", -1)),
				"tile_count": 0,
				"tile_owner_counts": {},
				"settlement_ids": [],
			}
		var entry: Dictionary = regions[region_id]
		entry["tile_count"] = int(entry.get("tile_count", 0)) + 1
		var owner_counts: Dictionary = entry.get("tile_owner_counts", {})
		var owner_id := String(tile_record.get("owner_id", ""))
		owner_counts[owner_id] = int(owner_counts.get(owner_id, 0)) + 1
		entry["tile_owner_counts"] = owner_counts
		regions[region_id] = entry
	for settlement_value in _state.get("settlements", {}).values():
		if settlement_value is not Dictionary:
			continue
		var settlement_record: Dictionary = settlement_value
		var region_id := String(settlement_record.get("region_id", ""))
		if not regions.has(region_id):
			continue
		var entry: Dictionary = regions[region_id]
		var ids: Array = entry.get("settlement_ids", [])
		ids.append(String(settlement_record.get("id", "")))
		ids.sort()
		entry["settlement_ids"] = ids
		regions[region_id] = entry
	_state["regions"] = regions


func _normalized_next_settlement_id(requested: int) -> int:
	var candidate := maxi(1, requested)
	while _state.get("settlements", {}).has("settlement_%d" % candidate):
		candidate += 1
	return candidate


func _take_next_settlement_id() -> String:
	var serial := _normalized_next_settlement_id(
		int(_state.get("next_settlement_id", 1))
	)
	var settlement_id := "settlement_%d" % serial
	_state["next_settlement_id"] = serial + 1
	return settlement_id


func _region_id(world_map, tile: Vector2i) -> String:
	var province_id := int(world_map.province_id(tile.x, tile.y))
	if province_id != -1:
		return "province_%d" % province_id
	return "frontier_%d_%d" % [
		tile.x / int(world_map.chunk_size),
		tile.y / int(world_map.chunk_size),
	]


func _tile_key(world_map, tile: Vector2i) -> String:
	return str(tile.y * int(world_map.width) + tile.x)


func _is_settleable_terrain(terrain_id: int) -> bool:
	return terrain_id > 3 and terrain_id not in [8, 13]


func _can_claim_around_city(world_map, tile: Vector2i) -> bool:
	return int(world_map.terrain_id(tile.x, tile.y)) >= 2


func _static_city_occupies(world_map, tile: Vector2i) -> bool:
	for city_value in world_map.cities:
		if city_value is Dictionary:
			var city: Dictionary = city_value
			if (
				bool(city.get("enabled", true))
				and floori(float(city.get("mapX", -1.0))) == tile.x
				and floori(float(city.get("mapY", -1.0))) == tile.y
			):
				return true
	return false
