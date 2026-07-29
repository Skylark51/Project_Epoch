extends SceneTree

const TEST_SAVE_PATH := "user://main_runtime_test_autosave.json"

var failures: Array[String] = []
var finished := false


func _initialize() -> void:
    var watchdog := create_timer(30.0)
    watchdog.timeout.connect(_watchdog_timeout)
    call_deferred("_run")


func _run() -> void:
    _remove_test_save()
    var scene = load("res://src/main.tscn")
    _expect(scene is PackedScene, "기준 메인 씬을 불러올 수 있어야 한다.")
    if scene is not PackedScene:
        _finish()
        return

    var root = scene.instantiate()
    get_root().add_child(root)
    await process_frame
    await process_frame
    await process_frame
    await process_frame

    var component = root.get_node_or_null("GovernanceDashboard")
    _expect(component != null, "메인 씬이 통치 대시보드 컴포넌트를 포함해야 한다.")
    if component == null:
        root.queue_free()
        await process_frame
        _finish()
        return

    _expect(component.get("base_ui") == root, "통치 컴포넌트가 기준 전략 UI에 직접 조립되어야 한다.")
    _expect(component.get("governance") != null, "GovernanceSession이 생성되어야 한다.")
    _expect(component.get_node_or_null("GovernanceLauncher") != null, "통치·반란 실행 버튼이 있어야 한다.")
    _expect(component.get_node_or_null("GovernanceDashboard") != null, "통치 대시보드 창이 있어야 한다.")

    var gateway = root.get("gateway")
    var governance = component.get("governance")
    var governance_snapshot: Dictionary = governance.snapshot()
    _expect(governance_snapshot.get("factions", {}).size() >= 11, "동아시아 플레이 가능 국가가 통치 시스템에 등록되어야 한다.")
    _expect(governance_snapshot.get("provinces", {}).size() == 13, "동아시아 프로빈스 13개가 통치 시스템에 등록되어야 한다.")
    _expect(governance_snapshot.get("political_groups", {}).get("goguryeo", {}).size() == 5, "기본 정치 집단 5개가 등록되어야 한다.")
    _expect(String(gateway.snapshot().get("scenario_id", "")) == "prototype_east_asia", "F5 런타임이 동아시아 시나리오를 사용해야 한다.")
    _expect(String(gateway.country("goguryeo").get("name", "")) == "고구려", "국가 선택에 고구려가 노출되어야 한다.")
    var map_tiles: Array = gateway.snapshot().get("map_tiles", [])
    var land_tiles := 0
    var water_tiles := 0
    var coastal_water_tiles := 0
    var covered_provinces := {}
    var all_hexagons := true
    for tile_value in map_tiles:
        if tile_value is not Dictionary:
            all_hexagons = false
            continue
        var tile: Dictionary = tile_value
        all_hexagons = all_hexagons and tile.get("polygon", []).size() == 6
        if bool(tile.get("water", false)):
            water_tiles += 1
            if String(tile.get("terrain", "")) == "coastal_water":
                coastal_water_tiles += 1
        else:
            land_tiles += 1
            covered_provinces[int(tile.get("province_id", -1))] = true
    _expect(map_tiles.size() == 28 * 18, "동아시아 지도가 빈칸 없는 28×18 연속 타일 필드여야 한다.")
    _expect(all_hexagons, "모든 지도 타일은 육각형이어야 한다.")
    _expect(land_tiles >= 150 and water_tiles >= 150, "동아시아 지도에 충분한 육지와 바다 타일이 함께 있어야 한다.")
    _expect(coastal_water_tiles >= 20, "육지 주변에 해안 바다 타일이 형성되어야 한다.")
    _expect(covered_provinces.size() == 13, "13개 프로빈스가 모두 하나 이상의 육지 타일을 가져야 한다.")
    _expect(String(gateway.province(1).get("source_province_id", "")) == "guknae_basin", "전략 지도가 동아시아 프로빈스 원본 ID를 유지해야 한다.")
    _expect(gateway.province(1).get("polygon", []).size() == 6, "전략 지도가 동아시아 전용 프로빈스 좌표를 사용해야 한다.")
    var province: Dictionary = governance_snapshot.get("provinces", {}).get("1", {})
    _expect(String(province.get("name", "")) == "국내성 권역", "첫 프로빈스가 국내성 권역이어야 한다.")
    _expect(String(province.get("governor_name", "")) == "해무진", "Codex2의 이름 있는 통치자가 연결되어야 한다.")
    _expect(province.get("strategic_point_ids", []).size() >= 5, "프로빈스에 핵심 지점이 5개 이상 있어야 한다.")

    component.call("_open_dashboard")
    await process_frame
    var dashboard = component.get("dashboard")
    _expect(dashboard != null and dashboard.visible, "메인 씬에서 통치 대시보드를 실제로 열 수 있어야 한다.")

    gateway.autosave_path = TEST_SAVE_PATH
    var core_turn_before := int(gateway.snapshot().get("turn", -1))
    var governance_turn_before := int(governance.turn)
    gateway.submit_turn()
    await process_frame
    var saved_core_turn := int(gateway.snapshot().get("turn", -1))
    var saved_governance_turn := int(governance.turn)
    _expect(saved_core_turn == core_turn_before + 1, "턴 실행 후 코어 턴이 1 증가해야 한다.")
    _expect(saved_governance_turn == governance_turn_before + 1, "턴 실행 후 통치 턴도 동시에 1 증가해야 한다.")
    _expect(FileAccess.file_exists(TEST_SAVE_PATH), "턴 종료 시 통합 자동 저장 파일이 생성되어야 한다.")

    var saved = _read_json(TEST_SAVE_PATH)
    _expect(saved is Dictionary and int(saved.get("schema_version", -1)) == 2, "통합 세이브에 데이터 버전 2가 기록되어야 한다.")
    var envelope: Dictionary = saved.get("governance_state", {}) if saved is Dictionary else {}
    _expect(int(envelope.get("core_turn", -1)) == saved_core_turn, "통치 저장의 코어 턴이 같은 파일의 코어 턴과 일치해야 한다.")
    _expect(int(envelope.get("state", {}).get("turn", -1)) == saved_governance_turn, "통치 턴이 통합 세이브에 함께 기록되어야 한다.")

    governance.turn = 77
    _expect(gateway.load_autosave(), "통합 자동 저장을 불러올 수 있어야 한다.")
    await process_frame
    _expect(int(gateway.snapshot().get("turn", -1)) == saved_core_turn, "불러오기 시 코어 상태가 복원되어야 한다.")
    _expect(int(governance.turn) == saved_governance_turn, "불러오기 시 통치 상태도 함께 복원되어야 한다.")

    _expect(gateway.select_player_country("baekje"), "백제로 새 게임을 시작할 수 있어야 한다.")
    await process_frame
    _expect(int(gateway.snapshot().get("turn", -1)) == 1, "새 게임은 첫 턴에서 시작해야 한다.")
    _expect(int(governance.turn) == 0, "새 게임은 이전 통치 세이브를 무단 복원하지 않아야 한다.")

    root.queue_free()
    await process_frame
    _remove_test_save()
    _finish()


func _read_json(path: String):
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    return JSON.parse_string(file.get_as_text())


func _remove_test_save() -> void:
    if FileAccess.file_exists(TEST_SAVE_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FAIL] %s" % message)


func _watchdog_timeout() -> void:
    if finished:
        return
    failures.append("메인 런타임 테스트가 제한 시간 안에 종료되지 않았다.")
    _finish()


func _finish() -> void:
    if finished:
        return
    finished = true
    _remove_test_save()
    if failures.is_empty():
        print("Main runtime test: PASS")
        quit(0)
    else:
        push_error("Main runtime test: %d failure(s)" % failures.size())
        for failure in failures:
            push_error(" - %s" % failure)
        quit(1)
