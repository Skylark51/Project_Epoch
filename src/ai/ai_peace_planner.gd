extends RefCounted

func plan(state, evaluation: Dictionary) -> Array:
	var country_id := str(evaluation.country_id)
	for war in state.wars.values():
		if country_id not in war.attackers and country_id not in war.defenders:
			continue
		var enemy := str(war.defenders[0]) if country_id in war.attackers else str(war.attackers[0])
		if float(evaluation.war_exhaustion) >= 12.0 or abs(float(war.score)) >= 20.0:
			var terms := {"province_ids": [], "reparations": 0}
			if float(war.score) > 10.0 and country_id in war.attackers:
				for province_id in state.controlled_provinces(country_id):
					if str(state.provinces[province_id].owner_id) == enemy:
						terms.province_ids = [province_id]
						break
			return [{"command_type": "offer_peace", "country_id": country_id, "target_id": enemy, "payload": {"terms": terms}, "priority": 110}]
	return []
