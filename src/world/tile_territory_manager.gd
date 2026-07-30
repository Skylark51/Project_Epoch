class_name TileTerritoryManager
extends RefCounted

const STATE_VERSION := 5
const INITIAL_POPULATION := 120
const INITIAL_CLAIM_RADIUS := 1
const CITY_EXCLUSION_RADIUS := 2
const MIN_CITY_CENTER_DISTANCE := CITY_EXCLUSION_RADIUS + 1
const CITY_MAX_INFLUENCE_RADIUS := 2
const YIELD_KEYS := ["food", "production", "commerce", "security"]
const TERRAIN_BASE_YIELDS := {
	2: {"food": 1.0, "commerce": 1.0},
	3: {"food": 1.0, "commerce": 1.0},
	4: {"food": 2.0, "production": 1.0},
	5: {"food": 3.0},
	6: {"food": 1.0, "production": 2.0},
	7: {"food": 1.0, "production": 2.0},
	8: {"production": 2.0},
	9: {"production": 1.0, "commerce": 1.0},
	10: {"food": 2.0, "production": 1.0},
	11: {"food": 2.0, "commerce": 1.0},
	12: {"food": 2.0, "commerce": 2.0},
	13: {"food": 2.0, "commerce": 1.0},
}
const FACILITY_YIELDS_PER_LEVEL := {
	"farmland": {"food": 1.5},
	"pasture": {"food": 1.0, "production": 0.5},
	"fishing": {"food": 1.5, "commerce": 0.5},
	"lumber_camp": {"production": 1.5},
	"mine": {"production": 2.0},
	"workshop": {"production": 1.5},
	"market": {"commerce": 1.5},
	"fort": {"security": 1.0},
}

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
	_migrate_legacy_management_links()
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


func managed_tiles(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile_value in _state.get("tiles", {}).values():
		if tile_value is not Dictionary:
			continue
		var tile_record: Dictionary = tile_value
		if String(tile_record.get("managing_settlement_id", "")) == settlement_id:
			result.append(tile_record.duplicate(true))
	result.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			if int(first.get("row", -1)) == int(second.get("row", -1)):
				return int(first.get("column", -1)) < int(second.get("column", -1))
			return int(first.get("row", -1)) < int(second.get("row", -1))
	)
	return result


