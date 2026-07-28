extends RefCounted

func change_tax(state, command: Dictionary) -> Dictionary:
	if not state.countries.has(command.country_id):
		return {"valid": false, "reason": "Country not found"}
	var rate := float(command.get("amount", command.get("payload", {}).get("tax_rate", -1.0)))
	if rate < 0.0 or rate > 0.6:
		return {"valid": false, "reason": "Tax rate must be between 0 and 0.6"}
	state.countries[command.country_id].tax_rate = rate
	return {"valid": true, "type": "change_tax", "country_id": command.country_id, "tax_rate": rate}

func eliminate_defeated(state) -> Array:
	var logs := []
	for country_id in state.countries:
		var country: Dictionary = state.countries[country_id]
		var alive: bool = state.is_country_alive(country_id)
		if not alive and not bool(country.get("eliminated", false)):
			country.eliminated = true
			logs.append({"type": "country_eliminated", "country_id": country_id})
	return logs
