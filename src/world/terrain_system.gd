extends RefCounted

func get_modifier(state, region_id: String) -> Dictionary:
	var region: Dictionary = state.regions.get(region_id, {})
	if region.is_empty():
		return {}
	return state.terrains.get(String(region.terrain), {}).duplicate(true)

func movement_cost(state, from_id: String, to_id: String, unit_type: String = "land") -> float:
	if not state.regions.has(from_id) or not state.regions.has(to_id):
		return INF
	if to_id not in state.regions[from_id].adjacent_region_ids:
		return INF
	var target: Dictionary = get_modifier(state, to_id)
	var cost := float(target.get("movement_cost", 1.0))
	if unit_type == "naval":
		if not bool(state.regions[to_id].coast):
			return INF
		cost *= 0.65
	for item in state.connections.values():
		var connection: Dictionary = item
		if _connects(connection, from_id, to_id):
			var modifiers: Dictionary = {"road":0.7,"mountain_path":0.8,"waterway":0.65,"sea_route":0.55,"beacon":1.0}
			cost *= float(modifiers.get(String(connection.type), 1.0))
	return maxf(0.2, cost)

func _connects(connection: Dictionary, a: String, b: String) -> bool:
	return (String(connection.from) == a and String(connection.to) == b) or (String(connection.from) == b and String(connection.to) == a)
