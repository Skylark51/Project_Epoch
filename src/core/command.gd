extends RefCounted

const SUPPORTED_TYPES := [
	"recruit", "move", "attack", "develop", "build_fort", "change_tax",
	"declare_war", "offer_peace", "improve_relations", "form_alliance",
	"break_alliance", "create_vassal", "release_vassal",
	"change_governance", "set_assimilation_policy"
]

static func create(command_type: String, country_id: String, values: Dictionary = {}) -> Dictionary:
	return {
		"command_id": str(values.get("command_id", "")),
		"turn": int(values.get("turn", 0)),
		"country_id": country_id,
		"command_type": command_type,
		"source_id": values.get("source_id", null),
		"target_id": values.get("target_id", null),
		"amount": float(values.get("amount", 0.0)),
		"cost": float(values.get("cost", 0.0)),
		"payload": values.get("payload", {}).duplicate(true),
		"priority": int(values.get("priority", 0))
	}

static func basic_validation(command: Dictionary) -> Dictionary:
	var missing: Array[String] = []
	for key in ["command_type", "country_id"]:
		if str(command.get(key, "")).is_empty():
			missing.append(key)
	if not str(command.get("command_type", "")) in SUPPORTED_TYPES:
		return {"valid": false, "reason": "지원하지 않는 명령", "missing": missing}
	return {"valid": missing.is_empty(), "reason": "필수 필드 누락" if not missing.is_empty() else "", "missing": missing}
