extends SceneTree

const WorldSession = preload("res://src/world/world_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var world := WorldSession.new()
	var started := world.startWorld("GOG")
	_assert(started.ok, "world catalog loads")
	if not started.ok:
		print(started)
		_finish()
		return
	_assert(world.state.regions.size() >= 40, "east Asia map has at least 40 regions")
	_assert(world.state.factions.size() >= 12, "at least 12 factions placed")
	_assert(world.getRegion("guknaeseong").display_name == "국내성", "Korean historical name preserved")
	_assert(world.getRegion("jiankang").region_group == "south_china", "Chinese eastern region present")
	_assert(world.getRegion("yamato").region_group == "yamato", "western Japan region present")
	_assert(world.getSettlement("guknaeseong").settlement_type == "flat_city", "flat city represented")
	_assert(world.getSettlement("hwando").settlement_type == "mountain_fortress", "mountain fortress represented")
	_assert(world.getTerrainModifier("hwando").defense > world.getTerrainModifier("hanseong").defense, "terrain affects defense")
	_assert(world.getMovementCost("guknaeseong","hwando") < INF, "adjacent movement cost available")
	_assert(world.getMovementCost("guknaeseong","yamato") == INF, "non-adjacent movement rejected")
	_assert(world.getSupplyCapacity("guknaeseong","GOG") > 0, "supply capacity calculated")
	_assert(not world.getConnectedSupplyNetwork("GOG").is_empty(), "connected supply network returned")
	var fort := world.getFortificationData("hwando")
	_assert(int(fort.fortification) > 0 and float(fort.linked_flat_fortress_bonus) > 0.0, "flat city and mountain fortress link bonus")
	var selection := world.selectSettlements(["guknaeseong","hanseong"])
	_assert(selection.ok and selection.selected.size() == 2, "multi-settlement selection")
	var batch := world.queueBuildingForSelected("farmland")
	_assert(batch.accepted.size() >= 1, "batch construction queue")
	var before_population := int(world.getSettlement("guknaeseong").resources.population)
	for index in range(3):
		_assert(world.advanceTurn().ok, "world turn %d" % (index + 1))
	_assert(int(world.getSettlement("guknaeseong").resources.population) != before_population, "settlement population grows")
	_assert("farmland" in world.getSettlement("guknaeseong").buildings, "queued building completes")
	_assert(world.setCityAutomation("guknaeseong", true, "defense").ok, "city automation enabled")
	_assert(world.buildConnection("hanseong","gwanmiseong","road").ok, "road connection constructed")
	_assert(world.damageSettlement("hwando", 15).damage == 15.0, "settlement damage API")
	_assert(world.addSiegeProgress("hwando","BAE",25).progress == 25.0, "siege progress API")
	var controller := world.changeRegionController("gwanmiseong","GOG")
	_assert(controller.ok and world.getRegion("gwanmiseong").controller_id == "GOG", "controller change API")
	_assert(not world.getBuildableSettlements("market","GOG").is_empty(), "buildable settlement highlighting data")
	_assert(not world.getSortedSettlements("population",true,"GOG").is_empty(), "settlement sort/filter")
	_assert(world.setCameraBookmark("1","guknaeseong",1.5).ok, "camera bookmark")
	var save_path := "user://epoch_world_test_v2.json"
	var before := _canonical(world.snapshot())
	_assert(world.saveWorld(save_path).ok, "world save succeeds")
	world.changeRegionController("guknaeseong","BAE")
	_assert(world.loadWorld(save_path).ok, "world load succeeds")
	_assert(_canonical(world.snapshot()) == before, "world save round-trip equality")
	_finish()

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: %s" % label)

func _finish() -> void:
	if failures.is_empty():
		print("ALL WORLD SYSTEM TESTS PASSED")
		quit(0)
	else:
		print("WORLD SYSTEM FAILURES: ", failures)
		quit(1)
