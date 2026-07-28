extends SceneTree

const Session = preload("res://src/core/game_session.gd")
const Battle = preload("res://src/systems/battle_system.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var session := Session.new()
	var started := session.start_scenario()
	_assert(started.ok, "sample scenario loads")
	if not started.ok:
		_finish()
		return
	_assert(session.state.countries.size() == 3, "three sample countries")
	_assert(session.state.provinces.size() == 9, "nine sample provinces")
	_assert(_adjacency_is_symmetric(session.state), "province adjacency is symmetric")
	var invalid := session.submit_command("move", {"source_id": 1, "target_id": 9})
	_assert(not invalid.valid, "invalid non-adjacent movement rejected")
	var recruit := session.submit_command("recruit", {"target_id": 1, "amount": 100})
	_assert(recruit.valid, "valid recruitment queued")
	var turn := session.end_turn()
	_assert(turn.ok and session.state.turn == 2, "turn processing advances date")
	_test_battle_determinism()
	_test_diplomacy_and_peace()
	for index in range(20):
		var result := session.end_turn()
		_assert(result.ok, "simulation turn %d" % (index + 1))
	_assert(session.state.turn == 22, "20-turn simulation completes")
	var save_path := "user://core_test_save.json"
	var before := JSON.stringify(session.state.to_dict())
	_assert(session.save(save_path).ok, "save succeeds")
	session.state.countries.AUR.treasury = -999.0
	_assert(session.load(save_path).ok, "load succeeds")
	var after_canonical := JSON.stringify(JSON.parse_string(JSON.stringify(session.state.to_dict())))
	var before_canonical := JSON.stringify(JSON.parse_string(before))
	_assert(after_canonical == before_canonical, "save/load state equality")
	_test_ai_commands_valid(session)
	_finish()

func _test_battle_determinism() -> void:
	var a := Session.new()
	var b := Session.new()
	a.start_scenario()
	b.start_scenario()
	for session in [a, b]:
		session.submit_command("declare_war", {"target_id": "BOR"})
		session.end_turn()
		session.submit_command("attack", {"source_id": 2, "target_id": 4})
	var ra: Variant = a.end_turn().result.phases[5].entries
	var rb: Variant = b.end_turn().result.phases[5].entries
	_assert(JSON.stringify(ra) == JSON.stringify(rb), "battle is deterministic")

func _test_diplomacy_and_peace() -> void:
	var session := Session.new()
	session.start_scenario()
	_assert(session.submit_command("declare_war", {"target_id": "BOR"}).valid, "war declaration validates")
	session.end_turn()
	_assert(not session.state.wars.is_empty(), "war created")
	var war: Dictionary = session.state.wars.values()[0]
	war.score = 100.0
	var peace := session.submit_command("offer_peace", {"target_id": "BOR", "payload": {"terms": {"province_ids": [2], "reparations": 0}}})
	_assert(peace.valid, "peace offer validates")
	session.end_turn()
	_assert(session.state.wars.is_empty(), "peace ends war")

func _test_ai_commands_valid(session) -> void:
	var planned: Array = session.processor.ai.plan_all(session.state)
	for command in planned:
		var normalized: Dictionary = command.duplicate(true)
		normalized["command_id"] = "test_ai"
		normalized["turn"] = session.state.turn
		normalized["source_id"] = normalized.get("source_id", null)
		normalized["target_id"] = normalized.get("target_id", null)
		normalized["amount"] = normalized.get("amount", 0)
		normalized["payload"] = normalized.get("payload", {})
		normalized["priority"] = normalized.get("priority", 0)
		_assert(session.processor.validate_command(session.state, normalized).valid, "AI command is valid: %s" % command.command_type)

func _adjacency_is_symmetric(state) -> bool:
	for id in state.provinces:
		for neighbor in state.provinces[id].neighbors:
			if id not in state.provinces[int(neighbor)].neighbors.map(func(value: Variant) -> int: return int(value)):
				return false
	return true

func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: %s" % label)

func _finish() -> void:
	if failures.is_empty():
		print("ALL CORE TESTS PASSED")
		quit(0)
	else:
		print("CORE TEST FAILURES: ", failures)
		quit(1)

