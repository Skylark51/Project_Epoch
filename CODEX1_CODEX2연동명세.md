# CODEX1–CODEX2 연동 명세

```gdscript
const WorldSession = preload("res://src/world/world_session.gd")
var world := WorldSession.new()
world.startWorld("GOG")
```

필수 조회 API:

- `getRegion(regionId)`
- `getSettlement(settlementId)`
- `getFaction(factionId)`
- `getTerrainModifier(regionId)`
- `getMovementCost(fromRegionId, toRegionId, unitType)`
- `getSupplyCapacity(regionId, factionId)`
- `getFortificationData(settlementId)`
- `getAdjacentRegions(regionId)`
- `getConnectedSupplyNetwork(factionId)`

전투·AI 변경 API:

- `changeRegionController(regionId, factionId)`
- `damageSettlement(settlementId, damage)`
- `addSiegeProgress(settlementId, factionId, amount)`

내정 UI API:

- `selectSettlements(ids)`
- `queueBuilding(settlementId, buildingId)`
- `queueBuildingForSelected(buildingId)`
- `setCityAutomation(settlementId, enabled, focus)`
- `buildConnection(fromRegionId, toRegionId, type)`
- `getBuildableSettlements(buildingId, factionId)`
- `getSortedSettlements(sortBy, descending, factionId)`
- `getNextUnprocessedSettlement(factionId)`
- `setCameraBookmark(slot, regionId, zoom)`
- `advanceTurn()`, `saveWorld()`, `loadWorld()`, `snapshot()`

Signals:

- `world_changed(snapshot)`
- `regions_changed(region_ids)`
- `settlements_changed(settlement_ids)`
- `construction_changed(settlement_ids)`
- `debug_event(entry)`

Codex 2 지도는 `snapshot.regions[*].x/y`, `controller_id`, `border_state`,
`influence_owner_id`, `terrain`을 사용해 지역·영향권 오버레이를 그릴 수 있다.
취락 아이콘은 `initial_settlement`로 `snapshot.settlements`를 참조한다.
