extends RefCounted

func add_connection(state, from_id: String, to_id: String, type: String = "road", level: int = 1) -> Dictionary:
	if not state.regions.has(from_id) or not state.regions.has(to_id):
		return {"ok":false,"reason":"Region not found"}
	if to_id not in state.regions[from_id].adjacent_region_ids:
		return {"ok":false,"reason":"Regions are not adjacent"}
	var id := "%s_%s_%s" % [type, from_id, to_id]
	state.connections[id] = {"id":id,"from":from_id,"to":to_id,"type":type,"level":level}
	state.log_event("network","Connection built",state.connections[id])
	return {"ok":true,"connection":state.connections[id].duplicate(true)}

func connected_supply_network(state, faction_id: String) -> Array[String]:
	var starts: Array[String] = []
	for settlement in state.settlements.values():
		if String(settlement.faction_id) == faction_id:
			starts.append(String(settlement.region_id))
	if starts.is_empty():
		return []
	var visited := {}
	var queue: Array[String] = [starts[0]]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		for neighbor_value in state.regions[current].adjacent_region_ids:
			var neighbor := String(neighbor_value)
			if visited.has(neighbor) or String(state.regions[neighbor].controller_id) != faction_id:
				continue
			if _has_logistics_link(state, current, neighbor):
				queue.append(neighbor)
	var result: Array[String] = []
	for id in visited:
		result.append(String(id))
	return result

func supply_capacity(state, region_id: String, faction_id: String) -> int:
	if not state.regions.has(region_id):
		return 0
	if String(state.regions[region_id].controller_id) != faction_id:
		return 0
	var capacity := int(state.balance.get("supply_base", 100))
	var settlement_id: Variant = state.regions[region_id].get("initial_settlement", null)
	if settlement_id != null and state.settlements.has(String(settlement_id)):
		var settlement: Dictionary = state.settlements[String(settlement_id)]
		capacity += int(settlement.resources.get("food", 0) * 0.25)
		for building_id in settlement.buildings:
			capacity += int(state.buildings.get(String(building_id), {}).get("effects", {}).get("supply", 0))
	for item in state.connections.values():
		var connection: Dictionary = item
		if String(connection.from) == region_id or String(connection.to) == region_id:
			var bonuses: Dictionary = {"road":40,"mountain_path":20,"waterway":70,"sea_route":100,"beacon":10}
			capacity += int(bonuses.get(String(connection.type), 0)) * int(connection.get("level", 1))
	return capacity

func _has_logistics_link(state, a: String, b: String) -> bool:
	for item in state.connections.values():
		var connection: Dictionary = item
		if (String(connection.from) == a and String(connection.to) == b) or (String(connection.from) == b and String(connection.to) == a):
			return true
	return false
