extends RefCounted

const Command = preload("res://src/core/command.gd")
var _commands: Array[Dictionary] = []
var _next_id := 1

func submit(command: Dictionary, turn: int) -> Dictionary:
	var result := Command.basic_validation(command)
	if not result.valid:
		return result
	var stored: Dictionary = command.duplicate(true)
	if str(stored.get("command_id", "")).is_empty():
		stored.command_id = "cmd_%06d" % _next_id
		_next_id += 1
	stored.turn = turn
	_commands.append(stored)
	return {"valid": true, "command": stored.duplicate(true)}

func drain() -> Array[Dictionary]:
	var result := _commands.duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.priority) == int(b.priority):
			return str(a.command_id) < str(b.command_id)
		return int(a.priority) > int(b.priority)
	)
	_commands.clear()
	return result

func peek() -> Array[Dictionary]:
	return _commands.duplicate(true)

func to_dict() -> Dictionary:
	return {"commands": _commands.duplicate(true), "next_id": _next_id}

func restore(data: Dictionary) -> void:
	_commands.clear()
	for item in data.get("commands", []):
		_commands.append(item.duplicate(true))
	_next_id = int(data.get("next_id", 1))
