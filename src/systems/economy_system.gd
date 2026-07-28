extends RefCounted

func process(state) -> Array:
	var logs := []
	var cfg: Dictionary = state.balance.economy
	for country_id in state.countries:
		var country: Dictionary = state.countries[country_id]
		if bool(country.get("eliminated", false)):
			continue
		var income := 0.0
		var fort_upkeep := 0.0
		for item in state.provinces.values():
			var province: Dictionary = item
			if str(province.owner_id) != country_id:
				continue
			var occupation_factor: float = 1.0 if str(province.controller_id) == country_id else float(cfg.get("occupied_income_multiplier", 0.2))
			var stability_factor := 0.5 + float(country.stability) / 200.0
			income += float(province.economy) * float(province.tax_efficiency) * float(country.tax_rate) * stability_factor * occupation_factor
			fort_upkeep += int(province.fort_level) * float(cfg.get("fort_maintenance", 0.5))
		var army_upkeep := 0.0
		for item in state.armies.values():
			var army: Dictionary = item
			if str(army.owner_id) == country_id:
				army_upkeep += float(army.soldiers) * float(cfg.get("army_maintenance_per_1000", 1.5)) / 1000.0
		var net := income - army_upkeep - fort_upkeep
		country.treasury = snappedf(float(country.treasury) + net, 0.01)
		if float(country.treasury) < 0.0:
			country.debt = float(country.get("debt", 0.0)) - float(country.treasury)
			country.treasury = 0.0
			country.stability = maxf(0.0, float(country.stability) - float(cfg.get("deficit_stability_penalty", 1.0)))
		logs.append({"type": "economy", "country_id": country_id, "income": income, "upkeep": army_upkeep + fort_upkeep, "net": net})
	return logs

func recover_manpower(state) -> Array:
	var logs := []
	var rate := float(state.balance.economy.get("manpower_recovery_rate", 0.01))
	for country_id in state.countries:
		var recovery := 0
		for item in state.provinces.values():
			var province: Dictionary = item
			if str(province.owner_id) == country_id:
				recovery += int(float(province.manpower) * rate)
		state.countries[country_id].manpower = int(state.countries[country_id].manpower) + recovery
		logs.append({"type": "manpower", "country_id": country_id, "recovered": recovery})
	return logs
