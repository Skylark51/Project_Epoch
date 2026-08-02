class_name StrategyGateway
extends RefCounted


const GameSessionScript = preload("res://src/core/game_session.gd")
const StrategyCommandMapperScript = preload(
    "res://src/presentation/strategy_command_mapper.gd"
)
const StrategySnapshotPresenterScript = preload(
    "res://src/presentation/strategy_snapshot_presenter.gd"
)

const CORE_SCENARIO := "res://data/scenarios/prototype_east_asia.json"
const AUTOSAVE_PATH := "user://autosave.json"


signal snapshot_changed(snapshot: Dictionary)
signal command_queue_changed(commands: Array)
signal turn_requested(commands: Array)
signal integration_notice(message: String)
signal new_game_started(snapshot: Dictionary)
signal autosave_loaded(snapshot: Dictionary)
signal notifications_changed(notifications: Array)


var autosave_path := AUTOSAVE_PATH
var game := GameSessionScript.new()

var _snapshot: Dictionary = {}
var _scenarios: Array[Dictionary] = []
var _commands: Array[Dictionary] = []
var _visual_geometry: Dictionary = {}
var _world_map_manifest: Dictionary = {}
var _next_command_id := 1
var _snapshot_presenter := StrategySnapshotPresenterScript.new()
var _ui_preferences_dirty := false


# -----------------------------------------------------------------------------
# Session lifecycle
# -----------------------------------------------------------------------------

func load_local_catalog() -> bool:
    _load_presentation_resources()

    var scenario_data = _load_json(CORE_SCENARIO)
    if scenario_data is Dictionary:
        _scenarios = [scenario_data.duplicate(true)]

    var result: Dictionary = game.start_scenario(CORE_SCENARIO, "")
    if not bool(result.get("ok", false)):
        _emit_start_failure(result)
        return false

    _connect_core_events()
    _sync_from_core()
    return true


func select_player_country(country_id: String) -> bool:
    var result: Dictionary = game.start_scenario(CORE_SCENARIO, country_id)
    if not bool(result.get("ok", false)):
        integration_notice.emit(
            "국가 선택 실패: %s" % _result_reason(result)
        )
        return false

    _reset_player_commands()
    _sync_from_core()

    new_game_started.emit(snapshot())
    command_queue_changed.emit(commands())
    return true


func submit_turn(force: bool = false) -> void:
    var validation := turn_end_validation()
    if not force and not validation.get("blocking", []).is_empty():
        integration_notice.emit("턴 종료 차단: 먼저 턴 검토 항목을 해결하세요.")
        return
    turn_requested.emit(commands())

    var result: Dictionary = game.end_turn(force)
    if not bool(result.get("ok", false)):
        integration_notice.emit(
            "턴 처리 실패: %s" % _result_reason(result)
        )
        return

    _commands.clear()
    command_queue_changed.emit(commands())
    _sync_from_core()
    _save_after_turn()


# -----------------------------------------------------------------------------
# Read-only presentation API
# -----------------------------------------------------------------------------

func snapshot() -> Dictionary:
    return _snapshot.duplicate(true)


func scenarios() -> Array[Dictionary]:
    return _scenarios.duplicate(true)


func countries() -> Dictionary:
    return _snapshot.get("countries", {}).duplicate(true)


func commands() -> Array:
    return _commands.duplicate(true)


func province(province_id: int) -> Dictionary:
    return _snapshot.get("provinces", {}).get(province_id, {}).duplicate(true)


func country(country_id: String) -> Dictionary:
    return _snapshot.get("countries", {}).get(country_id, {}).duplicate(true)


func relation(first_country_id: String, second_country_id: String) -> int:
    if first_country_id == second_country_id:
        return 100

    var relations: Dictionary = _snapshot.get("relations", {})
    return int(
        relations.get(
            _pair_key(first_country_id, second_country_id),
            0
        )
    )


func at_war(first_country_id: String, second_country_id: String) -> bool:
    for war_value in _snapshot.get("wars", []):
        if war_value is not Dictionary:
            continue

        var war: Dictionary = war_value
        var attacker := String(war.get("attacker", ""))
        var defender := String(war.get("defender", ""))

        var direct_match := (
            attacker == first_country_id
            and defender == second_country_id
        )
        var reverse_match := (
            attacker == second_country_id
            and defender == first_country_id
        )

        if direct_match or reverse_match:
            return true

    return false


# -----------------------------------------------------------------------------
# Command queue
# -----------------------------------------------------------------------------

