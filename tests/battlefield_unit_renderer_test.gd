extends SceneTree

const GatewayScript = preload("res://src/presentation/strategy_gateway.gd")
const StrategicMapScript = preload("res://src/map/strategic_map.gd")
const Formation = preload("res://src/map/battlefield_unit_formation.gd")
const Demo = preload("res://src/map/battlefield_unit_demo.gd")
const CAPTURE_PATH := "user://battlefield_unit_demo.png"

var failures: Array[String] = []


func _initialize() -> void:
	var watchdog := create_timer(15.0)
	watchdog.timeout.connect(func(): push_error("Battlefield unit renderer test timed out"); quit(1))
	call_deferred("_run")


func _run() -> void:
	var infantry := {"id": "stable_infantry", "soldiers": 1200, "visual_type": "infantry", "facing": 1}
	var archers := {"id": "stable_archers", "soldiers": 1200, "visual_type": "archer", "facing": -1}
	var infantry_slots: Array[Dictionary] = Formation.make_slots(infantry, 1.0)
	var second_infantry_slots: Array[Dictionary] = Formation.make_slots(infantry, 1.0)
	var archer_slots: Array[Dictionary] = Formation.make_slots(archers, 1.0)
	_expect(infantry_slots.size() >= 6 and infantry_slots.size() <= 16, "병력 한 부대는 6~16명의 대표 병사로 표현되어야 한다.")
	_expect(infantry_slots.size() == second_infantry_slots.size(), "같은 부대 seed는 재렌더링 때 같은 대형 크기를 유지해야 한다.")
	if not infantry_slots.is_empty() and infantry_slots.size() == second_infantry_slots.size():
		_expect(infantry_slots[0].offset == second_infantry_slots[0].offset, "같은 부대 seed는 병사 위치 편차를 고정해야 한다.")
	_expect(String(infantry_slots[0].visual_type) == "infantry" and String(archer_slots[0].visual_type) == "archer", "보병과 궁병은 별도 실루엣 타입을 유지해야 한다.")
	_expect(_width(archer_slots) > _width(infantry_slots), "궁병 대형은 보병보다 넓은 간격을 사용해야 한다.")
	_expect(Formation.visual_type_for_group({"id": "frontier_default", "owner_id": "northern_china_frontier", "soldiers": 700}) == "archer", "병과 상세가 없는 국경 군단도 궁병 시각 기본값을 사용해야 한다.")

	var gateway = GatewayScript.new()
	_expect(gateway.load_local_catalog(), "동아시아 시나리오를 로드해야 전장 유닛을 배치할 수 있다.")
	var snapshot: Dictionary = gateway.snapshot()
	_expect(snapshot.has("army_groups"), "표현 계층은 병력 숫자와 별도로 군단 상세 데이터를 받아야 한다.")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var map = StrategicMapScript.new()
	map.show_battlefield_units = true
	map.size = Vector2(1280, 720)
	viewport.add_child(map)
	map.set_snapshot(snapshot)
	await process_frame
	map.frame_world()
	await process_frame
	await process_frame

	var demo_groups: Array[Dictionary] = Demo.fallback_groups(snapshot.get("provinces", {}), map.world_map)
	_expect(demo_groups.size() == 2, "실제 군단이 없을 때 육지 앵커의 두 데모 부대가 배치되어야 한다.")
	for group in demo_groups:
		var position: Vector2 = group.world_position
		var tile: Vector2i = map.world_map.tile_at_world(position)
		var terrain := int(map.world_map.terrain_id(tile.x, tile.y))
		_expect(terrain >= 3 and terrain != 12 and terrain != 13, "데모 병사는 물 또는 호수 타일 위에 배치되지 않아야 한다.")

	var stats: Dictionary = map.battlefield_render_stats()
	var presented_armies: Array = snapshot.get("army_groups", [])
	_expect(bool(stats.get("demo_used", false)) or not presented_armies.is_empty(), "초기 게임 화면은 실제 군단 또는 시각 데모 대형을 사용해야 한다.")
	_expect(int(stats.get("group_count", 0)) >= 2, "전장 맵에 서로 다른 두 부대가 렌더링되어야 한다.")
	_expect(int(stats.get("soldier_count", 0)) >= 16, "전장 맵의 두 부대는 여러 소형 병사로 렌더링되어야 한다.")


	map.queue_free()
	viewport.queue_free()
	await process_frame
	if failures.is_empty():
		print("Battlefield unit renderer test: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _width(slots: Array[Dictionary]) -> float:
	if slots.is_empty():
		return 0.0
	var low := INF
	var high := -INF
	for slot in slots:
		var offset: Vector2 = slot.offset
		low = minf(low, offset.x)
		high = maxf(high, offset.x)
	return high - low


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures.append(message)
		push_error("[FAIL] %s" % message)
