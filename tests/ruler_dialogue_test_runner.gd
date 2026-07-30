extends SceneTree

var failures: Array[String] = []
var finished := false


func _initialize() -> void:
    var watchdog := create_timer(20.0)
    watchdog.timeout.connect(_watchdog_timeout)
    call_deferred("_run")


func _run() -> void:
    var scene = load("res://src/main.tscn")
    _expect(scene is PackedScene, "메인 장면을 불러올 수 있어야 한다.")
    if scene is not PackedScene:
        _finish()
        return

    var root = scene.instantiate()
    get_root().add_child(root)
    await process_frame
    await process_frame
    await process_frame
    await process_frame

    var dialogue = root.get_node_or_null("RulerDialogueOverlay")
    _expect(dialogue != null, "메인 장면에 군주 대화 오버레이가 포함되어야 한다.")
    if dialogue == null:
        root.queue_free()
        await process_frame
        _finish()
        return

    _expect(dialogue.get_node_or_null("RulerDialogueLauncher") != null, "군주 접견 버튼이 생성되어야 한다.")
    _expect(dialogue.get_node_or_null("RulerDialogueShade/RulerDialoguePanel") != null, "군주 대화 패널이 생성되어야 한다.")
    _expect(dialogue.get("ruler_catalog").has("goguryeo"), "고구려 군주 데이터가 등록되어야 한다.")

    var opened: bool = dialogue.call("open_dialogue", "goguryeo")
    _expect(opened, "고구려 군주 대화를 열 수 있어야 한다.")
    await process_frame

    _expect(dialogue.call("is_dialogue_open"), "대화 패널이 실제로 표시되어야 한다.")
    _expect(String(dialogue.get("current_ruler").get("name", "")) == "광개토대왕", "광개토대왕 이름이 대화 데이터에서 로드되어야 한다.")
    _expect(int(dialogue.get("current_ruler").get("frame_count", 0)) == 30, "초상 시트가 30프레임으로 정의되어야 한다.")

    dialogue.call("_set_frame", 29)
    _expect(int(dialogue.get("current_frame")) == 29, "마지막 프레임까지 선택할 수 있어야 한다.")
    var atlas = dialogue.get("portrait_atlas")
    _expect(atlas != null and atlas.region.size == Vector2(64, 64), "각 초상 프레임은 64×64이어야 한다.")

    dialogue.call("close_dialogue")
    _expect(not dialogue.call("is_dialogue_open"), "군주 대화를 종료할 수 있어야 한다.")

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
    failures.append("군주 대화 테스트가 제한 시간 안에 종료되지 않았다.")
    _finish()


func _finish() -> void:
    if finished:
        return
    finished = true
    if failures.is_empty():
        print("Ruler dialogue test: PASS")
        quit(0)
    else:
        push_error("Ruler dialogue test: %d failure(s)" % failures.size())
        for failure in failures:
            push_error(" - %s" % failure)
        quit(1)
