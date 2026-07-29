extends SceneTree

const TEST_PREFS_PATH := "user://ui_shell_test_preferences.json"

class MockCityProvider:
    extends RefCounted
    var ids := ["seoul", "busan", "tokyo"]
    var selected := "busan"
    var active_tab := "economy"
    var focused := ""

    func getOrderedCityIds() -> Array:
        return ids.duplicate()

    func getSelectedCityId() -> String:
        return selected

    func selectCityById(city_id: String) -> void:
        selected = city_id

    func focusCameraOnCity(city_id: String) -> void:
        focused = city_id


var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _remove_preferences()
    await _test_preferences_and_top_bar()
    await _test_zoom_input_and_city_cycle()
    _test_notifications()
    _test_turn_end_guard()
    _test_main_scene_contract()
    await process_frame
    await process_frame
    await process_frame
    _remove_preferences()
    for child in get_root().get_children():
        if is_instance_valid(child):
            child.free()
    if failures.is_empty():
        print("UI shell/input/notifications test: PASS")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)


func _test_preferences_and_top_bar() -> void:
    var preferences := UIShellPreferences.new(TEST_PREFS_PATH)
    preferences.load_preferences()
    var order: Array = preferences.top_bar().order
    order.erase("legitimacy")
    order.insert(0, "legitimacy")
    var visible: Array = preferences.top_bar().visible
    visible.append("legitimacy")
    preferences.set_top_bar(order, visible, "compact")
    _expect(FileAccess.file_exists(TEST_PREFS_PATH), "상단 정보 바 설정이 별도 사용자 설정 파일에 저장되어야 한다.")
    var restored := UIShellPreferences.new(TEST_PREFS_PATH)
    restored.load_preferences()
    _expect(String(restored.top_bar().order[0]) == "legitimacy", "새로고침 후 드래그 순서가 복원되어야 한다.")
    _expect("legitimacy" in restored.top_bar().visible, "새로고침 후 표시 항목이 복원되어야 한다.")
    _expect(String(restored.top_bar().display_mode) == "compact", "아이콘형·상세형 선택이 복원되어야 한다.")

    var bar := ConfigurableTopBar.new()
    bar.set_preferences(restored)
    bar.size = Vector2(1920, 58)
    get_root().add_child(bar)
    await process_frame
    bar.set_item_visible("legitimacy", false)
    _expect("legitimacy" not in bar.visible_item_ids(), "선택 항목을 상단 바에서 숨길 수 있어야 한다.")
    bar.set_item_visible("legitimacy", true)
    bar.reorder_item("legitimacy", "date")
    _expect(bar.item_order().find("legitimacy") < bar.item_order().find("date"), "상단 항목을 드래그 계약으로 재정렬할 수 있어야 한다.")
    var all_visible := UIShellPreferences.ITEM_IDS.duplicate()
    restored.set_top_bar(restored.top_bar().order, all_visible, "detail")
    bar.size = Vector2(1366, 58)
    bar.call("_refresh_layout")
    await process_frame
    _expect(bar.forced_compact, "1366px에서 항목이 많으면 자동으로 간략형으로 축약되어야 한다.")
    restored.set_top_bar(restored.top_bar().order, UIShellPreferences.REQUIRED_IDS, "detail")
    bar.call("_refresh_items")
    bar.size = Vector2(1920, 58)
    bar.call("_refresh_layout")
    await process_frame
    _expect(not bar.forced_compact, "1920px에서 기본 항목은 상세형을 유지해야 한다.")
    bar.queue_free()
    await process_frame
    var corrupt_file := FileAccess.open(TEST_PREFS_PATH, FileAccess.WRITE)
    corrupt_file.store_string("{broken")
    corrupt_file = null
    var recovered := UIShellPreferences.new(TEST_PREFS_PATH)
    recovered.load_preferences()
    _expect(not recovered.last_error.is_empty() and "date" in recovered.top_bar().visible, "손상된 UI 설정은 필수 항목 기본값으로 안전 복구되어야 한다.")


