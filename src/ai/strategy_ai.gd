class_name StrategyAI
extends RefCounted

func plan_turn(state) -> Array[Dictionary]:
    var commands: Array[Dictionary] = []
    for country_id_value in state.countries.keys():
        var country_id := String(country_id_value)
        if country_id == state.player_country_id or not state.country_is_alive(country_id):
            continue
        commands.append_array(_plan_diplomacy(state, country_id))
        commands.append_array(_plan_recruitment(state, country_id))
        commands.append_array(_plan_military(state, country_id))
    return commands

func _plan_diplomacy(state, country_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if not state.diplomacy.enemies_of(country_id).is_empty():
        return result
    var country: Dictionary = state.countries[country_id]
    var aggression := int(country.get("aggression", 50))
    var own_strength := state.country_strength(country_id)
    var best_target := ""
    var best_score := -99999.0
    for target_id in state.neighboring_countries(country_id):
        if not state.country_is_alive(target_id):
            continue
        var relation := state.diplomacy.relation(country_id, target_id)
        var target_strength := max(1.0, state.country_strength(target_id))
        var strength_ratio := own_strength / target_strength
        var score := float(aggression) - float(relation) * 0.45 + strength_ratio * 18.0
        if score > best_score:
            best_score = score
            best_target = target_id
    if best_target != "" and best_score >= 85.0:
        result.append(_command("declare_war", country_id, {"target_country_id": best_target}))
    return result

func _plan_recruitment(state, country_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var country: Dictionary = state.countries[country_id]
    if int(country.treasury) < 12 or int(country.manpower) < 5:
        return result
    var candidates := state.border_provinces(country_id)
    if candidates.is_empty():
        candidates = state.owned_provinces(country_id)
    if candidates.is_empty():
        return result
    var weakest := int(candidates[0])
    for province_id in candidates:
        if int(state.armies.get(province_id, 0)) < int(state.armies.get(weakest, 0)):
            weakest = int(province_id)
    var amount := 8 if int(country.treasury) >= 24 and int(country.manpower) >= 8 else 5
    result.append(_command("recruit", country_id, {"province_id": weakest, "amount": amount}))
    return result

func _plan_military(state, country_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var enemies := state.diplomacy.enemies_of(country_id)
    if enemies.is_empty():
        return result
    var used_sources: Dictionary = {}
    for source_id in state.border_provinces(country_id):
        var source_army := int(state.armies.get(source_id, 0))
        if source_army <= 3 or used_sources.has(source_id):
            continue
        var best_target := -1
        var best_value := 999999.0
        for neighbor_id_value in state.provinces[source_id].neighbors:
            var neighbor_id := int(neighbor_id_value)
            var target_owner := String(state.provinces[neighbor_id].owner)
            if target_owner == country_id or target_owner not in enemies:
                continue
            var target_defense := state.estimated_defense(neighbor_id)
            if target_defense < best_value:
                best_value = target_defense
                best_target = neighbor_id
        if best_target != -1:
            var amount := max(1, source_army - 1)
            result.append(_command("move", country_id, {"from_id": int(source_id), "to_id": best_target, "amount": amount}))
            used_sources[source_id] = true
    return result

func _command(command_type: String, country_id: String, payload: Dictionary) -> Dictionary:
    return {
        "id": 0,
        "type": command_type,
        "country_id": country_id,
        "payload": payload
    }
