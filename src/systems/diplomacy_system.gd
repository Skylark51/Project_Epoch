extends RefCounted

func validate_command(state, command: Dictionary) -> Dictionary:
	var source := str(command.country_id)
	var target := str(command.target_id)
	if source == target or not state.countries.has(source) or not state.countries.has(target):
		return {"valid": false, "reason": "외교 대상 국가가 잘못됨"}
	if not state.is_country_alive(source) or not state.is_country_alive(target):
		return {"valid": false, "reason": "멸망한 국가와 외교할 수 없음"}
	var type := str(command.command_type)
	if type == "declare_war" and are_at_war(state, source, target):
		return {"valid": false, "reason": "이미 전쟁 중"}
	if type == "form_alliance" and relation(state, source, target) < 25:
		return {"valid": false, "reason": "관계도가 부족함"}
	return {"valid": true}

func execute(state, command: Dictionary) -> Dictionary:
	var check := validate_command(state, command)
	if not check.valid:
		return check
	var source := str(command.country_id)
	var target := str(command.target_id)
	var type := str(command.command_type)
	var key: String = state.pair_key(source, target)
	if type == "declare_war":
		var war_id := "war_%s_%s_%s" % [state.turn, source, target]
		state.wars[war_id] = {"id": war_id, "attackers": [source], "defenders": [target], "score": 0.0, "start_turn": state.turn, "occupations": []}
		_remove_treaty(state, "alliance", source, target)
	elif type == "improve_relations":
		state.relations[key] = clamp(float(state.relations.get(key, 0.0)) + 10.0, -100.0, 100.0)
	elif type == "form_alliance":
		state.treaties.append({"type": "alliance", "members": [source, target], "start_turn": state.turn})
	elif type == "break_alliance":
		_remove_treaty(state, "alliance", source, target)
	elif type == "create_vassal":
		state.treaties.append({"type": "vassal", "overlord_id": source, "subject_id": target, "start_turn": state.turn})
	elif type == "release_vassal":
		_remove_treaty(state, "vassal", source, target)
	return {"valid": true, "type": type, "source_id": source, "target_id": target}

func relation(state, a: String, b: String) -> float:
	return float(state.relations.get(state.pair_key(a, b), 0.0))

func are_at_war(state, a: String, b: String) -> bool:
	for war in state.wars.values():
		if (a in war.attackers and b in war.defenders) or (b in war.attackers and a in war.defenders):
			return true
	return false

func _remove_treaty(state, type: String, a: String, b: String) -> void:
	state.treaties = state.treaties.filter(func(treaty: Dictionary) -> bool:
		if str(treaty.get("type", "")) != type:
			return true
		var participants: Array = treaty.get("members", [treaty.get("overlord_id", ""), treaty.get("subject_id", "")])
		return not (a in participants and b in participants)
	)
