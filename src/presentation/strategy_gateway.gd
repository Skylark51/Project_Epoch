class_name StrategyGateway
extends RefCounted

const GameSession = preload("res://src/core/game_session.gd")
const CORE_SCENARIO := "res://data/scenarios/sample_campaign.json"
const AUTOSAVE_PATH := "user://autosave.json"

signal snapshot_changed(snapshot: Dictionary)
signal command_queue_changed(commands: Array)
signal turn_requested(commands: Array)
signal integration_notice(message: String)

var game := GameSession.new()
var _snapshot: Dictionary = {}
var _scenarios: Array[Dictionary] = []
var _commands: Array[Dictionary] = []
var _visual_geometry: Dictionary = {}
var _next_command_id := 1

func load_local_catalog() -> bool:
    _load_visual_geometry()
    var scenario_data = _load_json(CORE_SCENARIO)
    if scenario_data is Dictionary:
        _scenarios = [scenario_data.duplicate(true)]
    var result: Dictionary = game.start_scenario(CORE_SCENARIO, "")
    if not bool(result.get("ok", false)):
        integration_notice.emit("코어 시나리오를 시작하지 못했습니다: %s" % str(result.get("errors", result.get("reason", "알 수 없는 오류"))))
        return false
    _connect_core_events()
    _sync_from_core()
    return true

func snapshot() -> Dictionary:
    return _snapshot.duplicate(true)

func scenarios() -> Array[Dictionary]:
    return _scenarios.duplicate(true)

func countries() -> Dictionary:
    return _snapshot.get("countries", {}).duplicate(true)

func select_player_country(country_id: String) -> bool:
    var result: Dictionary = game.start_scenario(CORE_SCENARIO, country_id)
    if not bool(result.get("ok", false)):
        integration_notice.emit("국가 선택 실패: %s" % str(result.get("errors", result.get("reason", "알 수 없는 오류"))))
        return false
    _commands.clear()
    _next_command_id = 1
    _sync_from_core()
    command_queue_changed.emit(commands())
    return true

func commands() -> Array:
    return _commands.duplicate(true)

func queue_command(command_type: String, payload: Dictionary, presentation: Dictionary = {}) -> int:
    var mapped := _map_command(command_type, payload)
    if mapped.is_empty():
        integration_notice.emit("현재 코어에서 지원하지 않는 명령입니다: %s" % command_type)
        return -1
    var result: Dictionary = game.submit_command(String(mapped.type), mapped.values)
    if not bool(result.get("valid", false)):
        integration_notice.emit("명령 거부: %s" % str(result.get("reason", "검증 실패")))
        return -1
    var core_command: Dictionary = result.get("command", {})
    var wrapper := {
        "id": _next_command_id,
        "type": command_type,
        "country_id": String(mapped.values.get("country_id", _snapshot.get("player_country_id", ""))),
        "payload": payload.duplicate(true),
        "presentation": presentation.duplicate(true),
        "status": "validated",
        "core_command_id": String(core_command.get("command_id", ""))
    }
    _commands.append(wrapper)
    _next_command_id += 1
    command_queue_changed.emit(commands())
    return int(wrapper.id)

func update_command(command_id: int, payload: Dictionary) -> bool:
    for wrapper in _commands:
        if int(wrapper.get("id", -1)) == command_id:
            var type := String(wrapper.get("type", ""))
            var presentation: Dictionary = wrapper.get("presentation", {}).duplicate(true)
            if not cancel_command(command_id):
                return false
            return queue_command(type, payload, presentation) != -1
    return false

func cancel_command(command_id: int) -> bool:
    for index in range(_commands.size()):
        var wrapper: Dictionary = _commands[index]
        if int(wrapper.get("id", -1)) != command_id:
            continue
        var core_id := String(wrapper.get("core_command_id", ""))
        var kept: Array[Dictionary] = []
        for item in game.queue.peek():
            if String(item.get("command_id", "")) != core_id:
                kept.append(item)
        var next_id := int(game.queue.to_dict().get("next_id", 1))
        game.queue.restore({"commands": kept, "next_id": next_id})
        if game.state != null:
            game.state.command_queue = game.queue.to_dict()
        _commands.remove_at(index)
        command_queue_changed.emit(commands())
        return true
    return false