func expand_city_influence(
	world_map,
	settlement_id: String,
	target_radius: int = CITY_MAX_INFLUENCE_RADIUS
) -> Dictionary:
	if world_map == null:
		return {
			"ok": false,
			"reason_code": "world_map_unavailable",
			"reason": "세계 지도가 아직 준비되지 않았습니다.",
		}
	if not _state.get("settlements", {}).has(settlement_id):
		return {
			"ok": false,
			"reason_code": "settlement_missing",
			"reason": "영향권을 확장할 도시가 없습니다.",
		}
	if target_radius < INITIAL_CLAIM_RADIUS or target_radius > CITY_MAX_INFLUENCE_RADIUS:
		return {
			"ok": false,
			"reason_code": "radius_out_of_range",
			"reason": "도시 영향권 반경은 %d에서 %d까지만 허용됩니다."
			% [INITIAL_CLAIM_RADIUS, CITY_MAX_INFLUENCE_RADIUS],
		}
	var settlement_record: Dictionary = _state.settlements[settlement_id]
	var current_radius := int(
		settlement_record.get("influence_radius", INITIAL_CLAIM_RADIUS)
	)
	if target_radius < current_radius:
		return {
			"ok": false,
			"reason_code": "influence_cannot_shrink",
			"reason": "도시 영향권은 명시적인 영토 이전 없이 축소할 수 없습니다.",
		}
	var center := Vector2i(
		int(settlement_record.get("column", -1)),
		int(settlement_record.get("row", -1))
	)
	var owner_id := String(settlement_record.get("owner_id", ""))
	var claimed_lookup: Dictionary = {}
	for claimed_key_value in settlement_record.get("claimed_tile_keys", []):
		claimed_lookup[String(claimed_key_value)] = true
	var newly_claimed: Array[String] = []
	var blocked_by: Dictionary = {}
	for row in range(center.y - target_radius, center.y + target_radius + 1):
		for column in range(center.x - target_radius, center.x + target_radius + 1):
			var candidate := Vector2i(column, row)
			if city_center_distance(center, candidate) > target_radius:
				continue
			if not world_map.contains(candidate.x, candidate.y):
				continue
			if not _can_claim_around_city(world_map, candidate):
				continue
			var key := _tile_key(world_map, candidate)
			var current: Dictionary = _state.tiles.get(key, {})
			if not current.is_empty():
				var current_manager := String(
					current.get("managing_settlement_id", "")
				)
				if current_manager == settlement_id:
					claimed_lookup[key] = true
				elif not current_manager.is_empty():
					blocked_by[current_manager] = true
				continue
			_state.tiles[key] = _make_tile_record(
				world_map,
				candidate,
				owner_id,
				"",
				settlement_id
			)
			claimed_lookup[key] = true
			newly_claimed.append(key)
	var all_claimed: Array[String] = []
	for key_value in claimed_lookup.keys():
		all_claimed.append(String(key_value))
	all_claimed.sort()
	settlement_record["claimed_tile_keys"] = all_claimed
	settlement_record["influence_radius"] = target_radius
	_state.settlements[settlement_id] = settlement_record
	_rebuild_regions()
	var blocked_ids: Array[String] = []
	for blocked_id_value in blocked_by.keys():
		blocked_ids.append(String(blocked_id_value))
	blocked_ids.sort()
	return {
		"ok": true,
		"reason_code": "ok",
		"settlement_id": settlement_id,
		"influence_radius": target_radius,
		"newly_claimed_tile_keys": newly_claimed,
		"claimed_tile_count": all_claimed.size(),
		"blocked_by_settlement_ids": blocked_ids,
		"border_edges": border_edges(world_map, false, settlement_id),
	}


func border_edges(
	world_map,
	include_frontier: bool = false,
	settlement_id: String = ""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world_map == null:
		return result
	var tiles: Dictionary = _state.get("tiles", {})
	var offsets: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
	]
	for key_value in tiles.keys():
		var key := String(key_value)
		var tile_record: Dictionary = tiles[key_value]
		var first_manager := String(
			tile_record.get("managing_settlement_id", "")
		)
		if first_manager.is_empty():
			continue
		if not settlement_id.is_empty() and first_manager != settlement_id:
			continue
		var first_owner := String(tile_record.get("owner_id", ""))
		var tile := Vector2i(
			int(tile_record.get("column", -1)),
			int(tile_record.get("row", -1))
		)
		for offset in offsets:
			var neighbor := tile + offset
			if not world_map.contains(neighbor.x, neighbor.y):
				if include_frontier:
					result.append(
						_make_border_edge(
							tile,
							neighbor,
							first_manager,
							"",
							first_owner,
							"",
							"frontier"
						)
					)
				continue
			var neighbor_key := _tile_key(world_map, neighbor)
			var neighbor_record: Dictionary = tiles.get(neighbor_key, {})
			var second_manager := String(
				neighbor_record.get("managing_settlement_id", "")
			)
			if second_manager.is_empty():
				if include_frontier:
					result.append(
						_make_border_edge(
							tile,
							neighbor,
							first_manager,
							"",
							first_owner,
							"",
							"frontier"
						)
					)
				continue
			if second_manager == first_manager:
				continue
			if settlement_id.is_empty() and int(key) > int(neighbor_key):
				continue
			var second_owner := String(neighbor_record.get("owner_id", ""))
			result.append(
				_make_border_edge(
					tile,
					neighbor,
					first_manager,
					second_manager,
					first_owner,
					second_owner,
					(
						"national_border"
						if first_owner != second_owner
						else "city_management_border"
					)
				)
			)
	return result


