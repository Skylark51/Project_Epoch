extends RefCounted

func plan(state, evaluation: Dictionary) -> Array:
	var commands := []
	var country_id := str(evaluation.country_id)
	if float(evaluation.treasury) > 100.0:
		var candidates: Array = state.owned_provinces(country_id)
		if not candidates.is_empty():
			candidates.sort_custom(func(a: int, b: int) -> bool:
				return float(state.provinces[a].economy) < float(state.provinces[b].economy)
			)
			commands.append({"command_type": "develop", "country_id": country_id, "target_id": candidates[0], "priority": 10})
	return commands
