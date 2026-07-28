class_name CommandQueue
extends RefCounted

var commands: Array[Dictionary] = []
var next_id: int = 1

func clear() -> void:
    commands.clear()
    next_id = 1

func add_command(command_type: String, country_id: String, payload: Dictionary) -> Dictionary:
    var command := {
        "id": next_id,
        "type": command_type,
        "country_id": country_id,
        "payload": payload.duplicate(true)
    }
    next_id += 1
    commands.append(command)
    return command

func queue_recruit(country_id: String, province_id: int, amount: int) -> Dictionary:
    return add_command("recruit", country_id, {"province_id": province_id, "amount": amount})

func queue_move(country_id: String, from_id: int, to_id: int, amount: int) -> Dictionary:
    return add_command("move", country_id, {"from_id": from_id, "to_id": to_id, "amount": amount})

func queue_declare_war(country_id: String, target_country_id: String) -> Dictionary:
    return add_command("declare_war", country_id, {"target_country_id": target_country_id})

func queue_offer_peace(country_id: String, target_country_id: String) -> Dictionary:
    return add_command("offer_peace", country_id, {"target_country_id": target_country_id})

func cancel(command_id: int) -> bool:
    for index in range(commands.size()):
        if int(commands[index].id) == command_id:
            commands.remove_at(index)
            return true
    return false

func has_move_from(country_id: String, province_id: int) -> bool:
    for command in commands:
        if String(command.country_id) != country_id or String(command.type) != "move":
            continue
        if int(command.payload.from_id) == province_id:
            return true
    return false

func has_diplomacy_command(command_type: String, country_id: String, target_country_id: String) -> bool:
    for command in commands:
        if String(command.type) != command_type or String(command.country_id) != country_id:
            continue
        if String(command.payload.target_country_id) == target_country_id:
            return true
    return false

func reserved_recruitment(country_id: String) -> Dictionary:
    var treasury: int = 0
    var manpower: int = 0
    for command in commands:
        if String(command.country_id) != country_id or String(command.type) != "recruit":
            continue
        var amount := int(command.payload.amount)
        treasury += amount * 2
        manpower += amount
    return {"treasury": treasury, "manpower": manpower}

func drain() -> Array[Dictionary]:
    var drained: Array[Dictionary] = []
    for command in commands:
        drained.append(command.duplicate(true))
    commands.clear()
    return drained

func summary_for_country(country_id: String, state) -> Array[String]:
    var lines: Array[String] = []
    for command in commands:
        if String(command.country_id) != country_id:
            continue
        var payload: Dictionary = command.payload
        match String(command.type):
            "recruit":
                var province_id := int(payload.province_id)
                lines.append("#%d 모집 · %s +%d" % [command.id, state.provinces[province_id].name, payload.amount])
            "move":
                var from_id := int(payload.from_id)
                var to_id := int(payload.to_id)
                lines.append("#%d 이동 · %s → %s (%d)" % [command.id, state.provinces[from_id].name, state.provinces[to_id].name, payload.amount])
            "declare_war":
                var target_id := String(payload.target_country_id)
                lines.append("#%d 외교 · %s에 전쟁 선포" % [command.id, state.countries[target_id].name])
            "offer_peace":
                var peace_target := String(payload.target_country_id)
                lines.append("#%d 외교 · %s에 평화 제안" % [command.id, state.countries[peace_target].name])
    return lines
