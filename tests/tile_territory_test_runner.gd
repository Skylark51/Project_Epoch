extends SceneTree

const ManagerScript = preload("res://src/world/tile_territory_manager.gd")
const WorldMapScript = preload("res://src/map/world_map_data.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_map = WorldMapScript.new()
	_expect(world_map.load_default(), "세계 지도 데이터를 불러온다.")
	var manager = ManagerScript.new()
	var first_tile := _find_settleable_tile(manager, world_map)
	_expect(first_tile.x >= 0, "개척 가능한 육지 타일을 찾는다.")
	if first_tile.x < 0:
		_finish()
		return
	var first_result: Dictionary = manager.found_initial_city(
		world_map,
		first_tile,
		"goguryeo",
		"시험 소도시",
		1
	)
	_expect(bool(first_result.get("ok", false)), "선택한 타일에 첫 도시를 건설한다.")
	var first_city: Dictionary = first_result.get("settlement", {})
	_expect(
		String(first_city.get("settlement_type", "")) == "small_town",
		"첫 도시는 작은 도시 단계다."
	)
	_expect(int(first_city.get("population", 0)) == 120, "첫 도시 인구는 120명이다.")
	_expect(bool(first_city.get("is_capital", false)), "첫 도시는 수도로 등록된다.")
	_expect(
		int(first_result.get("claimed_tile_count", 0)) >= 4
		and int(first_result.get("claimed_tile_count", 0)) <= 9,
		"도시 주변 최대 3×3 타일을 첫 영토로 편입한다."
	)
	var center_state: Dictionary = manager.tile_state(world_map, first_tile)
	_expect(
		String(center_state.get("owner_id", "")) == "goguryeo",
		"도시 중심 타일의 소유국을 기록한다."
	)
	_expect(
		String(center_state.get("settlement_id", "")) == String(first_city.get("id", "")),
		"도시와 중심 타일을 양방향 검증 가능한 형태로 연결한다."
	)
	_expect(
		String(center_state.get("managing_settlement_id", ""))
		== String(first_city.get("id", "")),
		"도시 중심 타일의 관리 도시를 기록한다."
	)
	for tile_record in manager.managed_tiles(String(first_city.get("id", ""))):
		_expect(
			String(tile_record.get("managing_settlement_id", ""))
			== String(first_city.get("id", "")),
			"초기 영향권의 모든 타일은 한 도시에만 귀속된다."
		)
	var nearby_tile := _find_settleable_in_distance(
		manager,
		world_map,
		first_tile,
		1,
		ManagerScript.CITY_EXCLUSION_RADIUS
	)
	_expect(nearby_tile.x >= 0, "도시 반경 2 안의 육지 타일을 찾는다.")
	if nearby_tile.x >= 0:
		var blocked: Dictionary = manager.can_found_city(
			world_map,
			nearby_tile,
			"baekje"
		)
		_expect(
			not bool(blocked.get("ok", false))
			and String(blocked.get("reason_code", "")) == "city_spacing",
			"기존 도시 중심 반경 2 안에는 새 도시를 세울 수 없다."
		)
		_expect(
			int(blocked.get("minimum_city_center_distance", 0)) == 3,
			"도시 중심의 최소 간격을 3타일로 안내한다."
		)
	var second_tile := _find_foundable_at_exact_distance(
		manager,
		world_map,
		first_tile,
		ManagerScript.MIN_CITY_CENTER_DISTANCE,
		"baekje"
	)
	_expect(second_tile.x >= 0, "기존 도시에서 정확히 3타일 떨어진 후보를 찾는다.")
	if second_tile.x >= 0:
		var second_result: Dictionary = manager.found_city(
			world_map,
			second_tile,
			"baekje",
			"두 번째 소도시",
			{"is_capital": true, "founded_turn": 2}
		)
		_expect(
			bool(second_result.get("ok", false)),
			"도시 중심이 정확히 3타일 떨어지면 건설할 수 있다."
		)
		_expect(
			manager.city_center_distance(first_tile, second_tile) == 3,
			"정사각 타일 거리 계산은 체비쇼프 거리로 고정한다."
		)
		var first_id := String(first_city.get("id", ""))
		var second_id := String(second_result.get("settlement", {}).get("id", ""))
		var first_expansion: Dictionary = manager.expand_city_influence(
			world_map,
			first_id,
			2
		)
		var second_expansion: Dictionary = manager.expand_city_influence(
			world_map,
			second_id,
			2
		)
		_expect(
			bool(first_expansion.get("ok", false))
			and int(first_expansion.get("influence_radius", 0)) == 2,
			"첫 도시 영향권을 최대 반경 2까지 확장한다."
		)
		_expect(
			bool(second_expansion.get("ok", false))
			and int(second_expansion.get("influence_radius", 0)) == 2,
			"인접 도시도 겹치지 않는 타일만 반경 2까지 확장한다."
		)
		var first_claims := _managed_tile_keys(manager, world_map, first_id)
		var second_claims := _managed_tile_keys(manager, world_map, second_id)
		_expect(
			_no_shared_keys(first_claims, second_claims),
			"같은 타일이 두 도시 영향권에 중복 귀속되지 않는다."
		)
		var borders: Array[Dictionary] = manager.border_edges(world_map)
		_expect(
			_has_border_between(borders, first_id, second_id, "national_border"),
			"서로 다른 국가의 도시 영향권 사이에 타일 단위 국경을 만든다."
		)
	var duplicate_capital: Dictionary = manager.found_initial_city(
		world_map,
		first_tile,
		"goguryeo",
		"중복 수도",
		2
	)
	_expect(
		not bool(duplicate_capital.get("ok", false))
		and String(duplicate_capital.get("reason_code", "")) == "capital_exists",
		"같은 국가가 첫 도시를 중복 건설할 수 없다."
	)
	var valid_state: Dictionary = manager.validate_state(world_map)
	_expect(
		bool(valid_state.get("ok", false)),
		"정상 타일·도시·권역 상태의 참조 무결성을 검증한다."
	)
	var restored = ManagerScript.new()
	restored.load_snapshot(manager.snapshot())
	_expect(restored.has_capital("goguryeo"), "저장 상태에서 첫 도시를 복원한다.")
	_expect(
		String(restored.settlement_at(world_map, first_tile).get("name", ""))
		== "시험 소도시",
		"복원 후에도 도시와 타일 연결을 유지한다."
	)
	_expect(
		bool(restored.validate_state(world_map).get("ok", false)),
		"저장 왕복 뒤에도 상태 검증을 통과한다."
	)
	var corrupt_snapshot: Dictionary = manager.snapshot()
	var first_key := String(corrupt_snapshot.tiles.keys()[0])
	corrupt_snapshot.tiles[first_key].column = (
		int(corrupt_snapshot.tiles[first_key].column) + 1
	)
	var corrupt_manager = ManagerScript.new()
	corrupt_manager.load_snapshot(corrupt_snapshot)
	var corrupt_validation: Dictionary = corrupt_manager.validate_state(world_map)
	_expect(
		not bool(corrupt_validation.get("ok", true))
		and _contains_error_prefix(corrupt_validation.get("errors", []), "tile_key_mismatch:"),
		"손상된 타일 키와 좌표의 불일치를 탐지한다."
	)
	if second_tile.x >= 0:
		var spacing_snapshot: Dictionary = manager.snapshot()
		var ids: Array = spacing_snapshot.settlements.keys()
		if ids.size() >= 2:
			var second_id := String(ids[1])
			spacing_snapshot.settlements[second_id].column = first_tile.x
			spacing_snapshot.settlements[second_id].row = first_tile.y
			var spacing_manager = ManagerScript.new()
			spacing_manager.load_snapshot(spacing_snapshot)
			var spacing_validation: Dictionary = spacing_manager.validate_state(world_map)
			_expect(
				not bool(spacing_validation.get("ok", true))
				and _contains_error_prefix(
					spacing_validation.get("errors", []),
					"city_spacing_violation:"
				),
				"불러온 상태에서도 도시 최소 간격 위반을 탐지한다."
			)
	_finish()


func _find_settleable_tile(manager, world_map) -> Vector2i:
	for index_value in world_map.assigned_indices:
		var index := int(index_value)
		var tile := Vector2i(index % world_map.width, index / world_map.width)
		if bool(
			manager.can_found_initial_city(
				world_map,
				tile,
				"goguryeo"
			).get("ok", false)
		):
			return tile
	return Vector2i(-1, -1)


func _find_settleable_in_distance(
	manager,
	world_map,
	origin: Vector2i,
	minimum_distance: int,
	maximum_distance: int
) -> Vector2i:
	for row in range(origin.y - maximum_distance, origin.y + maximum_distance + 1):
		for column in range(
			origin.x - maximum_distance,
			origin.x + maximum_distance + 1
		):
			var tile := Vector2i(column, row)
			if not world_map.contains(tile.x, tile.y):
				continue
			var distance: int = manager.city_center_distance(origin, tile)
			if distance < minimum_distance or distance > maximum_distance:
				continue
			var terrain_id := int(world_map.terrain_id(tile.x, tile.y))
			if terrain_id > 3 and terrain_id not in [8, 13]:
				return tile
	return Vector2i(-1, -1)


func _find_foundable_at_exact_distance(
	manager,
	world_map,
	origin: Vector2i,
	distance: int,
	owner_id: String
) -> Vector2i:
	for row in range(origin.y - distance, origin.y + distance + 1):
		for column in range(origin.x - distance, origin.x + distance + 1):
			var tile := Vector2i(column, row)
			if manager.city_center_distance(origin, tile) != distance:
				continue
			if bool(manager.can_found_city(world_map, tile, owner_id).get("ok", false)):
				return tile
	return Vector2i(-1, -1)


func _contains_error_prefix(errors: Array, prefix: String) -> bool:
	for error_value in errors:
		if String(error_value).begins_with(prefix):
			return true
	return false


func _managed_tile_keys(
	manager,
	world_map,
	settlement_id: String
) -> Dictionary:
	var result := {}
	for tile_record in manager.managed_tiles(settlement_id):
		var key := str(
			int(tile_record.get("row", -1)) * int(world_map.width)
			+ int(tile_record.get("column", -1))
		)
		result[key] = true
	return result


func _no_shared_keys(first: Dictionary, second: Dictionary) -> bool:
	for key in first.keys():
		if second.has(key):
			return false
	return true


func _has_border_between(
	borders: Array[Dictionary],
	first_id: String,
	second_id: String,
	kind: String
) -> bool:
	for border in borders:
		var edge_first := String(border.get("first_settlement_id", ""))
		var edge_second := String(border.get("second_settlement_id", ""))
		if (
			String(border.get("kind", "")) == kind
			and (
				(edge_first == first_id and edge_second == second_id)
				or (edge_first == second_id and edge_second == first_id)
			)
		):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures.append(message)
		push_error("[FAIL] %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("Tile territory test: PASS")
		quit(0)
	else:
		push_error("Tile territory test: %d failure(s)" % failures.size())
		quit(1)
