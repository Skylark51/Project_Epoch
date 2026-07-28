extends RefCounted

func process_turn(state) -> Array:
	var logs := []
	var base_growth := float(state.balance.get("base_growth_rate", 0.012))
	var food_rate := float(state.balance.get("food_per_population", 0.018))
	for settlement_id in state.settlements:
		var settlement: Dictionary = state.settlements[settlement_id]
		var region: Dictionary = state.regions[settlement.region_id]
		var terrain: Dictionary = state.terrains[String(region.terrain)]
		var resources: Dictionary = settlement.resources
		var population := int(resources.population)
		var food_need := population * food_rate
		var production := _production(state, settlement)
		for resource in production:
			resources[resource] = float(resources.get(resource, 0.0)) + float(production[resource])
		resources.food = float(resources.food) - food_need
		var food_factor := clampf(float(resources.food) / maxf(food_need * 2.0, 1.0), 0.25, 1.25)
		var growth := base_growth * float(terrain.get("growth", 1.0)) * food_factor * (1.0 - float(settlement.damage) / 150.0)
		resources.population = maxi(100, int(population * (1.0 + growth)))
		_promote_if_ready(settlement)
		logs.append({"settlement_id":settlement_id,"population":resources.population,"production":production})
	return logs

func set_auto_management(state, settlement_id: String, enabled: bool, focus: String = "balanced") -> Dictionary:
	if not state.settlements.has(settlement_id):
		return {"ok":false,"reason":"Settlement not found"}
	state.automation[settlement_id] = {"enabled":enabled,"focus":focus,
		"reserve_ratio":state.automation.get(settlement_id, {}).get("reserve_ratio", state.balance.get("auto_manager_reserve_ratio", 0.25))}
	state.settlements[settlement_id].auto_managed = enabled
	return {"ok":true}

func plan_automation(state, construction) -> Array:
	var results := []
	for settlement_id in state.automation:
		var policy: Dictionary = state.automation[settlement_id]
		if not bool(policy.enabled) or not state.construction_queues[settlement_id].is_empty():
			continue
		var settlement: Dictionary = state.settlements[settlement_id]
		var candidates: Array[String] = _focus_candidates(String(policy.focus), settlement)
		for building_id in candidates:
			var result: Dictionary = construction.enqueue(state, settlement_id, building_id)
			if result.ok:
				results.append({"settlement_id":settlement_id,"building_id":building_id})
				break
	return results

func fortification_data(state, settlement_id: String) -> Dictionary:
	var settlement: Dictionary = state.settlements.get(settlement_id, {})
	if settlement.is_empty():
		return {}
	var fortification := 0
	var storage := 0
	var vision := 0
	for building_id in settlement.buildings:
		var effects: Dictionary = state.buildings.get(String(building_id), {}).get("effects", {})
		fortification += int(effects.get("fortification", 0))
		storage += int(effects.get("storage", 0))
		vision += int(effects.get("vision", 0))
	var linked_bonus := 0.0
	if String(settlement.settlement_type) == "mountain_fortress":
		for connection in state.connections.values():
			if String(connection.from) == String(settlement.region_id) or String(connection.to) == String(settlement.region_id):
				if String(connection.type) in ["road","mountain_path"]:
					linked_bonus = float(state.balance.get("flat_mountain_link_defense_bonus", 0.2))
					break
	return {"settlement_id":settlement_id,"type":settlement.settlement_type,"fortification":fortification,
		"food_storage":float(settlement.resources.food) + storage,"vision":vision,
		"linked_flat_fortress_bonus":linked_bonus,"damage":settlement.damage,"sieges":settlement.sieges.duplicate(true)}

func damage(state, settlement_id: String, amount: float) -> Dictionary:
	if not state.settlements.has(settlement_id):
		return {"ok":false,"reason":"Settlement not found"}
	var settlement: Dictionary = state.settlements[settlement_id]
	settlement.damage = clampf(float(settlement.damage) + maxf(0.0, amount), 0.0, float(state.balance.get("settlement_damage_max", 100.0)))
	return {"ok":true,"damage":settlement.damage}

func add_siege_progress(state, settlement_id: String, faction_id: String, amount: float) -> Dictionary:
	if not state.settlements.has(settlement_id) or not state.factions.has(faction_id):
		return {"ok":false,"reason":"Settlement or faction not found"}
	var settlement: Dictionary = state.settlements[settlement_id]
	var max_progress := float(state.balance.get("siege_progress_max", 100.0))
	settlement.sieges[faction_id] = clampf(float(settlement.sieges.get(faction_id, 0.0)) + amount, 0.0, max_progress)
	return {"ok":true,"progress":settlement.sieges[faction_id],"completed":float(settlement.sieges[faction_id]) >= max_progress}

func _production(state, settlement: Dictionary) -> Dictionary:
	var region: Dictionary = state.regions[settlement.region_id]
	var terrain: Dictionary = state.terrains[String(region.terrain)]
	var result := {"food":4.0,"wood":2.0,"stone":1.0,"iron":0.2,"wealth":2.0,"authority":0.5}
	for building_id in settlement.buildings:
		var effects: Dictionary = state.buildings.get(String(building_id), {}).get("effects", {})
		for resource in ["food","wood","stone","iron","wealth","authority"]:
			result[resource] = float(result[resource]) + float(effects.get(resource, 0.0))
	for resource in terrain.get("production", {}):
		result[resource] = float(result.get(resource, 0.0)) * float(terrain.production[resource])
	return result

func _promote_if_ready(settlement: Dictionary) -> void:
	var thresholds := {"hamlet":0,"village":1200,"township":3500,"town":9000,"city":22000,"capital":45000}
	var order := ["hamlet","village","township","town","city","capital"]
	var current := order.find(String(settlement.tier))
	for index in range(order.size() - 1, current, -1):
		if int(settlement.resources.population) >= int(thresholds[order[index]]):
			settlement.tier = order[index]
			return

func _focus_candidates(focus: String, settlement: Dictionary) -> Array[String]:
	match focus:
		"food": return ["farmland","pasture","warehouse"]
		"resources": return ["lumber_camp","quarry","iron_mine","warehouse"]
		"trade": return ["market","port","road","warehouse"]
		"defense": return ["palisade","wall","beacon","barracks","mountain_fortress"]
		"authority": return ["shrine","office","palace"]
	return ["farmland","market","warehouse","road","palisade"]