func configure_tile_yield_sources(
	world_map,
	settlement_id: String,
	tile: Vector2i,
	special_resources: Array,
	facility_levels: Dictionary
) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {
			"ok": false,
			"reason_code": "tile_out_of_bounds",
			"reason": "생산 정보를 설정할 타일이 지도 안에 없습니다.",
		}
	var key := _tile_key(world_map, tile)
	var tile_record: Dictionary = _state.get("tiles", {}).get(key, {})
	if tile_record.is_empty():
		return {
			"ok": false,
			"reason_code": "tile_unclaimed",
			"reason": "도시 영향권 밖 타일에는 생산 정보를 설정할 수 없습니다.",
		}
	if String(tile_record.get("managing_settlement_id", "")) != settlement_id:
		return {
			"ok": false,
			"reason_code": "tile_managed_by_other_city",
			"reason": "다른 도시의 관리 타일입니다.",
		}
	var normalized_resources: Array[Dictionary] = []
	for resource_value in special_resources:
		if resource_value is not Dictionary:
			return {
				"ok": false,
				"reason_code": "special_resource_invalid",
				"reason": "특수 자원 정보는 사전 형식이어야 합니다.",
			}
		var resource: Dictionary = resource_value
		var resource_id := String(resource.get("id", ""))
		if resource_id.is_empty() or resource.get("yields", {}) is not Dictionary:
			return {
				"ok": false,
				"reason_code": "special_resource_invalid",
				"reason": "특수 자원에는 id와 생산량이 필요합니다.",
			}
		normalized_resources.append(
			{
				"id": resource_id,
				"yields": _normalized_yields(resource.get("yields", {})),
			}
		)
	var normalized_facilities: Dictionary = {}
	for facility_id_value in facility_levels.keys():
		var facility_id := String(facility_id_value)
		if not FACILITY_YIELDS_PER_LEVEL.has(facility_id):
			return {
				"ok": false,
				"reason_code": "facility_unknown",
				"reason": "등록되지 않은 타일 시설입니다: %s" % facility_id,
			}
		var level := int(facility_levels[facility_id_value])
		if level < 0:
			return {
				"ok": false,
				"reason_code": "facility_level_invalid",
				"reason": "시설 단계는 음수가 될 수 없습니다.",
			}
		if level > 0:
			normalized_facilities[facility_id] = level
	tile_record["special_resources"] = normalized_resources
	tile_record["facility_levels"] = normalized_facilities
	_state.tiles[key] = tile_record
	return {
		"ok": true,
		"reason_code": "ok",
		"tile_key": key,
		"special_resources": normalized_resources.duplicate(true),
		"facility_levels": normalized_facilities.duplicate(true),
	}


func set_yield_modifiers(
	settlement_id: String,
	city_modifiers: Dictionary,
	technology_modifiers: Dictionary
) -> Dictionary:
	if not _state.get("settlements", {}).has(settlement_id):
		return {
			"ok": false,
			"reason_code": "settlement_missing",
			"reason": "생산 보정을 설정할 도시가 없습니다.",
		}
	var settlement_record: Dictionary = _state.settlements[settlement_id]
	settlement_record["city_yield_modifiers"] = _normalized_modifiers(city_modifiers)
	settlement_record["technology_yield_modifiers"] = _normalized_modifiers(
		technology_modifiers
	)
	_state.settlements[settlement_id] = settlement_record
	return {
		"ok": true,
		"reason_code": "ok",
		"settlement_id": settlement_id,
		"city_yield_modifiers": settlement_record.city_yield_modifiers.duplicate(true),
		"technology_yield_modifiers":
			settlement_record.technology_yield_modifiers.duplicate(true),
	}


