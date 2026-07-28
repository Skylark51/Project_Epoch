extends RefCounted

func plan(state, evaluation: Dictionary) -> Array:
	var country_id := str(evaluation.country_id)
	if not _current_wars(state, country_id).is_empty() or float(evaluation.war_exhaustion) > 20.0:
		return []
	var profile: Dictionary = state.metadata.get("ai_profiles", {}).get(str(state.countries[country_id].ai_profile), {})
	var aggression: float = float(profile.get("aggression", 0.35))
	if state.turn < 3 or state.turn % max(4, int(10.0 - aggression * 5.0)) != 0:
		return []
	var own_power: int = max(1, int(evaluation.soldiers))
	for target in evaluation.border_threats:
		if _allied(state, country_id, target):
			continue
		var enemy_power: int = _country_power(state, target)
		var relation: float = float(state.relations.get(state.pair_key(country_id, target), 0.0))
		if own_power > enemy_power * (1.25 - aggression * 0.25) and relation < 10.0:
			return [{"command_type": "declare_war", "country_id": country_id, "target_id": target, "priority": 100}]
	return []

func _current_wars(state, country_id: String) -> Array:
	return state.wars.values().filter(func(war: Dictionary) -> bool: return country_id in war.attackers or country_id in war.defenders)

func _country_power(state, country_id: String) -> int:
	var result := 0
	for army in state.armies.values():
		if str(army.owner_id) == country_id:
			result += int(army.soldiers)
	return result

func _allied(state, a: String, b: String) -> bool:
	for treaty in state.treaties:
		if str(treaty.get("type", "")) == "alliance" and a in treaty.members and b in treaty.members:
			return true
	return false
