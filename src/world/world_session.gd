extends RefCounted

const DataLoader = preload("res://src/world/world_data_loader.gd")
const WorldState = preload("res://src/world/world_state.gd")
const TerrainSystem = preload("res://src/world/terrain_system.gd")
const NetworkSystem = preload("res://src/world/network_system.gd")
const InfluenceSystem = preload("res://src/world/influence_system.gd")
const ConstructionSystem = preload("res://src/world/construction_system.gd")
const SettlementSystem = preload("res://src/world/settlement_system.gd")
const SaveManager = preload("res://src/world/world_save_manager.gd")

signal world_changed(snapshot: Dictionary)
signal regions_changed(region_ids: Array)
signal settlements_changed(settlement_ids: Array)
signal construction_changed(settlement_ids: Array)
signal debug_event(entry: Dictionary)

var state
var terrain := TerrainSystem.new()
var network := NetworkSystem.new()
var influence := InfluenceSystem.new()
var construction := ConstructionSystem.new()
var settlement := SettlementSystem.new()
var saves := SaveManager.new()
var selected_settlement_ids: Array[String] = []

func startWorld(player_faction_id: String = "GOG") -> Dictionary:
	var loaded := DataLoader.new().load_catalog()
	if not loaded.ok:
		return loaded
	if player_faction_id not in loaded.catalog.factions.factions.map(func(item: Dictionary) -> String: return String(item.faction_id)):
		return {"ok":false,"errors":["Unknown faction: %s" % player_faction_id]}
	state = WorldState.new()
	state.initialize(loaded.catalog, player_faction_id)
	var changes := influence.recalculate(state)
	world_changed.emit(snapshot())
	return {"ok":true,"snapshot":snapshot(),"influence_changes":changes,"warnings":loaded.warnings}

func advanceTurn() -> Dictionary:
	if state == null:
		return {"ok":false,"reason":"World not started"}
	var auto_plans := settlement.plan_automation(state, construction)
	var completed := construction.process_turn(state)
	var growth := settlement.process_turn(state)
	var border_changes := influence.recalculate(state)
	state.turn += 1
	state.date.month = int(state.date.month) + int(state.balance.get("turn_months", 3))
	while int(state.date.month) > 12:
		state.date.month = int(state.date.month) - 12
		state.date.year = int(state.date.year) + 1
	var result := {"ok":true,"turn":state.turn,"date":state.date.duplicate(true),"automation":auto_plans,
		"construction_completed":completed,"settlement_growth":growth,"border_changes":border_changes}
	world_changed.emit(snapshot())
	if not completed.is_empty():
		construction_changed.emit(completed.map(func(item: Dictionary) -> String: return String(item.settlement_id)))
	return result

func getRegion(regionId: String) -> Dictionary:
	return state.regions.get(regionId, {}).duplicate(true) if state != null else {}

func getSettlement(settlementId: String) -> Dictionary:
	return state.settlements.get(settlementId, {}).duplicate(true) if state != null else {}

func getFaction(factionId: String) -> Dictionary:
	return state.factions.get(factionId, {}).duplicate(true) if state != null else {}

func getTerrainModifier(regionId: String) -> Dictionary:
	return terrain.get_modifier(state, regionId) if state != null else {}

func getMovementCost(fromRegionId: String, toRegionId: String, unitType: String = "land") -> float:
	return terrain.movement_cost(state, fromRegionId, toRegionId, unitType) if state != null else INF

func getSupplyCapacity(regionId: String, factionId: String) -> int:
	return network.supply_capacity(state, regionId, factionId) if state != null else 0

func getFortificationData(settlementId: String) -> Dictionary:
	return settlement.fortification_data(state, settlementId) if state != null else {}

func changeRegionController(regionId: String, factionId: String) -> Dictionary:
	if state == null or not state.regions.has(regionId) or not state.factions.has(factionId):
		return {"ok":false,"reason":"Region or faction not found"}
	var previous := String(state.regions[regionId].controller_id)
	state.regions[regionId].controller_id = factionId
	state.regions[regionId].influence_owner_id = factionId
	for item in state.settlements.values():
		var settlement_item: Dictionary = item
		if String(settlement_item.region_id) == regionId:
			settlement_item.faction_id = factionId
	state.log_event("control","Region controller changed",{"region_id":regionId,"from":previous,"to":factionId})
	regions_changed.emit([regionId])
	return {"ok":true,"from":previous,"to":factionId}