func tile_yield(world_map, tile: Vector2i) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {}
	var tile_record := tile_state(world_map, tile)
	if tile_record.is_empty():
		return {}
	var settlement_id := String(tile_record.get("managing_settlement_id", ""))
	var settlement_record: Dictionary = _state.get("settlements", {}).get(
		settlement_id,
		{}
	)
	var terrain_yields := _normalized_yields(
		TERRAIN_BASE_YIELDS.get(int(tile_record.get("terrain_id", 0)), {})
	)
	var special_resource_yields := _zero_yields()
	for resource_value in tile_record.get("special_resources", []):
		if resource_value is Dictionary:
			_add_yields(
				special_resource_yields,
				_normalized_yields(resource_value.get("yields", {}))
			)
	var facility_yields := _zero_yields()
	for facility_id_value in tile_record.get("facility_levels", {}).keys():
		var facility_id := String(facility_id_value)
		var level := int(tile_record.facility_levels[facility_id_value])
		var per_level := _normalized_yields(
			FACILITY_YIELDS_PER_LEVEL.get(facility_id, {})
		)
		for yield_key in YIELD_KEYS:
			facility_yields[yield_key] = (
				float(facility_yields[yield_key])
				+ float(per_level[yield_key]) * level
			)
	var city_modifiers := _normalized_modifiers(
		settlement_record.get("city_yield_modifiers", {})
	)
	var technology_modifiers := _normalized_modifiers(
		settlement_record.get("technology_yield_modifiers", {})
	)
	var potential_yields := _zero_yields()
	for yield_key in YIELD_KEYS:
		var subtotal := (
			float(terrain_yields[yield_key])
			+ float(special_resource_yields[yield_key])
			+ float(facility_yields[yield_key])
		)
		var multiplier := (
			1.0
			+ float(city_modifiers[yield_key])
			+ float(technology_modifiers[yield_key])
		)
		potential_yields[yield_key] = maxf(0.0, subtotal * multiplier)
	var active_yields := (
		potential_yields.duplicate(true)
		if bool(tile_record.get("worked", false))
		else _zero_yields()
	)
	return {
		"tile": tile,
		"tile_key": _tile_key(world_map, tile),
		"settlement_id": settlement_id,
		"worked": bool(tile_record.get("worked", false)),
		"work_mode": String(tile_record.get("work_mode", "unworked")),
		"terrain_yields": terrain_yields,
		"special_resource_yields": special_resource_yields,
		"facility_yields": facility_yields,
		"city_modifiers": city_modifiers,
		"technology_modifiers": technology_modifiers,
		"potential_yields": potential_yields,
		"active_yields": active_yields,
	}


func settlement_yields(world_map, settlement_id: String) -> Dictionary:
	var totals := _zero_yields()
	var worked_tile_count := 0
	for tile_record in managed_tiles(settlement_id):
		if not bool(tile_record.get("worked", false)):
			continue
		var tile := Vector2i(
			int(tile_record.get("column", -1)),
			int(tile_record.get("row", -1))
		)
		var detail := tile_yield(world_map, tile)
		_add_yields(totals, detail.get("active_yields", {}))
		worked_tile_count += 1
	return {
		"settlement_id": settlement_id,
		"worked_tile_count": worked_tile_count,
		"yields": totals,
	}


func households(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var settlement_record: Dictionary = _state.get("settlements", {}).get(
		settlement_id,
		{}
	)
	for household_value in settlement_record.get("households", {}).values():
		if household_value is Dictionary:
			result.append(household_value.duplicate(true))
	result.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return String(first.get("id", "")) < String(second.get("id", ""))
	)
	return result


