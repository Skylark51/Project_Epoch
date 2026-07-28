extends RefCounted

func validate_develop(state, command: Dictionary) -> Dictionary:
	var id := int(command.get("target_id", command.get("source_id", -1)))
	if not state.provinces.has(id):
		return {"valid": false, "reason": "Province not found"}
	if str(state.provinces[id].owner_id) != str(command.country_id):
		return {"valid": false, "reason": "Province not owned"}
	var cost := float(state.balance.economy.get("development_cost_base", 40.0))
	if float(state.countries[command.country_id].treasury) < cost:
		return {"valid": false, "reason": "Insufficient treasury"}
	return {"valid": true, "cost": cost}

func develop(state, command: Dictionary) -> Dictionary:
	var check: Dictionary = validate_develop(state, command)
	if not check.valid:
		return check
	var id := int(command.get("target_id", command.get("source_id", -1)))
	state.countries[command.country_id].treasury -= check.cost
	state.provinces[id].development = int(state.provinces[id].development) + 1
	state.provinces[id].economy = float(state.provinces[id].economy) + 2.0
	return {"valid": true, "type": "develop", "province_id": id, "cost": check.cost}

func build_fort(state, command: Dictionary) -> Dictionary:
	var id := int(command.get("target_id", command.get("source_id", -1)))
	if not state.provinces.has(id) or str(state.provinces[id].owner_id) != str(command.country_id):
		return {"valid": false, "reason": "Province not owned"}
	var cost := float(state.balance.military.get("fort_build_cost", 60.0))
	if float(state.countries[command.country_id].treasury) < cost:
		return {"valid": false, "reason": "Insufficient treasury"}
	state.countries[command.country_id].treasury -= cost
	state.provinces[id].fort_level = int(state.provinces[id].fort_level) + 1
	return {"valid": true, "type": "build_fort", "province_id": id, "cost": cost}

func apply_growth(state) -> Array:
	var rate_population := float(state.balance.economy.get("population_growth", 0.001))
	var rate_economy := float(state.balance.economy.get("economy_growth", 0.001))
	for item in state.provinces.values():
		var province: Dictionary = item
		var factor: float = maxf(0.0, 1.0 - float(province.unrest) / 100.0)
		province.population = int(float(province.population) * (1.0 + rate_population * factor))
		province.economy = snappedf(float(province.economy) * (1.0 + rate_economy * factor), 0.001)
	return [{"type": "province_growth", "count": state.provinces.size()}]