func _test_zoom_input_and_city_cycle() -> void:
    var map := StrategicMap.new()
    map.size = Vector2(1280, 720)
    get_root().add_child(map)
    await process_frame
    map.frame_world()
    await process_frame
    var before_wheel := map.zoom
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    wheel.position = Vector2(640, 360)
    map.call("_gui_input", wheel)
    _expect(map.zoom > before_wheel, "마우스 휠로 연속 확대할 수 있어야 한다.")
    map.set_zoom_tier("strategy")
    _expect(map.semantic_zoom_tier() == "strategy", "전략 확대 버튼이 전략 정보 단계로 이동해야 한다.")
    map.set_zoom_tier("region")
    _expect(map.semantic_zoom_tier() == "region", "지역 확대 버튼이 지역 정보 단계로 이동해야 한다.")
    map.set_zoom_tier("close")
    _expect(map.semantic_zoom_tier() == "close", "근접 확대 버튼이 근접 정보 단계로 이동해야 한다.")

    var provider := MockCityProvider.new()
    var adapter := CityNavigationAdapter.new()
    adapter.bind(map, provider)
    var router := MapInputRouter.new()
    get_root().add_child(router)
    router.bind(map, adapter)
    router.set_active(true)
    var tab_before := provider.active_tab
    var right := InputEventKey.new()
    right.keycode = KEY_RIGHT
    right.pressed = true
    _expect(router.handle_key(right), "도시 선택 상태에서 오른쪽 방향키를 소비해야 한다.")
    _expect(provider.selected == "tokyo" and provider.focused == "tokyo", "오른쪽 방향키가 다음 도시를 선택하고 카메라를 이동해야 한다.")
    _expect(provider.active_tab == tab_before, "도시 순환 중 현재 도시 패널 탭은 유지되어야 한다.")
    router.handle_key(right)
    _expect(provider.selected == "seoul", "마지막 도시 다음에는 첫 도시로 순환해야 한다.")
    var left := InputEventKey.new()
    left.keycode = KEY_LEFT
    left.pressed = true
    router.handle_key(left)
    _expect(provider.selected == "tokyo", "첫 도시 이전에는 마지막 도시로 순환해야 한다.")

    adapter.set_provider(null)
    adapter.clear_selection()
    map.go_to_lonlat(126.978, 37.5665, 1.65)
    var pan_before := map.pan
    router.handle_key(left)
    _expect(map.pan != pan_before, "도시 미선택 상태에서 방향키는 지도 이동이어야 한다.")
    var w := InputEventKey.new()
    w.keycode = KEY_W
    w.pressed = true
    pan_before = map.pan
    router.handle_key(w)
    _expect(map.pan != pan_before, "WASD로 지도를 이동할 수 있어야 한다.")
    var search := LineEdit.new()
    pan_before = map.pan
    _expect(not router.handle_key(left, search) and map.pan == pan_before, "검색·텍스트 입력 포커스 중 방향키 단축키가 입력을 방해하지 않아야 한다.")
    search.free()
    router.queue_free()
    map.queue_free()
    await process_frame


