extends RefCounted

func recalculate(state) -> Array:
	var changes := []
	state.influence.clear()
	for region_id in state.regions:
		state.influence[region_id] = {}
	for settlement in state.settlements.values():
		_spread_from_settlement(state, settlement)
	var threshold := float(state.balance.get("control_threshold", 55.0))
	var contested_ratio := float(state.balance.get("contested_ratio", 0.8))
	for region_id in state.regions:
		var scores: Dictionary = state.influence[region_id]
		var ranked := []
		for faction_id in scores:
			ranked.append({"faction_id":String(faction_id),"score":float(scores[faction_id])})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
		var region: Dictionary = state.regions[region_id]
		if ranked.is_empty() or float(ranked[0].score) < threshold:
			region.border_state = "frontier"
			continue
		if ranked.size() > 1 and float(ranked[1].score) >= float(ranked[0].score) * contested_ratio:
			region.border_state = "contested"
			region.influence_owner_id = String(ranked[0].faction_id)
			continue
		var previous := String(region.controller_id)
		region.border_state = "controlled"
		region.influence_owner_id = String(ranked[0].faction_id)
		region.controller_id = String(ranked[0].faction_id)
		if previous != String(region.controller_id):
			changes.append({"region_id":region_id,"from":previous,"to":region.controller_id})
	return changes

func _spread_from_settlement(state, settlement: Dictionary) -> void:
	var faction_id := String(settlement.faction_id)
	var origin := String(settlement.region_id)
	var resources: Dictionary = settlement.resources
	var base := float(resources.get("authority", 0)) * float(state.balance.get("authority_influence_weight", 0.45))
	base += float(resources.get("population", 0)) * float(state.balance.get("population_influence_weight", 0.002))
	base += float(settlement.get("garrison", 0)) * float(state.balance.get("garrison_influence_weight", 0.015))
	base += float(settlement.get("culture_strength", 1.0)) * float(state.balance.get("culture_influence_weight", 20.0))
	_add_score(state, origin, faction_id, base)
	for neighbor_value in state.regions[origin].adjacent_region_ids:
		var neighbor := String(neighbor_value)
		var terrain: Dictionary = state.terrains.get(String(state.regions[neighbor].terrain), {})
		var terrain_factor := 1.0 / maxf(0.5, float(terrain.get("movement_cost", 1.0)))
		var road_bonus := float(state.balance.get("road_influence_bonus", 18.0)) if _connected(state, origin, neighbor) else 0.0
		_add_score(state, neighbor, faction_id, base * 0.52 * terrain_factor + road_bonus)

func _add_score(state, region_id: String, faction_id: String, amount: float) -> void:
	var scores: Dictionary = state.influence[region_id]
	scores[faction_id] = float(scores.get(faction_id, 0.0)) + amount

func _connected(state, a: String, b: String) -> bool:
	for connection in state.connections.values():
		if (String(connection.from) == a and String(connection.to) == b) or (String(connection.from) == b and String(connection.to) == a):
			return true
	return false
