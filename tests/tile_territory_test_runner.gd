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
	_expect(
		bool(center_state.get("worked", false))
		and String(center_state.get("work_mode", "")) == "city_center"
		and String(center_state.get("assigned_household_id", "")).is_empty(),
		"도시 중심 타일은 가구를 소모하지 않고 자동 작업한다."
	)
	for tile_record in manager.managed_tiles(String(first_city.get("id", ""))):
		_expect(
			String(tile_record.get("managing_settlement_id", ""))
			== String(first_city.get("id", "")),
			"초기 영향권의 모든 타일은 한 도시에만 귀속된다."
		)
		if int(tile_record.get("terrain_id",0))>3 and int(tile_record.get("terrain_id",0))!=13:
			_expect(
				tile_record.get("special_resources", []).size() == 1
				and String(tile_record.get("special_resources", [])[0].get("id", "")) in ["grain", "wood", "iron", "gold"],
				"도시가 확보한 각 육지 타일은 지도 기반 자원 하나를 자동 계승한다."
			)
	var base_yield: Dictionary = manager.tile_yield(world_map, first_tile)
	_expect(
		bool(base_yield.get("worked", false))
		and float(base_yield.get("active_yields", {}).get("food", 0.0)) > 0.0,
		"중심 타일의 지형 기본 생산량을 자동 산출한다."
	)
	var configured_yield: Dictionary = manager.configure_tile_yield_sources(
		world_map,
		String(first_city.get("id", "")),
		first_tile,
		[{"id": "grain", "yields": {"food": 2.0}}],
		{"farmland": 1}
	)
	_expect(
		bool(configured_yield.get("ok", false)),
		"타일에 특수 자원과 시설 생산원을 함께 설정한다."
	)
	_expect(
		bool(
			manager.set_yield_modifiers(
				String(first_city.get("id", "")),
				{"food": 0.1},
				{"food": 0.2}
			).get("ok", false)
		),
		"도시 보정과 기술 보정을 각각 설정한다."
	)
	var calculated_yield: Dictionary = manager.tile_yield(world_map, first_tile)
	var terrain_food := float(
		calculated_yield.get("terrain_yields", {}).get("food", 0.0)
	)
	var expected_food := (terrain_food + 2.0 + 1.5) * 1.3
	_expect(
		is_equal_approx(
			float(calculated_yield.get("potential_yields", {}).get("food", 0.0)),
			expected_food
		),
		"지형+특수 자원+시설 합계에 도시·기술 보정을 적용한다."
	)
	var farmland_level_two_quote: Dictionary = manager.tile_facility_upgrade_quote(
		world_map,
		String(first_city.get("id", "")),
		first_tile,
		"farmland"
	)
	_expect(
		bool(farmland_level_two_quote.get("ok", false))
		and int(farmland_level_two_quote.get("target_level", 0)) == 2,
		"기존 시설을 같은 타일에서 다음 단계로 업그레이드한다."
	)
	var farmland_level_two: Dictionary = manager.complete_tile_facility_upgrade(
		world_map,
		String(first_city.get("id", "")),
		first_tile,
		"farmland",
		2
	)
	_expect(
		bool(farmland_level_two.get("ok", false))
		and int(farmland_level_two.get("level", 0)) == 2,
		"시설 업그레이드 완료 시 타일 단계가 증가한다."
	)
	var market_level_one: Dictionary = manager.complete_tile_facility_upgrade(
		world_map,
		String(first_city.get("id", "")),
		first_tile,
		"market",
		1
	)
	_expect(
		bool(market_level_one.get("ok", false)),
		"같은 타일에 다른 종류의 시설도 중복 설치한다."
	)
	var developed_center := manager.tile_state(world_map, first_tile)
	_expect(
		int(developed_center.get("facility_levels", {}).get("farmland", 0)) == 2
		and int(developed_center.get("facility_levels", {}).get("market", 0)) == 1,
		"타일 시설은 단일 슬롯이 아니라 종류별 업그레이드 단계로 저장한다."
	)
	var developed_yield: Dictionary = manager.tile_yield(world_map, first_tile)
	_expect(
		is_equal_approx(
			float(developed_yield.get("facility_yields", {}).get("food", 0.0)),
			1.5 * (1.0 + ManagerScript.FACILITY_MARGINAL_YIELD_FACTOR)
		),
		"같은 시설의 추가 단계 생산량은 점차 체감한다."
	)
	var farmland_level_three_quote: Dictionary = manager.tile_facility_upgrade_quote(
		world_map,
		String(first_city.get("id", "")),
		first_tile,
		"farmland"
	)
	_expect(
		int(
			farmland_level_three_quote.get("costs", {}).get("construction", 0)
		)
		> int(
			farmland_level_two_quote.get("costs", {}).get("construction", 0)
		),
		"시설 단계와 타일 총개발도가 높을수록 다음 비용이 증가한다."
	)
	var city_yields: Dictionary = manager.settlement_yields(
		world_map,
		String(first_city.get("id", ""))
	)
	_expect(
		int(city_yields.get("worked_tile_count", 0)) == 1
		and is_equal_approx(
			float(city_yields.get("yields", {}).get("food", 0.0)),
			float(developed_yield.get("active_yields", {}).get("food", 0.0))
		),
		"업그레이드된 중심 타일 생산량을 도시 합계에 반영한다."
	)
	var household_result: Dictionary = manager.add_households(
		String(first_city.get("id", "")),
		2,
		4,
		"farmers"
	)
	_expect(
		bool(household_result.get("ok", false))
		and int(household_result.get("household_count", 0)) == 2,
		"도시에 작업 단위인 가구를 등록한다."
	)
	var household_ids: Array = household_result.get("added_household_ids", [])
	var work_tiles := _non_center_managed_tiles(
		manager,
		String(first_city.get("id", ""))
	)
	_expect(work_tiles.size() >= 2, "가구를 배치할 비중심 타일을 찾는다.")
	if household_ids.size() >= 2 and work_tiles.size() >= 2:
		var first_household := String(household_ids[0])
		var second_household := String(household_ids[1])
		var first_work_tile := Vector2i(
			int(work_tiles[0].get("column", -1)),
			int(work_tiles[0].get("row", -1))
		)
		_expect(
			bool(
				manager.configure_city_construction(
					String(first_city.get("id", "")),
					10.0,
					{"wood": 100.0, "stone": 100.0, "iron": 100.0}
				).get("ok", false)
			),
			"도시에 턴당 건설력과 자원 비축량을 설정한다."
		)
		var queued_upgrade: Dictionary = manager.queue_tile_facility_upgrade(
			world_map,
			String(first_city.get("id", "")),
			first_work_tile,
			"farmland"
		)
		_expect(
			bool(queued_upgrade.get("ok", false))
			and float(
				queued_upgrade.get("resource_stockpile", {}).get("wood", 100.0)
			)
			< 100.0,
			"타일 업그레이드를 도시 대기열에 넣을 때 자원을 선예약한다."
		)
		var first_build_turn: Dictionary = manager.advance_city_construction(
			world_map,
			String(first_city.get("id", "")),
			1
		)
		_expect(
			first_build_turn.get("completed", []).is_empty()
			and int(
				manager.tile_state(world_map, first_work_tile).get(
					"facility_levels",
					{}
				).get("farmland", 0)
			)
			== 0,
			"건설력이 부족한 첫 턴에는 시설이 즉시 완공되지 않는다."
		)
		var second_build_turn: Dictionary = manager.advance_city_construction(
			world_map,
			String(first_city.get("id", "")),
			1
		)
		_expect(
			second_build_turn.get("completed", []).size() == 1
			and int(
				manager.tile_state(world_map, first_work_tile).get(
					"facility_levels",
					{}
				).get("farmland", 0)
			)
			== 1,
			"도시 건설력이 누적되면 FIFO 주문이 완공되어 타일에 반영된다."
		)
		_expect(
			manager.city_construction_status(
				String(first_city.get("id", ""))
			).get("queue", []).is_empty(),
			"완공된 타일 건설 주문은 도시 대기열에서 제거된다."
		)
		var second_work_tile := Vector2i(
			int(work_tiles[1].get("column", -1)),
			int(work_tiles[1].get("row", -1))
		)
		_expect(
			bool(
				manager.assign_household_to_tile(
					world_map,
					String(first_city.get("id", "")),
					first_household,
					first_work_tile
				).get("ok", false)
			),
			"비중심 타일에 한 가구를 배치한다."
		)
		var capacity_block: Dictionary = manager.assign_household_to_tile(
			world_map,
			String(first_city.get("id", "")),
			second_household,
			first_work_tile
		)
		_expect(
			not bool(capacity_block.get("ok", true))
			and String(capacity_block.get("reason_code", ""))
			== "tile_household_capacity",
			"한 타일에 두 가구를 중복 배치할 수 없다."
		)
		var moved: Dictionary = manager.assign_household_to_tile(
			world_map,
			String(first_city.get("id", "")),
			first_household,
			second_work_tile
		)
		_expect(bool(moved.get("ok", false)), "가구를 다른 관리 타일로 이동한다.")
		_expect(
			not bool(manager.tile_state(world_map, first_work_tile).get("worked", true))
			and String(
				manager.tile_state(world_map, second_work_tile).get(
					"assigned_household_id",
					""
				)
			)
			== first_household,
			"가구 이동 시 이전 타일은 자동 해제된다."
		)
		_expect(
			bool(
				manager.unassign_household(
					String(first_city.get("id", "")),
					first_household
				).get("ok", false)
			),
			"가구의 타일 작업을 해제한다."
		)
		_expect(
			not bool(manager.tile_state(world_map, second_work_tile).get("worked", true)),
			"가구가 빠진 일반 타일은 작업 중이 아니게 된다."
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
		var transferable_tile := _border_tile_for_settlement(
			borders,
			first_id,
			second_id
		)
		_expect(
			transferable_tile.x >= 0,
			"두 도시 국경에서 명시적으로 이전할 비중심 타일을 찾는다."
		)
		if transferable_tile.x >= 0:
			var stable_before := manager.tile_state(world_map, transferable_tile)
			manager.expand_city_influence(world_map, second_id, 2)
			var stable_after := manager.tile_state(world_map, transferable_tile)
			_expect(
				String(stable_before.get("managing_settlement_id", ""))
				== String(stable_after.get("managing_settlement_id", "")),
				"영향권을 다시 계산해도 기존 국경은 수동으로 이동하지 않는다."
			)
			var transfer: Dictionary = manager.transfer_tile_affiliation(
				world_map,
				transferable_tile,
				second_id,
				"baekje",
				"treaty",
				"test_treaty_001"
			)
			_expect(
				bool(transfer.get("ok", false))
				and int(transfer.get("border_revision", 0)) == 1,
				"조약 이벤트로만 타일의 정치 소유권과 관리 도시를 이전한다."
			)
			var transferred_state := manager.tile_state(
				world_map,
				transferable_tile
			)
			_expect(
				String(transferred_state.get("political_owner_id", "")) == "baekje"
				and String(
					transferred_state.get("managing_settlement_id", "")
				)
				== second_id,
				"이전된 타일은 새 소유국과 새 관리 도시를 함께 기록한다."
			)
			_expect(
				manager.border_events().size() == 1
				and String(
					manager.border_events()[0].get("event_id", "")
				)
				== "test_treaty_001",
				"국경 변경 이력을 단조 증가 리비전으로 남긴다."
			)
		var removal_manager = ManagerScript.new()
		var removal_pair := _find_support_city_pair(
			removal_manager,
			world_map,
			"goguryeo"
		)
		_expect(
			removal_pair.size() == 2,
			"실제 지도에서 영향권이 맞닿는 같은 국가 도시쌍을 찾는다."
		)
		if removal_pair.size() == 2:
			var removal_first_tile: Vector2i = removal_pair[0]
			var support_tile: Vector2i = removal_pair[1]
			var removal_first_result: Dictionary = (
				removal_manager.found_initial_city(
					world_map,
					removal_first_tile,
					"goguryeo",
					"폐기 대상 도시"
				)
			)
			var removal_first_id := String(
				removal_first_result.get("settlement", {}).get("id", "")
			)
			var support_result: Dictionary = removal_manager.found_city(
				world_map,
				support_tile,
				"goguryeo",
				"지원 소도시"
			)
			var support_id := String(
				support_result.get("settlement", {}).get("id", "")
			)
			removal_manager.expand_city_influence(
				world_map,
				removal_first_id,
				2
			)
			removal_manager.expand_city_influence(world_map, support_id, 2)
			var removal: Dictionary = removal_manager.remove_city(
				world_map,
				removal_first_id,
				"destroyed",
				"city_destroyed_001"
			)
			_expect(
				bool(removal.get("ok", false))
				and int(removal.get("reassigned_tile_count", 0)) > 0
				and int(removal.get("neutral_tile_count", 0)) > 0,
				"도시 파괴 시 같은 국가 영향에 닿는 타일만 재귀속하고 나머지는 중립화한다."
			)
			_expect(
				removal_manager.settlement(removal_first_id).is_empty(),
				"파괴된 도시는 도시 목록과 중심 타일 연결에서 제거된다."
			)
			var reassigned_key := _first_nested_key(
				removal.get("reassigned_tile_keys_by_settlement", {})
			)
			var reassigned_record: Dictionary = (
				removal_manager.snapshot().tiles.get(reassigned_key, {})
			)
			_expect(
				String(
					reassigned_record.get("managing_settlement_id", "")
				)
				== support_id,
				"재귀속 타일은 실제 반경에 닿은 같은 국가 도시에 귀속된다."
			)
			var neutral_key := String(removal.get("neutral_tile_keys", [])[0])
			var neutral_tile := _tile_from_key(world_map, neutral_key)
			var neutral_record := removal_manager.neutral_tile_state(
				world_map,
				neutral_tile
			)
			_expect(
				String(neutral_record.get("owner_id", "")).is_empty()
				and bool(neutral_record.get("ruins", false))
				and removal_manager.tile_state(
					world_map,
					neutral_tile
				).is_empty(),
				"인접 도시 반경 밖 타일은 개발 흔적을 보존한 중립 폐허가 된다."
			)
			_expect(
				bool(removal_manager.validate_state(world_map).get("ok", false)),
				"도시 제거와 재귀속 이후에도 타일 참조 무결성을 유지한다."
			)
		var occupation_manager = ManagerScript.new()
		occupation_manager.load_snapshot(manager.snapshot())
		var occupation_started: Dictionary = occupation_manager.begin_city_occupation(
			world_map,
			first_id,
			"baekje",
			"battle_capture_001"
		)
		_expect(
			bool(occupation_started.get("ok", false))
			and String(occupation_started.get("political_owner_id", ""))
			== "goguryeo"
			and String(occupation_started.get("military_controller_id", ""))
			== "baekje",
			"도시 함락 직후 중심 타일의 군사 통제만 바뀌고 정치 소유권은 남는다."
		)
		var occupation_expanded: Dictionary = (
			occupation_manager.advance_military_control(
				world_map,
				first_id,
				"baekje",
				1,
				"battle_spread_001"
			)
		)
		var controlled_count := int(
			occupation_expanded.get("controlled_tile_count", 0)
		)
		var first_claim_count: int = occupation_manager.settlement(
			first_id
		).get("claimed_tile_keys", []).size()
		_expect(
			bool(occupation_expanded.get("ok", false))
			and controlled_count > 1
			and controlled_count < first_claim_count,
			"군사 통제는 중심에서 인접 타일로 단계적으로 확장된다."
		)
		var sample_controlled_key := String(
			occupation_expanded.get(
				"newly_controlled_tile_keys",
				[]
			)[0]
		)
		var sample_controlled: Dictionary = (
			occupation_manager.snapshot().tiles[sample_controlled_key]
		)
		_expect(
			String(sample_controlled.get("military_controller_id", "")) == "baekje"
			and String(sample_controlled.get("political_owner_id", ""))
			== "goguryeo",
			"점령이 퍼진 타일도 평화조약 전에는 기존 정치 소유국을 유지한다."
		)
		var occupation_treaty: Dictionary = (
			occupation_manager.finalize_occupation_by_treaty(
				first_id,
				"baekje",
				"peace_treaty_occupation_001"
			)
		)
		_expect(
			bool(occupation_treaty.get("ok", false))
			and int(occupation_treaty.get("transferred_tile_count", 0))
			== first_claim_count,
			"평화조약이 체결되어야 도시 영토의 정치 소유권이 공식 이전된다."
		)
		_expect(
			String(
				occupation_manager.settlement(first_id).get("owner_id", "")
			)
			== "baekje"
			and bool(occupation_manager.validate_state(world_map).get("ok", false)),
			"조약 완료 후 도시·타일 소유권과 군사 통제 상태가 일관된다."
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


func _find_support_city_pair(
	manager,
	world_map,
	owner_id: String
) -> Array[Vector2i]:
	for index_value in world_map.assigned_indices:
		var index := int(index_value)
		var first := Vector2i(index % world_map.width, index / world_map.width)
		if not bool(manager.can_found_city(world_map, first, owner_id).get("ok", false)):
			continue
		for distance in range(
			ManagerScript.MIN_CITY_CENTER_DISTANCE,
			ManagerScript.CITY_MAX_INFLUENCE_RADIUS * 2 + 1
		):
			for row in range(first.y - distance, first.y + distance + 1):
				for column in range(first.x - distance, first.x + distance + 1):
					var second := Vector2i(column, row)
					if manager.city_center_distance(first, second) != distance:
						continue
					if bool(
						manager.can_found_city(
							world_map,
							second,
							owner_id
						).get("ok", false)
					):
						return [first, second]
	return []


func _find_support_city_site(
	manager,
	world_map,
	origin: Vector2i,
	owner_id: String
) -> Vector2i:
	for distance in range(
		ManagerScript.MIN_CITY_CENTER_DISTANCE,
		ManagerScript.CITY_MAX_INFLUENCE_RADIUS * 2 + 1
	):
		var candidate := _find_foundable_at_exact_distance(
			manager,
			world_map,
			origin,
			distance,
			owner_id
		)
		if candidate.x >= 0:
			return candidate
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


func _non_center_managed_tiles(
	manager,
	settlement_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile_record in manager.managed_tiles(settlement_id):
		if String(tile_record.get("settlement_id", "")).is_empty():
			result.append(tile_record)
	return result


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


func _first_nested_key(source: Dictionary) -> String:
	for value in source.values():
		if value is Array and not value.is_empty():
			return String(value[0])
	return ""


func _tile_from_key(world_map, tile_key: String) -> Vector2i:
	var index := int(tile_key)
	return Vector2i(index % int(world_map.width), index / int(world_map.width))


func _border_tile_for_settlement(
	borders: Array[Dictionary],
	first_id: String,
	second_id: String
) -> Vector2i:
	for border in borders:
		var edge_first := String(border.get("first_settlement_id", ""))
		var edge_second := String(border.get("second_settlement_id", ""))
		if edge_first == first_id and edge_second == second_id:
			return Vector2i(border.get("from_tile", Vector2i(-1, -1)))
		if edge_first == second_id and edge_second == first_id:
			return Vector2i(border.get("to_tile", Vector2i(-1, -1)))
	return Vector2i(-1, -1)


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
