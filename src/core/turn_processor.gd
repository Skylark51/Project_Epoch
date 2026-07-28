extends RefCounted

const ProvinceSystem = preload("res://src/systems/province_system.gd")
const CountrySystem = preload("res://src/systems/country_system.gd")
const EconomySystem = preload("res://src/systems/economy_system.gd")
const MilitarySystem = preload("res://src/systems/military_system.gd")
const BattleSystem = preload("res://src/systems/battle_system.gd")
const DiplomacySystem = preload("res://src/systems/diplomacy_system.gd")
const PeaceSystem = preload("res://src/systems/peace_system.gd")
const StabilitySystem = preload("res://src/systems/stability_system.gd")
const StrategicMilitary = preload("res://src/systems/strategic_military_system.gd")
const AIDirector = preload("res://src/ai/ai_director.gd")

var province := ProvinceSystem.new()
var country := CountrySystem.new()
var economy := EconomySystem.new()
var military := MilitarySystem.new()
var battle := BattleSystem.new()
var diplomacy := DiplomacySystem.new()
var peace := PeaceSystem.new()
var stability := StabilitySystem.new()
var strategic := StrategicMilitary.new()
var ai := AIDirector.new()

func process_turn(state, queue) -> Dictionary:
	var phases := []
	var commands: Array[Dictionary] = queue.drain()
	var valid := []
	var rejected := []
	for command in commands:
		var check := validate_command(state, command)
		if check.valid:
			valid.append(command)
		else:
			rejected.append({"command": command, "reason": check.reason})
	phases.append(_phase("command_validation", valid + rejected))
	phases.append(_phase("diplomacy", _execute_types(state, valid, ["declare_war", "improve_relations", "form_alliance", "break_alliance", "create_vassal", "release_vassal"])))
	phases.append(_phase("administration", _execute_types(state, valid, ["change_tax", "develop", "build_fort"])))
	phases.append(_phase("recruitment", _execute_types(state, valid, ["recruit"])))
	phases.append(_phase("movement", _execute_types(state, valid, ["move"])))
	phases.append(_phase("battle", _execute_types(state, valid, ["attack"])))
	phases.append(_phase("occupation", _occupation_logs(state)))
	phases.append(_phase("peace", _execute_types(state, valid, ["offer_peace"])))
	phases.append(_phase("economy", economy.process(state)))
	phases.append(_phase("manpower", economy.recover_manpower(state)))
	phases.append(_phase("growth", province.apply_growth(state)))
	phases.append(_phase("stability", stability.process(state)))
	phases.append(_phase("collapse", country.eliminate_defeated(state)))
	phases.append(_phase("events", _process_events(state)))
	var ai_commands := ai.plan_all(state)
	var ai_logs := []
	for command in ai_commands:
		var submitted: Dictionary = queue.submit(command, state.turn + 1)
		ai_logs.append(submitted)
	phases.append(_phase("ai_planning", ai_logs))
	_advance_date(state)
	phases.append(_phase("date", [{"turn": state.turn, "date": state.date.duplicate(true)}]))
	phases.append(_phase("autosave", [{"requested": true, "turn": state.turn}]))
	state.command_queue = queue.to_dict()
	return {"turn": state.turn, "date": state.date.duplicate(true), "phases": phases, "rejected": rejected, "ai_commands": ai_commands}

func validate_command(state, command: Dictionary) -> Dictionary:
	var country_id := str(command.get("country_id", ""))
	if not state.is_country_alive(country_id):
		return {"valid": false, "reason": "명령 국가가 존재하지 않거나 멸망함"}
	var type := str(command.command_type)
	if type in ["declare_war", "improve_relations", "form_alliance", "break_alliance", "create_vassal", "release_vassal"]:
		return diplomacy.validate_command(state, command)
	if type == "offer_peace":
		return peace.validate_offer(state, command)
	if type == "recruit":
		return military.validate_recruit(state, command)
	if type in ["move", "attack"]:
		return military.validate_move(state, command, type == "attack")
	if type == "develop":
		return province.validate_develop(state, command)
	if type == "build_fort":
		return province.validate_develop(state, command)
	if type == "change_tax":
		var rate := float(command.get("amount", command.get("payload", {}).get("tax_rate", -1.0)))
		return {"valid": rate >= 0.0 and rate <= 0.6, "reason": "세율 범위 오류"}
	return {"valid": false, "reason": "지원하지 않는 명령"}

func _execute_types(state, commands: Array, types: Array) -> Array:
	var logs := []
	for command in commands:
		if str(command.command_type) not in types:
			continue
		var type := str(command.command_type)
		if type in ["declare_war", "improve_relations", "form_alliance", "break_alliance", "create_vassal", "release_vassal"]:
			logs.append(diplomacy.execute(state, command))
		elif type == "offer_peace":
			logs.append(peace.execute_offer(state, command))
		elif type == "recruit":
			logs.append(military.recruit(state, command))
		elif type == "move":
			logs.append(military.move(state, command))
		elif type == "attack":
			logs.append(battle.resolve_attack(state, command))
		elif type == "develop":
			logs.append(province.develop(state, command))
		elif type == "build_fort":
			logs.append(province.build_fort(state, command))
		elif type == "change_tax":
			logs.append(country.change_tax(state, command))
	return logs

func _occupation_logs(state) -> Array:
	var logs := []
	for province_id in state.provinces:
		var item: Dictionary = state.provinces[province_id]
		if str(item.owner_id) != str(item.controller_id):
			logs.append({"type": "occupied", "province_id": province_id, "owner_id": item.owner_id, "controller_id": item.controller_id})
	return logs

func _process_events(state) -> Array:
	var logs := []
	for province in state.provinces.values():
		if float(province.unrest) >= 80.0 and state.turn % 3 == 0:
			province.controller_id = province.owner_id
			province.unrest = 50.0
			logs.append({"type": "revolt", "province_id": province.id})
	return logs

func _advance_date(state) -> void:
	state.turn += 1
	state.date.month = int(state.date.month) + 1
	if int(state.date.month) > 12:
		state.date.month = 1
		state.date.year = int(state.date.year) + 1

func _phase(name: String, entries: Array) -> Dictionary:
	return {"phase": name, "entries": entries}