func add_households(
	settlement_id: String,
	count: int,
	members_per_household: int = 4,
	occupation: String = "unassigned"
) -> Dictionary:
	if not _state.get("settlements", {}).has(settlement_id):
		return {
			"ok": false,
			"reason_code": "settlement_missing",
			"reason": "가구를 등록할 도시가 없습니다.",
		}
	if count <= 0:
		return {
			"ok": false,
			"reason_code": "household_count_invalid",
			"reason": "추가할 가구 수는 1 이상이어야 합니다.",
		}
	var settlement_record: Dictionary = _state.settlements[settlement_id]
	var household_records: Dictionary = settlement_record.get("households", {})
	var next_serial := maxi(1, int(settlement_record.get("next_household_id", 1)))
	var added_ids: Array[String] = []
	for unused_index in range(count):
		var household_id := "%s_household_%d" % [settlement_id, next_serial]
		while household_records.has(household_id):
			next_serial += 1
			household_id = "%s_household_%d" % [settlement_id, next_serial]
		household_records[household_id] = {
			"id": household_id,
			"settlement_id": settlement_id,
			"members": maxi(1, members_per_household),
			"occupation": occupation,
			"assigned_tile_key": "",
		}
		added_ids.append(household_id)
		next_serial += 1
	settlement_record["households"] = household_records
	settlement_record["next_household_id"] = next_serial
	_state.settlements[settlement_id] = settlement_record
	return {
		"ok": true,
		"reason_code": "ok",
		"settlement_id": settlement_id,
		"added_household_ids": added_ids,
		"household_count": household_records.size(),
	}


func assign_household_to_tile(
	world_map,
	settlement_id: String,
	household_id: String,
	tile: Vector2i
) -> Dictionary:
	if world_map == null or not world_map.contains(tile.x, tile.y):
		return {
			"ok": false,
			"reason_code": "tile_out_of_bounds",
			"reason": "가구를 배치할 타일이 지도 안에 없습니다.",
		}
	if not _state.get("settlements", {}).has(settlement_id):
		return {
			"ok": false,
			"reason_code": "settlement_missing",
			"reason": "가구를 배치할 도시가 없습니다.",
		}
	var settlement_record: Dictionary = _state.settlements[settlement_id]
	var household_records: Dictionary = settlement_record.get("households", {})
	if not household_records.has(household_id):
		return {
			"ok": false,
			"reason_code": "household_missing",
			"reason": "해당 도시에 등록된 가구가 아닙니다.",
		}
	var key := _tile_key(world_map, tile)
	var tile_record: Dictionary = _state.get("tiles", {}).get(key, {})
	if tile_record.is_empty():
		return {
			"ok": false,
			"reason_code": "tile_unclaimed",
			"reason": "도시 영향권 밖의 타일에는 가구를 배치할 수 없습니다.",
		}
	if String(tile_record.get("managing_settlement_id", "")) != settlement_id:
		return {
			"ok": false,
			"reason_code": "tile_managed_by_other_city",
			"reason": "다른 도시가 관리하는 타일에는 가구를 배치할 수 없습니다.",
		}
	if String(tile_record.get("settlement_id", "")) == settlement_id:
		return {
			"ok": false,
			"reason_code": "city_center_auto_worked",
			"reason": "도시 중심 타일은 가구를 배치하지 않아도 자동 작업됩니다.",
		}
	var occupying_household_id := String(
		tile_record.get("assigned_household_id", "")
	)
	if (
		not occupying_household_id.is_empty()
		and occupying_household_id != household_id
	):
		return {
			"ok": false,
			"reason_code": "tile_household_capacity",
			"reason": "한 타일에는 한 가구만 배치할 수 있습니다.",
			"assigned_household_id": occupying_household_id,
		}
	var household_record: Dictionary = household_records[household_id]
	var previous_key := String(household_record.get("assigned_tile_key", ""))
	if not previous_key.is_empty() and previous_key != key:
		_clear_household_from_tile(previous_key, household_id)
	tile_record["worked"] = true
	tile_record["work_mode"] = "household"
	tile_record["assigned_household_id"] = household_id
	_state.tiles[key] = tile_record
	household_record["assigned_tile_key"] = key
	household_records[household_id] = household_record
	settlement_record["households"] = household_records
	_state.settlements[settlement_id] = settlement_record
	return {
		"ok": true,
		"reason_code": "ok",
		"settlement_id": settlement_id,
		"household_id": household_id,
		"tile_key": key,
		"previous_tile_key": previous_key,
	}


