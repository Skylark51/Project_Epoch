extends RefCounted

func validate(state, settlement_id: String, building_id: String) -> Dictionary:
	if not state.settlements.has(settlement_id):
		return {"ok":false,"reason":"Settlement not found"}
	if not state.buildings.has(building_id):
		return {"ok":false,"reason":"Building not found"}
	var settlement: Dictionary = state.settlements[settlement_id]
	var building: Dictionary = state.buildings[building_id]
	var region: Dictionary = state.regions[settlement.region_id]
	var terrains: Array = building.get("terrains", [])
	if not terrains.is_empty() and String(region.terrain) not in terrains:
		return {"ok":false,"reason":"Terrain requirement not met"}
	for requirement in building.get("requires", []):
		var required := String(requirement)
		if required in ["hamlet","village","township","town","city","capital"]:
			if _tier_index(settlement.tier) < _tier_index(required):
				return {"ok":false,"reason":"Settlement tier requirement not met"}
		elif required not in settlement.buildings:
			return {"ok":false,"reason":"Required building missing: %s" % required}
	var faction: Dictionary = state.factions[settlement.faction_id]
	for resource in building.cost:
		if float(faction.resources.get(resource, 0)) < float(building.cost[resource]):
			return {"ok":false,"reason":"Insufficient %s" % resource}
	var queue: Array = state.construction_queues.get(settlement_id, [])
	if queue.size() >= int(state.balance.get("queue_limit", 8)):
		return {"ok":false,"reason":"Construction queue is full"}
	return {"ok":true,"turns":int(building.turns),"cost":building.cost.duplicate(true)}

func enqueue(state, settlement_id: String, building_id: String) -> Dictionary:
	var check := validate(state, settlement_id, building_id)
	if not check.ok:
		return check
	var settlement: Dictionary = state.settlements[settlement_id]
	var faction: Dictionary = state.factions[settlement.faction_id]
	for resource in check.cost:
		faction.resources[resource] = float(faction.resources.get(resource, 0)) - float(check.cost[resource])
	var entry := {"building_id":building_id,"turns_total":check.turns,"turns_remaining":check.turns,"status":"queued"}
	state.construction_queues[settlement_id].append(entry)
	state.log_event("construction","Building queued",{"settlement_id":settlement_id,"building_id":building_id})
	return {"ok":true,"entry":entry.duplicate(true)}

func enqueue_batch(state, settlement_ids: Array, building_id: String) -> Dictionary:
	var accepted := []
	var rejected := []
	for value in settlement_ids:
		var settlement_id := String(value)
		var result := enqueue(state, settlement_id, building_id)
		if result.ok:
			accepted.append(settlement_id)
		else:
			rejected.append({"settlement_id":settlement_id,"reason":result.reason})
	return {"ok":not accepted.is_empty(),"accepted":accepted,"rejected":rejected}

func process_turn(state) -> Array:
	var completed := []
	for settlement_id in state.construction_queues:
		var queue: Array = state.construction_queues[settlement_id]
		if queue.is_empty():
			continue
		var entry: Dictionary = queue[0]
		entry.status = "building"
		entry.turns_remaining = int(entry.turns_remaining) - 1
		if int(entry.turns_remaining) <= 0:
			state.settlements[settlement_id].buildings.append(String(entry.building_id))
			completed.append({"settlement_id":settlement_id,"building_id":entry.building_id})
			queue.pop_front()
	return completed

func _tier_index(tier: String) -> int:
	return ["hamlet","village","township","town","city","capital"].find(tier)