func queue_command(
    command_type: String,
    payload: Dictionary,
    presentation: Dictionary = {}
) -> int:
    var mapped := _map_command(command_type, payload)
    if mapped.is_empty():
        integration_notice.emit(
            "현재 코어에서 지원하지 않는 명령입니다: %s" % command_type
        )
        return -1

    var result: Dictionary = game.submit_command(
        String(mapped.get("type", "")),
        mapped.get("values", {})
    )
    if not bool(result.get("valid", false)):
        integration_notice.emit(
            "명령 거부: %s" % _result_reason(result, "검증 실패")
        )
        return -1

    var core_command: Dictionary = result.get("command", {})
    var wrapper := _build_command_wrapper(
        command_type,
        payload,
        presentation,
        mapped,
        core_command
    )

    _commands.append(wrapper)
    _next_command_id += 1
    command_queue_changed.emit(commands())
    return int(wrapper.get("id", -1))


func update_command(command_id: int, payload: Dictionary) -> bool:
    for wrapper_value in _commands:
        if wrapper_value is not Dictionary:
            continue

        var wrapper: Dictionary = wrapper_value
        if int(wrapper.get("id", -1)) != command_id:
            continue

        var command_type := String(wrapper.get("type", ""))
        var presentation: Dictionary = wrapper.get(
            "presentation",
            {}
        ).duplicate(true)

        if not cancel_command(command_id):
            return false

        return queue_command(command_type, payload, presentation) != -1

    return false


func cancel_command(command_id: int) -> bool:
    for command_index in range(_commands.size()):
        var wrapper: Dictionary = _commands[command_index]
        if int(wrapper.get("id", -1)) != command_id:
            continue

        _remove_core_command(String(wrapper.get("core_command_id", "")))
        _commands.remove_at(command_index)
        command_queue_changed.emit(commands())
        return true

    return false


func clear_commands() -> void:
    var retained_ai_commands: Array[Dictionary] = []
    var player_country_id := String(
        _snapshot.get("player_country_id", "")
    )

    for queued_value in game.queue.peek():
        if queued_value is not Dictionary:
            continue

        var queued_command: Dictionary = queued_value
        if String(queued_command.get("country_id", "")) != player_country_id:
            retained_ai_commands.append(queued_command)

    var next_id := int(game.queue.to_dict().get("next_id", 1))
    game.queue.restore({
        "commands": retained_ai_commands,
        "next_id": next_id
    })

    _commands.clear()
    command_queue_changed.emit(commands())


# -----------------------------------------------------------------------------
# Save integration
# -----------------------------------------------------------------------------

func load_autosave() -> bool:
    var result: Dictionary = game.load(autosave_path)
    if not bool(result.get("ok", false)):
        integration_notice.emit(
            "불러오기 실패: %s" % _result_reason(result, "저장 파일 없음")
        )
        return false

    _commands.clear()
    _snapshot = _presentation_snapshot(game.get_public_snapshot())
    _ui_preferences_dirty = false

    autosave_loaded.emit(snapshot())
    snapshot_changed.emit(snapshot())
    notifications_changed.emit(notifications())
    command_queue_changed.emit(commands())
    return true


func set_governance_save_data(data: Dictionary) -> void:
    if game.state != null:
        game.state.governance_state = data.duplicate(true)


func governance_save_data() -> Dictionary:
    if game.state == null:
        return {}

    return game.state.governance_state.duplicate(true)
func turn_end_validation() -> Dictionary:
    return game.turn_end_validation(_ui_preferences_dirty)
func update_ui_preferences(patch: Dictionary) -> bool:
    var result: Dictionary = game.update_ui_preferences(patch)
    if not bool(result.get("ok", false)):
        integration_notice.emit("UI 설정 저장 실패: %s" % _result_reason(result))
        return false
    _ui_preferences_dirty = true
    _sync_from_core()
    return true
func ui_preferences() -> Dictionary:
    return _snapshot.get("ui_preferences", {}).duplicate(true)
func notifications() -> Array:
    return _snapshot.get("notifications", []).duplicate(true)
func mark_notification_read(notification_id: int) -> bool:
    var marked := game.mark_notification_read(notification_id)
    if marked:
        _sync_from_core()
    return marked
func governance_options(country_id: String = "") -> Array:
    var target_country_id := country_id if not country_id.is_empty() else String(_snapshot.get("player_country_id", ""))
    return game.governance_options(target_country_id)



func save_autosave() -> Dictionary:
    if game.state == null:
        return {
            "ok": false,
            "error": "시나리오가 시작되지 않음"
        }

    var result: Dictionary = game.save(autosave_path)
    if bool(result.get("ok", false)):
        _ui_preferences_dirty = false
    if not bool(result.get("ok", false)):
        integration_notice.emit(
            "통합 저장 실패: %s" % _result_reason(result)
        )

    return result


