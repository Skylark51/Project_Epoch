extends RefCounted

const WorldState = preload("res://src/world/world_state.gd")
const CURRENT_VERSION := 2

func save(state, path: String = "user://epoch_world_v2.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"Cannot open save path"}
	var data: Dictionary = state.to_dict()
	data.save_version = CURRENT_VERSION
	file.store_string(JSON.stringify(data))
	return {"ok":true,"path":path}

func load(path: String = "user://epoch_world_v2.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"Save file not found"}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return {"ok":false,"reason":"Corrupted save data"}
	if int(data.get("save_version", -1)) != CURRENT_VERSION:
		return {"ok":false,"reason":"Incompatible save version. World saves require version 2."}
	var state := WorldState.new()
	state.from_dict(data)
	return {"ok":true,"state":state}
