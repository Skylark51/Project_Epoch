extends RefCounted

const GameState = preload("res://src/core/game_state.gd")
const CURRENT_VERSION := 2

func save_game(state, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "세이브 파일을 열 수 없음: %s" % path}
	var payload: Dictionary = state.to_dict()
	payload.schema_version = CURRENT_VERSION
	file.store_string(JSON.stringify(payload, "\t", false))
	return {"ok": true, "path": path}

func load_game(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "세이브 파일이 없음: %s" % path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "error": "세이브 JSON이 손상됨"}
	var migrated := migrate(parsed)
	if not migrated.ok:
		return migrated
	var state := GameState.new()
	state.from_dict(migrated.data)
	return {"ok": true, "state": state, "migrated_from": migrated.migrated_from}

func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	var migrated := data.duplicate(true)
	var original := version
	if version == 0:
		migrated.schema_version = 1
		if not migrated.has("command_queue"):
			migrated.command_queue = {"commands": [], "next_id": 1}
		version = 1
	if version == 1:
		migrated.schema_version = 2
		if not migrated.has("governance_state"):
			migrated.governance_state = {}
		version = 2
	# Schema v2 remains the public save contract. These optional v2 additions
	# receive defaults so older v2 saves load without a version bump.
	if version == 2:
		if not migrated.has("notifications"):
			migrated.notifications = []
		if not migrated.has("ui_preferences"):
			migrated.ui_preferences = {}
	if version != CURRENT_VERSION:
		return {"ok": false, "error": "지원하지 않는 세이브 버전: %s" % version}
	return {"ok": true, "data": migrated, "migrated_from": original}
