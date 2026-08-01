class_name BattlefieldUnitFormation
extends RefCounted

## Stable, data-driven formation slots for the small representative soldiers
## shown on the strategic map. The formation is intentionally independent from
## the map renderer so unit art can be replaced without changing map code.

const MIN_REPRESENTATIVES := 6
const MAX_REPRESENTATIVES := 16
const DEFAULT_ARCHER_OWNERS := ["northern_china_frontier", "yamato", "tsukushi_confederacy", "kibi_league"]


static func representative_count(soldiers: int) -> int:
	if soldiers <= 0:
		return 0
	return clampi(6 + roundi(sqrt(float(soldiers) / 42.0)), MIN_REPRESENTATIVES, MAX_REPRESENTATIVES)


static func visual_type_for_group(group: Dictionary) -> String:
	var requested := String(group.get("visual_type", ""))
	if requested == "infantry" or requested == "archer":
		return requested
	var infantry_strength := 0
	var archer_strength := 0
	for value in group.get("units", []):
		if value is not Dictionary:
			continue
		var unit: Dictionary = value
		var unit_id := String(unit.get("unit_id", ""))
		var category := String(unit.get("category", ""))
		var strength := maxi(1, int(unit.get("strength", unit.get("soldiers", 0))))
		if "archer" in unit_id or category == "ranged":
			archer_strength += strength
		else:
			infantry_strength += strength
	if archer_strength == 0 and infantry_strength == 0:
		return "archer" if String(group.get("owner_id", "")) in DEFAULT_ARCHER_OWNERS else "infantry"
	return "archer" if archer_strength > infantry_strength else "infantry"


static func make_slots(group: Dictionary, world_scale: float) -> Array[Dictionary]:
	var count := representative_count(int(group.get("soldiers", 0)))
	if count == 0:
		return []
	var visual_type := visual_type_for_group(group)
	var columns := clampi(ceili(float(count) / 3.0), 3, 5)
	var rows := ceili(float(count) / float(columns))
	var spacing_x := (10.4 if visual_type == "archer" else 8.8) * world_scale
	var spacing_y := 8.6 * world_scale
	var seed := String(group.get("id", group.get("army_id", "formation")))
	var slots: Array[Dictionary] = []
	for index in range(count):
		var column := index % columns
		var row := index / columns
		var base_offset := Vector2(
			(float(column) - float(columns - 1) * 0.5) * spacing_x,
			(float(row) - float(rows - 1) * 0.5) * spacing_y
		)
		var jitter := Vector2(
			(_stable_fraction("%s:x:%d" % [seed, index]) - 0.5) * spacing_x * 0.24,
			(_stable_fraction("%s:y:%d" % [seed, index]) - 0.5) * spacing_y * 0.18
		)
		slots.append({
			"offset": base_offset + jitter,
			"rank": row,
			"slot": index,
			"visual_type": visual_type,
			"facing": int(group.get("facing", -1))
		})
	return slots


static func _stable_fraction(key: String) -> float:
	return float(abs(hash(key)) % 10000) / 9999.0
