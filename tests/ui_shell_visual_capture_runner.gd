extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
    for resolution in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
        get_root().size = resolution
        var packed = load("res://src/main.tscn")
        var root = packed.instantiate()
        get_root().add_child(root)
        await process_frame
        root.call("_start_game")
        await process_frame
        await process_frame
        await process_frame
        var bar = root.get("top_bar")
        var turn_button: Button = bar.turn_button
        var required_visible := 0
        for child in bar.item_row.get_children():
            if child is TopBarItem and child.visible and child.item_id in UIShellPreferences.REQUIRED_IDS:
                required_visible += 1
        _check(required_visible == UIShellPreferences.REQUIRED_IDS.size(), "%s 필수 상단 정보 항목 표시" % str(resolution))
        var urgent_button: Button = bar.urgent_button
        _check(bar.get_global_rect().end.x <= resolution.x + 1.0, "%s 상단 바 화면 폭" % str(resolution))
        _check(turn_button.get_global_rect().end.x <= resolution.x + 1.0, "%s 턴 종료 버튼 화면 안쪽" % str(resolution))
        _check(not turn_button.get_global_rect().intersects(urgent_button.get_global_rect()), "%s 긴급 알림·턴 종료 버튼 비중첩" % str(resolution))
        var image := get_root().get_texture().get_image()
        var output := "res://captures/ui_shell_%dx%d.png" % [resolution.x, resolution.y]
        var error := image.save_png(output)
        _check(error == OK, "%s 실행 화면 캡처" % str(resolution))
        root.queue_free()
        await process_frame
    if failures.is_empty():
        print("UI shell visual capture: PASS")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)


func _check(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FAIL] %s" % message)
