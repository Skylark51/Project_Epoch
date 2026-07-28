class_name TurnProcessor
extends RefCounted

var strategy_ai := StrategyAI.new()

func process_turn(state) -> Array[String]:
    var logs: Array[String] = []
    var commands: Array[Dictionary] = state.command_queue.drain()
    var ai_commands := strategy_ai.plan_turn(state)
    commands.append_array(ai_commands)

    logs.append("[명령 수집] 플레이어·AI 명령 %d건" % commands.size())
    _resolve_diplomacy(state, commands, logs)
    _resolve_recruitment(state, commands, logs)
    _resolve_movement(state, commands, logs)
    logs.append_array(state.apply_economy_phase())
    logs.append_array(state.apply_growth_phase())
    logs.append_array(state.diplomacy.advance_turn(state.countries))
    state.advance_calendar()
    return logs

func _resolve_diplomacy(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[외교 단계]")
    for command in commands:
        var command_type := String(command.type)
        if command_type not in ["declare_war", "offer_peace"]:
            continue
        var country_id := String(command.country_id)
        var target_id := String(command.payload.target_country_id)
        if not state.country_is_alive(country_id) or not state.country_is_alive(target_id):
            continue
        if command_type == "declare_war":
            var result := state.diplomacy.declare_war(country_id, target_id, state.turn)
            logs.append("%s → %s: %s" % [state.countries[country_id].name, state.countries[target_id].name, result])
        else:
            var peace_result := state.resolve_peace_offer(country_id, target_id)
            logs.append("%s → %s: %s" % [state.countries[country_id].name, state.countries[target_id].name, peace_result])

func _resolve_recruitment(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[모집 단계]")
    for command in commands:
        if String(command.type) != "recruit":
            continue
        var payload: Dictionary = command.payload
        logs.append(state.execute_recruit(String(command.country_id), int(payload.province_id), int(payload.amount)))

func _resolve_movement(state, commands: Array[Dictionary], logs: Array[String]) -> void:
    logs.append("[이동·전투 단계]")
    for command in commands:
        if String(command.type) != "move":
            continue
        var payload: Dictionary = command.payload
        logs.append(state.execute_move(String(command.country_id), int(payload.from_id), int(payload.to_id), int(payload.amount)))
