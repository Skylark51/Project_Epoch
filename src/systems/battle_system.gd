extends RefCounted

func resolve_attack(state, command: Dictionary) -> Dictionary:
	var source := int(command.source_id)
	var target := int(command.target_id)
	var attacker := _army_at(state, source, command.country_id)
	var defender_country := str(state.provinces[target].controller_id)
	var defender := _army_at(state, target, defender_country)
	if attacker.is_empty():
		return {"valid": false, "reason": "怨듦꺽援곗씠 ?놁쓬"}
	var attack_power := _power(state, attacker, false, target)
	var defense_power: float = _power(state, defender, true, target) if not defender.is_empty() else max(1.0, float(state.provinces[target].fort_level) * 100.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _battle_seed(state.random_seed, state.turn, source, target, command.command_id)
	attack_power *= rng.randf_range(0.9, 1.1)
	defense_power *= rng.randf_range(0.9, 1.1)
	var attacker_wins: bool = attack_power > defense_power
	var attacker_loss: int = min(int(attacker.soldiers), int(max(1.0, defense_power * 0.18)))
	var defender_loss := 0
	attacker.soldiers = max(0, int(attacker.soldiers) - attacker_loss)
	if not defender.is_empty():
		defender_loss = min(int(defender.soldiers), int(max(1.0, attack_power * 0.22)))
		defender.soldiers = max(0, int(defender.soldiers) - defender_loss)
	if attacker_wins and int(attacker.soldiers) > 0:
		attacker.province_id = target
		state.provinces[target].controller_id = command.country_id
	if not defender.is_empty() and int(defender.soldiers) <= 0:
		state.armies.erase(str(defender.army_id))
	if int(attacker.soldiers) <= 0:
		state.armies.erase(str(attacker.army_id))
	var result := {"valid": true, "type": "battle", "attacker_id": command.country_id,
		"defender_id": defender_country, "province_id": target, "attacker_wins": attacker_wins,
		"attacker_loss": attacker_loss, "defender_loss": defender_loss,
		"attack_power": snapped(attack_power, 0.001), "defense_power": snapped(defense_power, 0.001)}
	_update_war_score(state, result)
	return result

func _power(state, army: Dictionary, defending: bool, province_id: int) -> float:
	if army.is_empty():
		return 0.0
	var country: Dictionary = state.countries[army.owner_id]
	var tech := float(country.technology.get("military", 1))
	var terrain_id := str(state.provinces[province_id].terrain)
	var terrain_mod := float(state.balance.military.get("terrain_defense", {}).get(terrain_id, 1.0)) if defending else 1.0
	var fort_mod := 1.0 + float(state.provinces[province_id].fort_level) * float(state.balance.military.get("fort_defense_per_level", 0.15)) if defending else 1.0
	var exhaustion: float = max(0.5, 1.0 - float(country.war_exhaustion) / 200.0)
	return float(army.soldiers) * float(army.morale) * float(army.organization) * float(army.supply) * (1.0 + tech * 0.05 + float(army.commander_bonus)) * terrain_mod * fort_mod * exhaustion

func _battle_seed(base: int, turn: int, source: int, target: int, command_id: String) -> int:
	return abs(base * 1000003 + turn * 10007 + source * 503 + target * 509 + command_id.hash())

func _army_at(state, province_id: int, country_id: String) -> Dictionary:
	for army in state.armies.values():
		if int(army.province_id) == province_id and str(army.owner_id) == country_id:
			return army
	return {}

func _update_war_score(state, result: Dictionary) -> void:
	for war in state.wars.values():
		var attackers: Array = war.get("attackers", [])
		var defenders: Array = war.get("defenders", [])
		if result.attacker_id in attackers and result.defender_id in defenders:
			war.score = float(war.get("score", 0.0)) + (5.0 if result.attacker_wins else -3.0)
		elif result.attacker_id in defenders and result.defender_id in attackers:
			war.score = float(war.get("score", 0.0)) + (-5.0 if result.attacker_wins else 3.0)

