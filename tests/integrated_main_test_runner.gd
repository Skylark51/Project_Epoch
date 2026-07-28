extends SceneTree

var failures: Array[String] = []
var finished := false


func _initialize() -> void:
    var watchdog := create_timer(30.0)
    watchdog.timeout.connect(_watchdog_timeout)
    call_deferred("_run")


func _run() -> void:
    var scene = load("res://src/integration/integrated_main.tscn")
    _expect(scene is PackedScene, "통합 메인 씬을 불러올 수 있어야 한다.")
    if scene is not PackedScene:
        _finish()
        return

    var root = scene.instantiate()
    get_root().add_child(root)
    await process_frame
    await process_frame
    await process_frame
    await process_frame

    _expect(root.get("base_ui") != null, "기존 전략 UI가 통합 루트에 포함되어야 한다.")
    _expect(root.get("governance") != null, "GovernanceSession이 생성되어야 한다.")
    _expect(root.get_node_or_null("GovernanceLauncher") != null, "통치·반란 실행 버튼이 있어야 한다.")
    _expect(root.get_node_or_null("GovernanceDashboard") != null, "통치 대시보드가 있어야 한다.")

    var governance = root.get("governance")
    if governance != null:
        var snapshot: Dictionary = governance.snapshot()
        _expect(snapshot.get("factions", {}).size() >= 3, "기존 국가가 통치 시스템에 등록되어야 한다.")
        _expect(snapshot.get("provinces", {}).size() >= 9, "기존 프로빈스가 통치 시스템에 등록되어야 한다.")
        _expect(snapshot.get("political_groups", {}).get("AUR", {}).size() == 5, "기본 정치 집단 5개가 등록되어야 한다.")
        var province: Dictionary = snapshot.get("provinces", {}).get("1", {})
        _expect(String(province.get("governor_name", "")) != "", "모든 프로빈스에 이름 있는 통치자가 있어야 한다.")
        _expect(province.get("strategic_point_ids", []).size() >= 5, "프로빈스에 핵심 지점이 5개 이상 있어야 한다.")

    root.call("_open_dashboard")
    await process_frame
    var dashboard = root.get("dashboard")
    _expect(dashboard != null and dashboard.visible, "통치 대시보드를 실제로 열 수 있어야 한다.")

    var before_turn := int(governance.turn) if governance != null else -1
    var gateway = root.call("_gateway")
    var core_snapshot: Dictionary = gateway.snapshot()
    root.call("_on_core_snapshot", {
        "turn": int(root.get("last_core_turn")) + 1,
        "player_country_id": "AUR",
        "countries": core_snapshot.get("countries", {}),
        "provinces": core_snapshot.get("provinces", {}),
        "armies": core_snapshot.get("armies", {}),
        "wars": [],
    })
    if governance != null:
        _expect(int(governance.turn) == before_turn + 1, "코어 턴 증가 시 통치 턴도 함께 진행되어야 한다.")

    root.queue_free()
    await process_frame
    _finish()


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FAIL] %s" % message)


func _watchdog_timeout() -> void:
    if finished:
        return
    failures.append("통합 런타임 테스트가 제한 시간 안에 종료되지 않았다.")
    _finish()


func _finish() -> void:
    if finished:
        return
    finished = true
    if failures.is_empty():
        print("Integrated main test: PASS")
        quit(0)
    else:
        push_error("Integrated main test: %d failure(s)" % failures.size())
        for failure in failures:
            push_error(" - %s" % failure)
        quit(1)