func clear_commands() -> void:
    var ai_only: Array[Dictionary] = []
    for item in game.queue.peek():
        if String(item.get("country_id", "")) != String(_snapshot.get("player_country_id", "")):
            ai_only.append(item)
    game.queue.restore({"commands": ai_only, "next_id": int(game.queue.to_dict().get("next_id", 1))})
    _commands.clear()
    command_queue_changed.emit(commands())

func submit_turn() -> void:
    turn_requested.emit(commands())
    var result: Dictionary = game.end_turn()
    if not bool(result.get("ok", false)):
        integration_notice.emit("턴 처리 실패: %s" % str(result.get("reason", "알 수 없는 오류")))
        return
    _commands.clear()
    command_queue_changed.emit(commands())
    _sync_from_core()
    var save_result: Dictionary = game.save(AUTOSAVE_PATH)
    if not bool(save_result.get("ok", false)):
        integration_notice.emit("자동 저장 실패: %s" % str(save_result.get("error", "알 수 없는 오류")))
    else:
        integration_notice.emit("턴 처리가 완료되고 자동 저장되었습니다.")

func province(province_id: int) -> Dictionary:
    return _snapshot.get("provinces", {}).get(province_id, {}).duplicate(true)

func country(country_id: String) -> Dictionary:
    return _snapshot.get("countries", {}).get(country_id, {}).duplicate(true)

func relation(a: String, b: String) -> int:
    if a == b:
        return 100
    return int(_snapshot.get("relations", {}).get(_pair_key(a, b), 0))

func at_war(a: String, b: String) -> bool:
    for war in _snapshot.get("wars", []):
        var attacker := String(war.get("attacker", ""))
        var defender := String(war.get("defender", ""))
        if (attacker == a and defender == b) or (attacker == b and defender == a):
            return true
    return false

func load_autosave() -> bool:
    var result: Dictionary = game.load(AUTOSAVE_PATH)
    if not bool(result.get("ok", false)):
        integration_notice.emit("불러오기 실패: %s" % str(result.get("error", "저장 파일 없음")))
        return false
    _commands.clear()
    _sync_from_core()
    command_queue_changed.emit(commands())
    return true

func _map_command(command_type: String, payload: Dictionary) -> Dictionary:
    var player := String(_snapshot.get("player_country_id", ""))
    var values := {"country_id": player}
    var core_type := command_type
    match command_type:
        "recruit":
            values.target_id = int(payload.get("province_id", -1))
            values.amount = int(payload.get("amount", 0))
        "move", "attack":
            values.source_id = int(payload.get("from_id", -1))
            values.target_id = int(payload.get("to_id", -1))
            values.amount = int(payload.get("amount", 0))
            values.payload = {"leave_garrison": int(payload.get("leave_garrison", 1))}
        "develop":
            values.target_id = int(payload.get("province_id", -1))
        "fortify":
            core_type = "build_fort"
            values.target_id = int(payload.get("province_id", -1))
        "declare_war", "improve_relations":
            values.target_id = String(payload.get("target_country_id", ""))
        "offer_alliance":
            core_type = "form_alliance"
            values.target_id = String(payload.get("target_country_id", ""))
        "demand_vassalization":
            core_type = "create_vassal"
            values.target_id = String(payload.get("target_country_id", ""))
        "peace_offer":
            core_type = "offer_peace"
            values.target_id = String(payload.get("target_country_id", ""))
            values.payload = {"terms": {
                "province_ids": payload.get("province_demands", []).duplicate(),
                "reparations": float(payload.get("reparations", 0)),
                "vassalize": bool(payload.get("vassalize", false)),
                "recognize_independence": bool(payload.get("recognize_independence", false))
            }}
        _:
            return {}
    return {"type": core_type, "values": values}