func unassign_household(settlement_id: String, household_id: String) -> Dictionary:
	if not _state.get("settlements", {}).has(settlement_id):
		return {
			"ok": false,
			"reason_code": "settlement_missing",
			"reason": "가구가 속한 도시가 없습니다.",
		}
	var settlement_record: Dictionary = _state.settlements[settlement_id]
	var household_records: Dictionary = settlement_record.get("households", {})
	if not household_records.has(household_id):
		return {
			"ok": false,
			"reason_code": "household_missing",
			"reason": "해당 도시에 등록된 가구가 아닙니다.",
		}
	var household_record: Dictionary = household_records[household_id]
	var previous_key := String(household_record.get("assigned_tile_key", ""))
	if not previous_key.is_empty():
		_clear_household_from_tile(previous_key, household_id)
	household_record["assigned_tile_key"] = ""
	household_records[household_id] = household_record
	settlement_record["households"] = household_records
	_state.settlements[settlement_id] = settlement_record
	return {
		"ok": true,
		"reason_code": "ok",
		"household_id": household_id,
		"previous_tile_key": previous_key,
	}


func worked_tiles(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile_record in managed_tiles(settlement_id):
		if bool(tile_record.get("worked", false)):
			result.append(tile_record)
	return result


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
		var managing_settlement_id := String(
			tile_record.get("managing_settlement_id", "")
		)
		if managing_settlement_id.is_empty():
			errors.append("tile_manager_missing:%s" % tile_key)
		elif not settlements.has(managing_settlement_id):
			errors.append("tile_manager_unknown:%s" % tile_key)
		elif String(settlements[managing_settlement_id].get("owner_id", "")) != String(
			tile_record.get("owner_id", "")
		):
			errors.append("tile_manager_owner_mismatch:%s" % tile_key)
		var assigned_household_id := String(
			tile_record.get("assigned_household_id", "")
		)
		var work_mode := String(tile_record.get("work_mode", "unworked"))
		if not linked_settlement_id.is_empty():
			if not bool(tile_record.get("worked", false)) or work_mode != "city_center":
				errors.append("city_center_not_auto_worked:%s" % tile_key)
			if not assigned_household_id.is_empty():
				errors.append("city_center_household_assigned:%s" % tile_key)
		elif assigned_household_id.is_empty():
			if bool(tile_record.get("worked", false)) or work_mode != "unworked":
				errors.append("unassigned_tile_marked_worked:%s" % tile_key)
		elif not bool(tile_record.get("worked", false)) or work_mode != "household":
			errors.append("household_tile_not_worked:%s" % tile_key)
		var special_resources_value = tile_record.get("special_resources", [])
		if special_resources_value is not Array:
			errors.append("tile_special_resources_not_array:%s" % tile_key)
		else:
			for resource_value in special_resources_value:
				if (
					resource_value is not Dictionary
					or String(resource_value.get("id", "")).is_empty()
					or resource_value.get("yields", {}) is not Dictionary
				):
					errors.append("tile_special_resource_invalid:%s" % tile_key)
		var facilities_value = tile_record.get("facility_levels", {})
		if facilities_value is not Dictionary:
			errors.append("tile_facilities_not_dictionary:%s" % tile_key)
		else:
			for facility_id_value in facilities_value.keys():
				if (
					not FACILITY_YIELDS_PER_LEVEL.has(String(facility_id_value))
					or int(facilities_value[facility_id_value]) < 0
				):
					errors.append("tile_facility_invalid:%s" % tile_key)
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
		if (
			not center_record.is_empty()
			and String(center_record.get("managing_settlement_id", "")) != settlement_key
		):
			errors.append("settlement_center_manager_mismatch:%s" % settlement_key)
		if (
			not center_record.is_empty()
			and (
				not bool(center_record.get("worked", false))
				or String(center_record.get("work_mode", "")) != "city_center"
			)
		):
			errors.append("settlement_center_work_mode_invalid:%s" % settlement_key)
		if String(settlement_record.get("region_id", "")) != _region_id(world_map, center):
			errors.append("settlement_region_mismatch:%s" % settlement_key)
		for modifier_field in [
			"city_yield_modifiers",
			"technology_yield_modifiers",
		]:
			if settlement_record.get(modifier_field, {}) is not Dictionary:
				errors.append(
					"settlement_yield_modifiers_invalid:%s:%s"
					% [settlement_key, modifier_field]
				)
		var household_records_value = settlement_record.get("households", {})
		if household_records_value is not Dictionary:
			errors.append("settlement_households_not_dictionary:%s" % settlement_key)
		else:
			var household_records: Dictionary = household_records_value
			var assigned_household_tiles: Dictionary = {}
			for household_key_value in household_records.keys():
				var household_key := String(household_key_value)
				var household_value = household_records[household_key_value]
				if household_value is not Dictionary:
					errors.append(
						"household_record_not_dictionary:%s:%s"
						% [settlement_key, household_key]
					)
					continue
				var household_record: Dictionary = household_value
				if String(household_record.get("id", "")) != household_key:
					errors.append(
						"household_id_mismatch:%s:%s"
						% [settlement_key, household_key]
					)
				if String(household_record.get("settlement_id", "")) != settlement_key:
					errors.append(
						"household_settlement_mismatch:%s:%s"
						% [settlement_key, household_key]
					)
				var assigned_key := String(
					household_record.get("assigned_tile_key", "")
				)
				if assigned_key.is_empty():
					continue
				if assigned_household_tiles.has(assigned_key):
					errors.append(
						"household_tile_duplicate:%s:%s"
						% [settlement_key, assigned_key]
					)
				else:
					assigned_household_tiles[assigned_key] = household_key
				if not tiles.has(assigned_key):
					errors.append(
						"household_tile_missing:%s:%s"
						% [settlement_key, household_key]
					)
					continue
				var assigned_tile: Dictionary = tiles[assigned_key]
				if (
					String(assigned_tile.get("managing_settlement_id", ""))
					!= settlement_key
				):
					errors.append(
						"household_tile_manager_mismatch:%s:%s"
						% [settlement_key, household_key]
					)
				if (
					String(assigned_tile.get("assigned_household_id", ""))
					!= household_key
				):
					errors.append(
						"household_tile_link_mismatch:%s:%s"
						% [settlement_key, household_key]
					)
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
			if String(claimed_tile.get("managing_settlement_id", "")) != settlement_key:
				errors.append(
					"settlement_claim_manager_mismatch:%s:%s"
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
			if not current.is_empty():
				continue
			_state.tiles[key] = _make_tile_record(
				world_map,
				claim_tile,
				owner_id,
				settlement_id if claim_tile == tile else "",
				settlement_id
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
		"influence_radius": INITIAL_CLAIM_RADIUS,
		"households": {},
		"next_household_id": 1,
		"city_yield_modifiers": {},
		"technology_yield_modifiers": {},
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
	settlement_id: String,
	managing_settlement_id: String
) -> Dictionary:
	return {
		"column": tile.x,
		"row": tile.y,
		"owner_id": owner_id,
		"region_id": _region_id(world_map, tile),
		"province_id": int(world_map.province_id(tile.x, tile.y)),
		"terrain_id": int(world_map.terrain_id(tile.x, tile.y)),
		"settlement_id": settlement_id,
		"managing_settlement_id": managing_settlement_id,
		"worked": not settlement_id.is_empty(),
		"work_mode": "city_center" if not settlement_id.is_empty() else "unworked",
		"assigned_household_id": "",
		"special_resources": [],
		"facility_levels": {},
	}


func _zero_yields() -> Dictionary:
	return {
		"food": 0.0,
		"production": 0.0,
		"commerce": 0.0,
		"security": 0.0,
	}


func _normalized_yields(source: Dictionary) -> Dictionary:
	var result := _zero_yields()
	for yield_key in YIELD_KEYS:
		result[yield_key] = maxf(0.0, float(source.get(yield_key, 0.0)))
	return result


func _normalized_modifiers(source: Dictionary) -> Dictionary:
	var result := _zero_yields()
	for yield_key in YIELD_KEYS:
		result[yield_key] = maxf(-0.95, float(source.get(yield_key, 0.0)))
	return result


func _add_yields(target: Dictionary, addition: Dictionary) -> void:
	for yield_key in YIELD_KEYS:
		target[yield_key] = (
			float(target.get(yield_key, 0.0))
			+ float(addition.get(yield_key, 0.0))
		)


func _clear_household_from_tile(tile_key: String, household_id: String) -> void:
	if not _state.get("tiles", {}).has(tile_key):
		return
	var tile_record: Dictionary = _state.tiles[tile_key]
	if String(tile_record.get("assigned_household_id", "")) != household_id:
		return
	tile_record["assigned_household_id"] = ""
	tile_record["worked"] = false
	tile_record["work_mode"] = "unworked"
	_state.tiles[tile_key] = tile_record


func _make_border_edge(
	first_tile: Vector2i,
	second_tile: Vector2i,
	first_settlement_id: String,
	second_settlement_id: String,
	first_owner_id: String,
	second_owner_id: String,
	kind: String
) -> Dictionary:
	return {
		"from_tile": first_tile,
		"to_tile": second_tile,
		"first_settlement_id": first_settlement_id,
		"second_settlement_id": second_settlement_id,
		"first_owner_id": first_owner_id,
		"second_owner_id": second_owner_id,
		"kind": kind,
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


func _migrate_legacy_management_links() -> void:
	var tiles: Dictionary = _state.get("tiles", {})
	var settlements: Dictionary = _state.get("settlements", {})
	for settlement_key_value in settlements.keys():
		var settlement_id := String(settlement_key_value)
		var settlement_value = settlements[settlement_key_value]
		if settlement_value is not Dictionary:
			continue
		var settlement_record: Dictionary = settlement_value
		if settlement_record.get("households", {}) is not Dictionary:
			settlement_record["households"] = {}
		if settlement_record.get("city_yield_modifiers", {}) is not Dictionary:
			settlement_record["city_yield_modifiers"] = {}
		if (
			settlement_record.get("technology_yield_modifiers", {})
			is not Dictionary
		):
			settlement_record["technology_yield_modifiers"] = {}
		settlement_record["next_household_id"] = maxi(
			1,
			int(settlement_record.get("next_household_id", 1))
		)
		settlement_record["influence_radius"] = clampi(
			int(
				settlement_record.get(
					"influence_radius",
					INITIAL_CLAIM_RADIUS
				)
			),
			INITIAL_CLAIM_RADIUS,
			CITY_MAX_INFLUENCE_RADIUS
		)
		for claimed_key_value in settlement_record.get("claimed_tile_keys", []):
			var claimed_key := String(claimed_key_value)
			if not tiles.has(claimed_key):
				continue
			var tile_record: Dictionary = tiles[claimed_key]
			if tile_record.get("special_resources", []) is not Array:
				tile_record["special_resources"] = []
			if tile_record.get("facility_levels", {}) is not Dictionary:
				tile_record["facility_levels"] = {}
			if String(tile_record.get("managing_settlement_id", "")).is_empty():
				tile_record["managing_settlement_id"] = settlement_id
			if String(tile_record.get("settlement_id", "")) == settlement_id:
				tile_record["worked"] = true
				tile_record["work_mode"] = "city_center"
				tile_record["assigned_household_id"] = ""
			else:
				var assigned_id := String(
					tile_record.get("assigned_household_id", "")
				)
				tile_record["assigned_household_id"] = assigned_id
				tile_record["worked"] = not assigned_id.is_empty()
				tile_record["work_mode"] = (
					"household" if not assigned_id.is_empty() else "unworked"
				)
			tiles[claimed_key] = tile_record
		settlements[settlement_key_value] = settlement_record
	_state["tiles"] = tiles
	_state["settlements"] = settlements


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
