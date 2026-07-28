extends RefCounted

func validate_offer(state, command: Dictionary) -> Dictionary:
	var war: Dictionary = _find_war(state, command.country_id, str(command.target_id))
	if war.is_empty():
		return {"valid": false, "reason": "양국 사이에 전쟁이 없음"}
	var terms: Dictionary = command.get("payload", {}).get("terms", {})
	var cost: float = _peace_cost(state, terms)
	var available: float = abs(float(war.get("score", 0.0)))
	if cost > available + 10.0:
		return {"valid": false, "reason": "전쟁 점수가 평화 비용보다 낮음", "cost": cost, "available": available}
	return {"valid": true, "war_id": war.id, "cost": cost}

func execute_offer(state, command: Dictionary) -> Dictionary:
	var check := validate_offer(state, command)
	if not check.valid:
		return check
	var terms: Dictionary = command.get("payload", {}).get("terms", {})
	var giver := str(command.target_id)
	var receiver := str(command.country_id)
	for value in terms.get("province_ids", []):
		var province_id := int(value)
		if state.provinces.has(province_id) and str(state.provinces[province_id].owner_id) == giver:
			state.provinces[province_id].owner_id = receiver
			state.provinces[province_id].controller_id = receiver
	var reparations: float = min(float(terms.get("reparations", 0.0)), float(state.countries[giver].treasury))
	state.countries[giver].treasury -= reparations
	state.countries[receiver].treasury += reparations
	if bool(terms.get("vassalize", false)):
		state.treaties.append({"type": "vassal", "overlord_id": receiver, "subject_id": giver, "start_turn": state.turn})
	state.treaties.append({"type": "truce", "members": [receiver, giver], "expires_turn": state.turn + int(state.balance.diplomacy.get("truce_turns", 12))})
	state.wars.erase(check.war_id)
	return {"valid": true, "type": "peace", "war_id": check.war_id, "province_ids": terms.get("province_ids", []), "reparations": reparations}

func _find_war(state, a: String, b: String) -> Dictionary:
	for war in state.wars.values():
		if (a in war.attackers and b in war.defenders) or (b in war.attackers and a in war.defenders):
			return war
	return {}

func _peace_cost(state, terms: Dictionary) -> float:
	var result := float(terms.get("reparations", 0.0)) * float(state.balance.diplomacy.get("reparation_cost_factor", 0.02))
	for value in terms.get("province_ids", []):
		var province: Dictionary = state.provinces.get(int(value), {})
		result += float(province.get("development", 0)) * float(state.balance.diplomacy.get("province_development_cost", 5.0))
	if bool(terms.get("vassalize", false)):
		result += float(state.balance.diplomacy.get("vassalization_cost", 50.0))
	return result
