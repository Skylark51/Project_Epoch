class_name TurnProcessor
extends RefCounted

var strategy_ai

func _init() -> void:
    var strategy_ai_script = load("res://src/ai/strategy_ai.gd")
    if strategy_ai_script != null:
        strategy_ai = strategy_ai_script.new()

func process_turn(state) -> Array[String]:
    var logs: Array[String] = []
    var commands: Array[Dictionary] = state.command_queue.drain()
    if strategy_ai != null:
        var ai_commands: Array[Dictionary] = strategy_ai.plan_turn(state)
        commands.append_array(ai_commands)
    else:
        logs.append("[경고] AI 모듈을 불러오지 못했습니다.")

    logs.append("[명령 수집] 플레이어·AI 명령 %d건" % commands.size())
    _resolve_diplomacy(state, commands, logs)
    _resolve_recruitment(state, commands, logs)
    _resolve_movement(state, commands, logs)
    logs.append_array(state.apply_economy_phase())
    logs.append_array(state.apply_growth_phase())
    if state.diplomacy != null:
        logs.append_array(state.diplomacy.advance_turn(state.countries))
    state.advance_calendar()
    return logs

func _resolve_diplomacy(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[외교 단계]")
    if state.diplomacy == null:
        logs.append("외교 모듈 없음")
        return
    for command in commands:
        var command_type := String(command.get("type", ""))
        if command_type not in ["declare_war", "offer_peace"]:
            continue
        var country_id := String(command.get("country_id", ""))
        var payload: Dictionary = command.get("payload", {})
        var target_id := String(payload.get("target_country_id", ""))
        if not state.country_is_alive(country_id) or not state.country_is_alive(target_id):
            continue
        if command_type == "declare_war":
            var result := state.diplomacy.declare_war(country_id, target_id, state.turn)
            logs.append("%s → %s: %s" % [String(state.countries[country_id].get("name", country_id)), String(state.countries[target_id].get("name", target_id)), result])
        else:
            var peace_result := state.resolve_peace_offer(country_id, target_id)
            logs.append("%s → %s: %s" % [String(state.countries[country_id].get("name", country_id)), String(state.countries[target_id].get("name", target_id)), peace_result])

func _resolve_recruitment(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[모집 단계]")
    for command in commands:
        if String(command.get("type", "")) != "recruit":
            continue
        var payload: Dictionary = command.get("payload", {})
        logs.append(state.execute_recruit(String(command.get("country_id", "")), int(payload.get("province_id", -1)), int(payload.get("amount", 0))))

func _resolve_movement(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[이동·전투 단계]")
    for command in commands:
        if String(command.get("type", "")) != "move":
            continue
        var payload: Dictionary = command.get("payload", {})
        logs.append(state.execute_move(String(command.get("country_id", "")), int(payload.get("from_id", -1)), int(payload.get("to_id", -1)), int(payload.get("amount", 0))))
