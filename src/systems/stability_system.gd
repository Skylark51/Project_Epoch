extends RefCounted

func process(state) -> Array:
	var logs := []
	for country_id in state.countries:
		var country: Dictionary = state.countries[country_id]
		var at_war := false
		for item in state.wars.values():
			var war: Dictionary = item
			if country_id in war.get("attackers", []) or country_id in war.get("defenders", []):
				at_war = true
				break
		if at_war:
			country.war_exhaustion = minf(100.0, float(country.war_exhaustion) + 0.5)
		else:
			country.war_exhaustion = maxf(0.0, float(country.war_exhaustion) - 0.75)
		country.stability = clampf(float(country.stability) - float(country.war_exhaustion) * 0.002, 0.0, 100.0)
		logs.append({"type": "stability", "country_id": country_id, "stability": country.stability, "war_exhaustion": country.war_exhaustion})
	for item in state.provinces.values():
		var province: Dictionary = item
		var owner: Dictionary = state.countries.get(str(province.owner_id), {})
		var tax_pressure: float = maxf(0.0, float(owner.get("tax_rate", 0.25)) - 0.3) * 20.0
		province.unrest = clampf(float(province.unrest) + tax_pressure + float(owner.get("war_exhaustion", 0.0)) * 0.01 - 0.25, 0.0, 100.0)
	return logs
