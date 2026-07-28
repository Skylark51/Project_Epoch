extends RefCounted

func validate_recruit(state, command: Dictionary) -> Dictionary:
	var province_id := int(command.get("target_id", command.get("source_id", -1)))
	var amount := int(command.get("amount", 0))
	if amount <= 0 or not state.provinces.has(province_id):
		return {"valid": false, "reason": "Invalid recruitment target or amount"}
	if str(state.provinces[province_id].controller_id) != str(command.country_id):
		return {"valid": false, "reason": "Province not controlled"}
	var country: Dictionary = state.countries.get(command.country_id, {})
	var cost := amount * float(state.balance.military.get("recruit_cost_per_1000", 12.0)) / 1000.0
	if int(country.get("manpower", 0)) < amount or float(country.get("treasury", 0.0)) < cost:
		return {"valid": false, "reason": "Insufficient manpower or treasury"}
	return {"valid": true, "cost": cost, "province_id": province_id, "amount": amount}

func recruit(state, command: Dictionary) -> Dictionary:
	var check: Dictionary = validate_recruit(state, command)
	if not check.valid:
		return check
	var country: Dictionary = state.countries[command.country_id]
	country.manpower -= check.amount
	country.treasury -= check.cost
	var army: Dictionary = _army_at(state, check.province_id, command.country_id)
	if army.is_empty():
		var id := "army_%s_%s_%s" % [command.country_id, state.turn, state.armies.size() + 1]
		state.armies[id] = {"id": id, "army_id": id, "owner_id": command.country_id, "province_id": check.province_id,
			"soldiers": check.amount, "morale": 1.0, "organization": 1.0, "supply": 1.0,
			"movement_points": 1, "commander_bonus": 0.0}
	else:
		army.soldiers += check.amount
	return {"valid": true, "type": "recruit", "province_id": check.province_id, "amount": check.amount, "cost": check.cost}

func validate_move(state, command: Dictionary, attack: bool = false) -> Dictionary:
	var source := int(command.get("source_id", -1))
	var target := int(command.get("target_id", -1))
	if not state.provinces.has(source) or not state.provinces.has(target):
		return {"valid": false, "reason": "Province not found"}
	if target not in state.provinces[source].get("neighbors", []).map(func(value: Variant) -> int: return int(value)):
		return {"valid": false, "reason": "Provinces are not adjacent"}
	var army: Dictionary = _army_at(state, source, command.country_id)
	if army.is_empty():
		return {"valid": false, "reason": "Army not found"}
	var friendly := str(state.provinces[target].controller_id) == str(command.country_id)
	if attack == friendly:
		return {"valid": false, "reason": "Movement/attack target mismatch"}
	return {"valid": true, "army_id": army.army_id, "source_id": source, "target_id": target}

func move(state, command: Dictionary) -> Dictionary:
	var check: Dictionary = validate_move(state, command)
	if not check.valid:
		return check
	state.armies[check.army_id].province_id = check.target_id
	return {"valid": true, "type": "move", "army_id": check.army_id, "source_id": check.source_id, "target_id": check.target_id}

func _army_at(state, province_id: int, country_id: String) -> Dictionary:
	for item in state.armies.values():
		var army: Dictionary = item
		if int(army.province_id) == province_id and str(army.owner_id) == country_id:
			return army
	return {}