func _sync_from_core() -> void:
    _snapshot = _presentation_snapshot(game.get_public_snapshot())
    snapshot_changed.emit(snapshot())

func _presentation_snapshot(core: Dictionary) -> Dictionary:
    var result := {
        "countries": {}, "provinces": {}, "armies": {}, "relations": core.get("relations", {}).duplicate(true),
        "wars": [], "player_country_id": String(core.get("player_country_id", "")),
        "date": core.get("date", {}).duplicate(true), "turn": int(core.get("turn", 1))
    }
    for id_value in core.get("countries", {}).keys():
        var id := String(id_value)
        var source: Dictionary = core.countries[id_value]
        var country_item := source.duplicate(true)
        country_item["capital_province"] = int(source.get("capital_province_id", -1))
        country_item["government"] = String(source.get("government_id", "정부"))
        country_item["income"] = 0
        result.countries[id] = country_item
    for id_value in core.get("provinces", {}).keys():
        var id := int(id_value)
        var source: Dictionary = core.provinces[id_value]
        var province_item := source.duplicate(true)
        province_item["owner"] = String(source.get("owner_id", ""))
        province_item["controller"] = String(source.get("controller_id", province_item.owner))
        province_item["fort"] = int(source.get("fort_level", 0))
        province_item["revolt_risk"] = float(source.get("unrest", 0.0))
        province_item["polygon"] = _visual_geometry.get(id, _fallback_polygon(id))
        result.provinces[id] = province_item
        result.armies[id] = 0
    for army in core.get("armies", {}).values():
        var province_id := int(army.get("province_id", -1))
        result.armies[province_id] = int(result.armies.get(province_id, 0)) + int(army.get("soldiers", 0))
    for war in core.get("wars", {}).values():
        var attackers: Array = war.get("attackers", [])
        var defenders: Array = war.get("defenders", [])
        result.wars.append({
            "id": war.get("id", ""), "attacker": String(attackers[0]) if not attackers.is_empty() else "",
            "defender": String(defenders[0]) if not defenders.is_empty() else "", "score": float(war.get("score", 0.0)),
            "war_score": float(war.get("score", 0.0)), "attackers": attackers.duplicate(), "defenders": defenders.duplicate()
        })
    return result

func _load_visual_geometry() -> void:
    _visual_geometry.clear()
    var legacy = _load_json("res://data/provinces.json")
    if legacy is Dictionary:
        for province_item in legacy.get("provinces", []):
            if province_item is Dictionary and province_item.has("polygon"):
                _visual_geometry[int(province_item.get("id", -1))] = province_item.polygon.duplicate(true)

func _fallback_polygon(province_id: int) -> Array:
    var index: int = maxi(0, province_id - 1)
    var column: int = index % 3
    var row: int = int(index / 3)
    var x: float = 70.0 + column * 245.0
    var y: float = 60.0 + row * 170.0
    return [[x, y + 20.0], [x + 55.0, y], [x + 205.0, y + 12.0], [x + 220.0, y + 118.0], [x + 150.0, y + 145.0], [x + 18.0, y + 130.0]]

func _connect_core_events() -> void:
    if not game.events.turn_phase_completed.is_connected(_on_turn_phase):
        game.events.turn_phase_completed.connect(_on_turn_phase)
    if not game.events.command_rejected.is_connected(_on_command_rejected):
        game.events.command_rejected.connect(_on_command_rejected)

func _on_turn_phase(phase: String, entries: Array) -> void:
    if not entries.is_empty():
        integration_notice.emit("턴 단계 완료: %s · %d건" % [phase, entries.size()])

func _on_command_rejected(result: Dictionary) -> void:
    integration_notice.emit("코어 명령 거부: %s" % str(result.get("reason", "검증 실패")))

func _load_json(path: String):
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    return JSON.parse_string(file.get_as_text())

func _pair_key(a: String, b: String) -> String:
    return a + "|" + b if a < b else b + "|" + a
