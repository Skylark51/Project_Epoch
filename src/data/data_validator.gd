extends RefCounted

static func validate(countries: Array, provinces: Array, scenario: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var country_ids := {}
	var province_ids := {}
	var capitals := {}
	for country in countries:
		var id := str(country.get("id", ""))
		if id.is_empty() or country_ids.has(id):
			errors.append("국가 ID가 없거나 중복됨: %s" % id)
		country_ids[id] = true
		capitals[id] = 0
	for province in provinces:
		var id := int(province.get("id", -1))
		if id < 0 or province_ids.has(id):
			errors.append("Province ID가 없거나 중복됨: %s" % id)
		province_ids[id] = province
		var owner := str(province.get("owner_id", ""))
		if not country_ids.has(owner):
			errors.append("Province %s의 소유국 %s가 없음" % [id, owner])
		if bool(province.get("capital", false)):
			capitals[owner] = int(capitals.get(owner, 0)) + 1
	for id in province_ids:
		var province: Dictionary = province_ids[id]
		for neighbor_value in province.get("neighbors", []):
			var neighbor := int(neighbor_value)
			if not province_ids.has(neighbor):
				errors.append("Province %s의 인접 Province %s가 없음" % [id, neighbor])
			elif id not in province_ids[neighbor].get("neighbors", []).map(func(value: Variant) -> int: return int(value)):
				errors.append("인접 관계 비대칭: %s-%s" % [id, neighbor])
	for country_id in country_ids:
		if int(capitals.get(country_id, 0)) != 1:
			errors.append("%s의 수도 Province 수가 1이 아님" % country_id)
	if str(scenario.get("id", "")).is_empty():
		errors.append("시나리오 ID가 없음")
	return {"valid": errors.is_empty(), "errors": errors, "warnings": warnings}
