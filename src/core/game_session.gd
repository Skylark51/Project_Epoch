extends RefCounted

const GameState = preload("res://src/core/game_state.gd")
const GameEvents = preload("res://src/core/game_events.gd")
const Command = preload("res://src/core/command.gd")
const CommandQueue = preload("res://src/core/command_queue.gd")
const TurnProcessor = preload("res://src/core/turn_processor.gd")
const ScenarioSystem = preload("res://src/systems/scenario_system.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const ProvincialGovernance = preload("res://src/core/provincial_governance.gd")
const TurnEndValidator = preload("res://src/core/turn_end_validator.gd")
const NotificationCenter = preload("res://src/core/epoch_notification_center.gd")

var state
var events := GameEvents.new()
var queue := CommandQueue.new()
var processor := TurnProcessor.new()
var scenarios := ScenarioSystem.new()
var saves := SaveManager.new()
var provincial_governance := ProvincialGovernance.new()
var turn_end_validator := TurnEndValidator.new()

func start_scenario(path: String = "res://data/scenarios/prototype_east_asia.json", player_country_id: String = "") -> Dictionary:
	var loaded := scenarios.load_scenario(path, player_country_id)
	if not loaded.ok:
		return loaded
	state = GameState.new()
	state.from_dict(loaded.state)
	provincial_governance.initialize_state(state)
	queue.restore(state.command_queue)
	events.scenario_started.emit(get_public_snapshot())
	return {"ok": true, "snapshot": get_public_snapshot(), "warnings": loaded.get("warnings", [])}

func submit_command(command_type: String, values: Dictionary = {}) -> Dictionary:
	if state == null:
		return {"valid": false, "reason": "시나리오가 시작되지 않음"}
	var country_id := str(values.get("country_id", state.player_country_id))
	var command := Command.create(command_type, country_id, values)
	var result := processor.validate_command(state, command)
	if not result.valid:
		events.command_rejected.emit({"command": command, "reason": result.reason})
		return result
	var submitted := queue.submit(command, state.turn)
	state.command_queue = queue.to_dict()
	events.command_queued.emit(submitted.command)
	return submitted

func end_turn(force: bool = false) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "시나리오가 시작되지 않음"}
	var review := turn_end_validation()
	if not force and not review.get("blocking", []).is_empty():
		return {"ok": false, "reason": "턴 종료를 차단하는 항목이 있음", "validation": review}
	var result := processor.process_turn(state, queue)
	for phase in result.phases:
		events.turn_phase_completed.emit(phase.phase, phase.entries)
	events.turn_completed.emit(result)
	return {"ok": true, "result": result, "snapshot": get_public_snapshot(), "validation": review}

func save(path: String = "user://autosave.json") -> Dictionary:
	state.command_queue = queue.to_dict()
	var result := saves.save_game(state, path)
	if result.ok:
		events.save_completed.emit(path)
	return result

func load(path: String = "user://autosave.json") -> Dictionary:
	var result := saves.load_game(path)
	if not result.ok:
		return result
	state = result.state
	provincial_governance.initialize_state(state)
	queue.restore(state.command_queue)
	events.load_completed.emit(path)
	return {"ok": true, "snapshot": get_public_snapshot(), "migrated_from": result.migrated_from}
func turn_end_validation(ui_preferences_dirty: bool = false) -> Dictionary:
	if state == null:
		return turn_end_validator.evaluate(null, [], processor, ui_preferences_dirty)
	return turn_end_validator.evaluate(
		state,
		queue.peek(),
		processor,
		ui_preferences_dirty
	)
func update_ui_preferences(patch: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "시나리오가 시작되지 않음"}
	state.ui_preferences = _merge_preferences(state.ui_preferences, patch)
	return {"ok": true, "preferences": state.ui_preferences.duplicate(true)}
func mark_notification_read(notification_id: int) -> bool:
	if state == null:
		return false
	return NotificationCenter.mark_read(state, notification_id)
func governance_options(country_id: String) -> Array:
	if state == null:
		return []
	var target_country_id := country_id if not country_id.is_empty() else str(state.player_country_id)
	return provincial_governance.allowed_levels(state, target_country_id)
func _merge_preferences(base: Dictionary, patch: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key_value in patch.keys():
		var key := String(key_value)
		if patch[key_value] is Dictionary and result.get(key, null) is Dictionary:
			result[key] = _merge_preferences(result[key], patch[key_value])
		else:
			result[key] = patch[key_value]
	return result

func get_public_snapshot() -> Dictionary:
	if state == null:
		return {}
	return state.to_dict()
