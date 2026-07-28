extends RefCounted

func evaluate(state, country_id: String) -> Dictionary:
	var soldiers := 0
	for army in state.armies.values():
		if str(army.owner_id) == country_id:
			soldiers += int(army.soldiers)
	var border_threats := []
	for province_id in state.owned_provinces(country_id):
		for neighbor in state.provinces[province_id].neighbors:
			var other := str(state.provinces[int(neighbor)].owner_id)
			if other != country_id and other not in border_threats:
				border_threats.append(other)
	var country: Dictionary = state.countries[country_id]
	return {"country_id": country_id, "soldiers": soldiers, "treasury": float(country.treasury),
		"manpower": int(country.manpower), "stability": float(country.stability),
		"war_exhaustion": float(country.war_exhaustion), "border_threats": border_threats,
		"province_count": state.owned_provinces(country_id).size()}