func _test_notifications() -> void:
    var center := NotificationCenter.new()
    get_root().add_child(center)
    var pause_events: Array[bool] = []
    center.pause_requested.connect(func(value): pause_events.append(value))
    var first := center.add_notification({
        "kind": "food_decline", "severity": "caution", "title": "식량 감소",
        "message": "서울 식량이 감소했습니다.", "city_id": "seoul"
    })
    center.add_notification({
        "kind": "food_decline", "severity": "caution", "title": "식량 감소",
        "message": "서울 식량이 다시 감소했습니다.", "city_id": "seoul"
    })
    _expect(center.all_notifications().size() == 1 and int(center.all_notifications()[0].repeat_count) == 2, "동일 반복 알림을 한 항목으로 묶어야 한다.")
    center.add_notification({
        "kind": "stability_decline", "severity": "warning", "title": "안정도 악화",
        "message": "서울 안정도가 악화했습니다.", "city_id": "seoul"
    })
    _expect(center.crisis_cards().size() == 1 and center.crisis_cards()[0].notifications.size() == 2, "같은 도시의 여러 경고를 도시 위기 카드로 통합해야 한다.")
    var urgent := center.add_notification({
        "kind": "capital_siege", "severity": "urgent", "title": "수도 포위",
        "message": "수도가 포위되었습니다.", "city_id": "seoul"
    })
    _expect(not pause_events.is_empty() and pause_events.back(), "긴급 알림은 자동 일시정지를 요청해야 한다.")
    _expect(center.urgent_unread_count() == 1, "긴급 미확인 수를 상단 바에 제공해야 한다.")
    center.acknowledge(int(urgent.id))
    _expect(not pause_events.back(), "긴급 알림 확인 후 자동 일시정지를 해제해야 한다.")
    _expect(center.mark_read(int(first.id)), "알림 읽음 상태를 변경할 수 있어야 한다.")
    center.configure({"food_decline": {"banner": true}})
    _expect(bool(center.channels_for({"kind": "food_decline", "severity": "caution"}).get("banner", false)), "사건 종류별 표시 방식을 중요도 기본값과 별도로 설정할 수 있어야 한다.")
    var strict := {"urgent": {}}
    center.configure(strict)
    _expect(not center.channels_for({"kind": "urgent", "severity": "urgent"}).is_empty(), "긴급 알림은 모든 표시 방식을 완전히 비활성화할 수 없어야 한다.")
    center.queue_free()


func _test_turn_end_guard() -> void:
    var center := NotificationCenter.new()
    get_root().add_child(center)
    var guard := TurnEndGuard.new()
    guard.bind(center)
    guard.set_pending_items([
        {"id": "succession", "type": "mandatory_succession", "message": "후계자를 선택하십시오."},
        {"id": "build", "type": "empty_construction_queue", "message": "건설 대기열이 비었습니다."},
        {"id": "auto", "type": "stability_decline", "auto_governed": true}
    ])
    var report := guard.validate()
    _expect(not bool(report.can_end_turn) and int(report.blocker_count) == 1, "필수 정치 결정이 있으면 턴 종료를 차단해야 한다.")
    _expect(int(report.warning_count) == 1, "자동 통치 항목을 제외하고 일반 경고만 표시해야 한다.")
    guard.resolve_item("succession")
    report = guard.validate()
    _expect(bool(report.can_end_turn) and int(report.warning_count) == 1, "차단 항목 해결 즉시 턴 종료가 다시 가능해야 한다.")
    guard.ignore_for_turn("build")
    _expect(int(guard.validate().warning_count) == 0, "일반 경고를 이번 턴만 무시할 수 있어야 한다.")
    center.add_notification({
        "kind": "peace_offer", "severity": "decision_required", "title": "평화 제안",
        "message": "응답이 필요합니다."
    })
    _expect(guard.has_blockers(), "결정 필요 알림이 남아 있으면 턴 종료를 제한해야 한다.")
    center.resolve(int(center.pending_decisions()[0].id))
    _expect(not guard.has_blockers(), "필수 알림 해결 후 턴 종료 차단이 즉시 해제되어야 한다.")
    center.queue_free()


func _test_main_scene_contract() -> void:
    var packed = load("res://src/main.tscn")
    _expect(packed is PackedScene, "기준 메인 씬이 UI Shell 모듈과 함께 로드되어야 한다.")
    var main_script: Script = load("res://src/main.gd")
    var method_names: Array[String] = []
    for method in main_script.get_script_method_list():
        method_names.append(String(method.name))
    _expect("getOrderedCityIds" in method_names and "selectCityById" in method_names, "코덱스 2 도시 목록과 연결할 공용 계약을 제공해야 한다.")
    _expect("push_game_notification" in method_names, "F5 런타임이 알림 센터 입력 계약을 제공해야 한다.")
    _expect("set_turn_validation_items" in method_names, "F5 런타임이 턴 종료 검증 입력 계약을 제공해야 한다.")

func _remove_preferences() -> void:
    if FileAccess.file_exists(TEST_PREFS_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PREFS_PATH))


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FAIL] %s" % message)