# -----------------------------------------------------------------------------
# Translation boundaries
# -----------------------------------------------------------------------------

func _map_command(command_type: String, payload: Dictionary) -> Dictionary:
    var player_country_id := String(
        _snapshot.get("player_country_id", "")
    )
    return StrategyCommandMapperScript.build(
        command_type,
        payload,
        player_country_id
    )


func _presentation_snapshot(core: Dictionary) -> Dictionary:
    return _snapshot_presenter.present(core)


# -----------------------------------------------------------------------------
# Internal orchestration
# -----------------------------------------------------------------------------

func _sync_from_core() -> void:
    _snapshot = _presentation_snapshot(game.get_public_snapshot())
    snapshot_changed.emit(snapshot())
    notifications_changed.emit(notifications())


func _load_presentation_resources() -> void:
    _load_visual_geometry()
    _world_map_manifest = _load_json(
        "res://data/maps/generated/east_asia_world_map_manifest.json"
    )
    _snapshot_presenter.configure(
        _visual_geometry,
        _world_map_manifest
    )


func _load_visual_geometry() -> void:
    _visual_geometry.clear()

    var legacy = _load_json("res://data/provinces.json")
    if legacy is not Dictionary:
        return

    for province_value in legacy.get("provinces", []):
        if province_value is not Dictionary:
            continue

        var province: Dictionary = province_value
        if not province.has("polygon"):
            continue

        var province_id := int(province.get("id", -1))
        _visual_geometry[province_id] = province.get(
            "polygon",
            []
        ).duplicate(true)


func _connect_core_events() -> void:
    if not game.events.turn_phase_completed.is_connected(_on_turn_phase):
        game.events.turn_phase_completed.connect(_on_turn_phase)

    if not game.events.command_rejected.is_connected(_on_command_rejected):
        game.events.command_rejected.connect(_on_command_rejected)


func _build_command_wrapper(
    command_type: String,
    payload: Dictionary,
    presentation: Dictionary,
    mapped: Dictionary,
    core_command: Dictionary
) -> Dictionary:
    var mapped_values: Dictionary = mapped.get("values", {})
    var country_id := String(
        mapped_values.get(
            "country_id",
            _snapshot.get("player_country_id", "")
        )
    )

    return {
        "id": _next_command_id,
        "type": command_type,
        "country_id": country_id,
        "payload": payload.duplicate(true),
        "presentation": presentation.duplicate(true),
        "status": "validated",
        "core_command_id": String(core_command.get("command_id", ""))
    }


func _remove_core_command(core_command_id: String) -> void:
    var retained_commands: Array[Dictionary] = []

    for queued_value in game.queue.peek():
        if queued_value is not Dictionary:
            continue

        var queued_command: Dictionary = queued_value
        if String(queued_command.get("command_id", "")) != core_command_id:
            retained_commands.append(queued_command)

    var next_id := int(game.queue.to_dict().get("next_id", 1))
    game.queue.restore({
        "commands": retained_commands,
        "next_id": next_id
    })

    if game.state != null:
        game.state.command_queue = game.queue.to_dict()


func _reset_player_commands() -> void:
    _commands.clear()
    _next_command_id = 1


func _save_after_turn() -> void:
    var save_result: Dictionary = game.save(autosave_path)
    if not bool(save_result.get("ok", false)):
        integration_notice.emit(
            "자동 저장 실패: %s" % _result_reason(save_result)
        )
        return

    integration_notice.emit("턴 처리가 완료되고 자동 저장되었습니다.")


func _emit_start_failure(result: Dictionary) -> void:
    var fallback_reason = result.get(
        "errors",
        result.get("reason", "알 수 없는 오류")
    )
    integration_notice.emit(
        "코어 시나리오를 시작하지 못했습니다: %s" % str(fallback_reason)
    )


func _on_turn_phase(phase: String, entries: Array) -> void:
    if entries.is_empty():
        return

    integration_notice.emit(
        "턴 단계 완료: %s · %d건" % [phase, entries.size()]
    )


func _on_command_rejected(result: Dictionary) -> void:
    integration_notice.emit(
        "코어 명령 거부: %s" % _result_reason(result, "검증 실패")
    )


func _load_json(path: String):
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null

    return JSON.parse_string(file.get_as_text())


func _result_reason(
    result: Dictionary,
    fallback := "알 수 없는 오류"
) -> String:
    return str(
        result.get(
            "reason",
            result.get("error", fallback)
        )
    )


func _pair_key(first_country_id: String, second_country_id: String) -> String:
    if first_country_id < second_country_id:
        return "%s|%s" % [first_country_id, second_country_id]

    return "%s|%s" % [second_country_id, first_country_id]