func damageSettlement(settlementId: String, damage: float) -> Dictionary:
	var result := settlement.damage(state, settlementId, damage)
	if result.ok:
		settlements_changed.emit([settlementId])
	return result

func addSiegeProgress(settlementId: String, factionId: String, amount: float) -> Dictionary:
	var result := settlement.add_siege_progress(state, settlementId, factionId, amount)
	if result.ok:
		settlements_changed.emit([settlementId])
	return result

func getAdjacentRegions(regionId: String) -> Array:
	return state.regions.get(regionId, {}).get("adjacent_region_ids", []).duplicate() if state != null else []

func getConnectedSupplyNetwork(factionId: String) -> Array[String]:
	return network.connected_supply_network(state, factionId) if state != null else []

func selectSettlements(ids: Array) -> Dictionary:
	selected_settlement_ids.clear()
	var missing := []
	for value in ids:
		var id := String(value)
		if state.settlements.has(id):
			selected_settlement_ids.append(id)
		else:
			missing.append(id)
	return {"ok":missing.is_empty(),"selected":selected_settlement_ids.duplicate(),"missing":missing}

func queueBuilding(settlementId: String, buildingId: String) -> Dictionary:
	var result := construction.enqueue(state, settlementId, buildingId)
	if result.ok:
		construction_changed.emit([settlementId])
	return result

func queueBuildingForSelected(buildingId: String) -> Dictionary:
	var result := construction.enqueue_batch(state, selected_settlement_ids, buildingId)
	if result.ok:
		construction_changed.emit(result.accepted)
	return result

func setCityAutomation(settlementId: String, enabled: bool, focus: String = "balanced") -> Dictionary:
	return settlement.set_auto_management(state, settlementId, enabled, focus)

func buildConnection(fromRegionId: String, toRegionId: String, type: String = "road") -> Dictionary:
	var result := network.add_connection(state, fromRegionId, toRegionId, type)
	if result.ok:
		influence.recalculate(state)
		regions_changed.emit([fromRegionId, toRegionId])
	return result

func getBuildableSettlements(buildingId: String, factionId: String = "") -> Array:
	var result := []
	for settlement_id in state.settlements:
		var item: Dictionary = state.settlements[settlement_id]
		if not factionId.is_empty() and String(item.faction_id) != factionId:
			continue
		var check := construction.validate(state, String(settlement_id), buildingId)
		if check.ok:
			result.append(String(settlement_id))
	return result

func getSortedSettlements(sortBy: String = "population", descending: bool = true, factionId: String = "") -> Array:
	var result := []
	for item in state.settlements.values():
		var settlement_item: Dictionary = item
		if factionId.is_empty() or String(settlement_item.faction_id) == factionId:
			result.append(settlement_item.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: Variant = a.resources.get(sortBy, a.get(sortBy, 0))
		var bv: Variant = b.resources.get(sortBy, b.get(sortBy, 0))
		return av > bv if descending else av < bv
	)
	return result

func setCameraBookmark(slot: String, regionId: String, zoom: float = 1.0) -> Dictionary:
	if not state.regions.has(regionId):
		return {"ok":false,"reason":"Region not found"}
	state.camera_bookmarks[slot] = {"region_id":regionId,"zoom":zoom}
	return {"ok":true}

func getNextUnprocessedSettlement(factionId: String = "") -> Dictionary:
	for settlement_id in state.settlements:
		var item: Dictionary = state.settlements[settlement_id]
		if not factionId.is_empty() and String(item.faction_id) != factionId:
			continue
		if state.construction_queues[settlement_id].is_empty() and not bool(state.automation[settlement_id].enabled):
			return item.duplicate(true)
	return {}

func saveWorld(path: String = "user://epoch_world_v2.json") -> Dictionary:
	return saves.save(state, path)

func loadWorld(path: String = "user://epoch_world_v2.json") -> Dictionary:
	var result := saves.load(path)
	if result.ok:
		state = result.state
		world_changed.emit(snapshot())
	return result

func snapshot() -> Dictionary:
	return state.to_dict() if state != null else {}
