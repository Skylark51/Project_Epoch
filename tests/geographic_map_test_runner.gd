extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gateway := StrategyGateway.new()
	_expect(gateway.load_local_catalog(), "전략 게이트웨이가 동아시아 시나리오를 로드해야 한다.")
	var map := StrategicMap.new()
	map.size = Vector2(1280, 720)
	get_root().add_child(map)
	map.set_snapshot(gateway.snapshot())
	await process_frame
	map.frame_world()
	await process_frame
	await process_frame
	_expect(map.world_map != null, "전략 지도에 실제 지리 월드맵 모듈이 연결되어야 한다.")
	_expect(map.zoom < 0.32, "전체 지도 프레이밍은 저해상도 전체보기 LOD를 사용해야 한다.")
	_expect(map.visible_chunk_count > 0, "전체보기에서도 가시 청크 범위를 계산해야 한다.")

	map.go_to_lonlat(126.9780, 37.5665, 1.2)
	await process_frame
	await process_frame
	_expect(map.visible_chunk_count > 0 and map.visible_chunk_count < 1200, "확대 시 카메라 주변 청크만 렌더링해야 한다.")
	_expect(map.last_rendered_tile_count < 307200, "확대 시 307,200개 전체 타일을 매 프레임 그리지 않아야 한다.")
	var seoul_world := map.world_map.world_from_lonlat(126.9780, 37.5665)
	var seoul_screen := seoul_world * map.zoom + map.pan
	_expect(map.call("_province_at", seoul_screen) != -1, "서울 실제 좌표에서 기존 전략 프로빈스를 선택할 수 있어야 한다.")
	_expect(String(map.call("_city_at", seoul_screen)) == "seoul", "서울 도시 마커가 실제 좌표에서 클릭되어야 한다.")
	var islands := [
		["제주", 126.53, 33.38], ["울릉도", 130.90, 37.50], ["독도", 131.87, 37.24],
		["쓰시마", 129.30, 34.40], ["하이난", 109.75, 19.20], ["타이완", 121.00, 23.70],
		["오키나와", 127.68, 26.21]
	]
	for island in islands:
		var island_tile := map.world_map.projection.lonlat_to_tile(float(island[1]), float(island[2]))
		var terrain_id := map.world_map.terrain_id(floori(island_tile.x), floori(island_tile.y))
		_expect(terrain_id >= 3, "%s가 실제 상대 좌표에 육지로 보존되어야 한다." % String(island[0]))
	var straits := [["쓰가루 해협", 140.70, 41.50], ["타이완 해협", 119.80, 24.50], ["대한해협", 129.60, 34.80]]
	for strait in straits:
		var strait_tile := map.world_map.projection.lonlat_to_tile(float(strait[1]), float(strait[2]))
		_expect(map.world_map.terrain_id(floori(strait_tile.x), floori(strait_tile.y)) <= 2, "%s이 육지로 막히지 않아야 한다." % String(strait[0]))
	var export_path := "user://geographic_map_test.png"
	_expect(map.export_world_map_png(export_path) == OK and FileAccess.file_exists(export_path), "전체 지도 PNG를 내보낼 수 있어야 한다.")
	if FileAccess.file_exists(export_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	map.queue_free()
	await process_frame
	if failures.is_empty():
		print("Geographic map test: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures.append(message)
		push_error("[FAIL] %s" % message)
