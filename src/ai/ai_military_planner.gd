extends RefCounted

func plan(state, evaluation: Dictionary) -> Array:
	var commands := []
	var country_id := str(evaluation.country_id)
	var provinces: Array = state.controlled_provinces(country_id)
	if int(evaluation.manpower) >= 200 and float(evaluation.treasury) >= 10.0 and not provinces.is_empty():
		commands.append({"command_type": "recruit", "country_id": country_id, "target_id": provinces[0], "amount": 200, "priority": 20})
	var war_target := _war_target(state, country_id)
	for item in state.armies.values():
		var army: Dictionary = item
		if str(army.owner_id) != country_id:
			continue
		var source := int(army.province_id)
		for neighbor_value in state.provinces[source].neighbors:
			var target := int(neighbor_value)
			if not war_target.is_empty() and str(state.provinces[target].controller_id) == war_target:
				commands.append({"command_type": "attack", "country_id": country_id, "source_id": source, "target_id": target, "priority": 30})
				return commands
		for neighbor_value in state.provinces[source].neighbors:
			var target := int(neighbor_value)
			if str(state.provinces[target].controller_id) == country_id:
				commands.append({"command_type": "move", "country_id": country_id, "source_id": source, "target_id": target, "priority": 5})
				return commands
	return commands

func _war_target(state, country_id: String) -> String:
	for item in state.wars.values():
		var war: Dictionary = item
		if country_id in war.attackers:
			return str(war.defenders[0])
		if country_id in war.defenders:
			return str(war.attackers[0])
	return ""
