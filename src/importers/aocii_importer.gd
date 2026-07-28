extends RefCounted

## Local-only structural importer. It never bundles or redistributes source assets.
func inspect_archive(source_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var error := reader.open(source_path)
	if error != OK:
		return {"ok": false, "error": "Archive is not a readable ZIP/EGG file", "code": error}
	var files := reader.get_files()
	var groups := {"countries": [], "provinces": [], "scenarios": [], "diplomacy": [],
		"governments": [], "ai": [], "events": [], "translations": [], "saves": [], "other": []}
	for path in files:
		groups[_classify(path)].append(path)
	reader.close()
	return {"ok": true, "source_path": source_path, "file_count": files.size(), "groups": groups}

func convert_records(records: Dictionary) -> Dictionary:
	var countries := []
	for source in records.get("countries", []):
		countries.append({
			"id": str(source.get("id", source.get("tag", ""))).to_upper(),
			"name": str(source.get("name", "Unknown")),
			"color": str(source.get("color", "#808080")),
			"capital_province_id": int(source.get("capital_province_id", source.get("capital", -1))),
			"government_id": str(source.get("government_id", "monarchy")),
			"treasury": float(source.get("treasury", 100.0)),
			"manpower": int(source.get("manpower", 1000)),
			"stability": float(source.get("stability", 60.0)),
			"war_exhaustion": 0.0,
			"technology": source.get("technology", {"administration": 1, "economy": 1, "military": 1}),
			"tax_rate": float(source.get("tax_rate", 0.25)),
			"ai_profile": str(source.get("ai_profile", "balanced"))
		})
	var provinces := []
	for source in records.get("provinces", []):
		provinces.append({
			"id": int(source.get("id", -1)), "name": str(source.get("name", "Province")),
			"owner_id": str(source.get("owner_id", source.get("owner", ""))),
			"controller_id": str(source.get("controller_id", source.get("owner", ""))),
			"population": int(source.get("population", 10000)), "economy": float(source.get("economy", 10.0)),
			"development": int(source.get("development", 1)), "tax_efficiency": float(source.get("tax_efficiency", 0.6)),
			"manpower": int(source.get("manpower", 500)), "terrain": str(source.get("terrain", "plains")),
			"fort_level": int(source.get("fort_level", 0)), "unrest": float(source.get("unrest", 0.0)),
			"army": int(source.get("army", 0)), "neighbors": source.get("neighbors", []),
			"capital": bool(source.get("capital", false)), "coastal": bool(source.get("coastal", false))
		})
	return {"schema_version": 1, "countries": countries, "provinces": provinces,
		"conversion_note": "Fields were normalized; no source assets are embedded."}

func _classify(path: String) -> String:
	var lower := path.to_lower()
	for key in ["countries", "provinces", "scenarios", "diplomacy", "governments", "events", "translations", "saves"]:
		if key.trim_suffix("s") in lower:
			return key
	if "ai" in lower:
		return "ai"
	return "other"
