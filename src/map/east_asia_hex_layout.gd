extends RefCounted

const COLUMNS := 28
const ROWS := 18
const HEX_RADIUS := 30.0
const ORIGIN := Vector2(54.0, 52.0)
const SQRT_THREE := 1.7320508075688772

const ANCHORS := {
	"qingzhou_corridor": Vector2i(5, 13),
	"liaodong_corridor": Vector2i(8, 3),
	"guknae_basin": Vector2i(11, 2),
	"pyongyang_basin": Vector2i(12, 5),
	"han_river_basin": Vector2i(13, 8),
	"yeongsan_basin": Vector2i(14, 11),
	"daegaya_basin": Vector2i(14, 9),
	"gyeongju_basin": Vector2i(16, 9),
	"aragaya_basin": Vector2i(14, 12),
	"guya_basin": Vector2i(16, 12),
	"tsukushi_plain": Vector2i(19, 13),
	"kibi_plain": Vector2i(22, 10),
	"yamato_basin": Vector2i(25, 9),
}

const ZONE_SOURCES := {
	"china": ["qingzhou_corridor", "liaodong_corridor"],
	"korea": ["guknae_basin", "pyongyang_basin", "han_river_basin", "yeongsan_basin", "daegaya_basin", "gyeongju_basin", "aragaya_basin", "guya_basin"],
	"japan": ["tsukushi_plain", "kibi_plain", "yamato_basin"],
}

const CHINA_COAST := [5, 6, 7, 8, 9, 9, 9, 10, 10, 10, 10, 10, 10, 9, 9, 8, 7, 6]

static func build(provinces: Dictionary) -> Dictionary:
	var province_by_source := {}
	for id_value in provinces.keys():
		var province: Dictionary = provinces[id_value]
		province_by_source[String(province.get("source_province_id", ""))] = int(id_value)

	var cells := {}
	for row in range(ROWS):
		for column in range(COLUMNS):
			var coordinate := Vector2i(column, row)
			var zone := _land_zone(column, row)
			var province_id := _nearest_province(zone, coordinate, province_by_source) if not zone.is_empty() else -1
			cells[_cell_key(column, row)] = {
				"column": column,
				"row": row,
				"zone": zone,
				"province_id": province_id,
				"water": zone.is_empty(),
			}

	var center_totals := {}
	var center_counts := {}
	var representative_distance := {}
	var province_polygons := {}
	var tiles: Array[Dictionary] = []
	var land_count := 0
	var water_count := 0
	for row in range(ROWS):
		for column in range(COLUMNS):
			var key := _cell_key(column, row)
			var cell: Dictionary = cells[key]
			var center := _hex_center(column, row)
			var polygon := _hex_polygon(center)
			var province_id := int(cell.province_id)
			var is_water := bool(cell.water)
			var coastal := _touches_other_type(column, row, is_water, cells)
			var terrain := _tile_terrain(column, row, province_id, coastal, provinces)
			var boundary := not is_water and _touches_other_province(column, row, province_id, cells)
			tiles.append({
				"id": key,
				"column": column,
				"row": row,
				"province_id": province_id,
				"water": is_water,
				"coastal": coastal,
				"terrain": terrain,
				"boundary": boundary,
				"polygon": polygon,
			})
			if is_water:
				water_count += 1
				continue
			land_count += 1
			center_totals[province_id] = center_totals.get(province_id, Vector2.ZERO) + center
			center_counts[province_id] = int(center_counts.get(province_id, 0)) + 1
			var source_id := String(provinces.get(province_id, {}).get("source_province_id", ""))
			var anchor: Vector2i = ANCHORS.get(source_id, Vector2i(column, row))
			var anchor_center := _hex_center(anchor.x, anchor.y)
			var distance := center.distance_squared_to(anchor_center)
			if not representative_distance.has(province_id) or distance < float(representative_distance[province_id]):
				representative_distance[province_id] = distance
				province_polygons[province_id] = polygon.duplicate(true)

	var province_centers := {}
	for province_id in center_totals.keys():
		province_centers[province_id] = center_totals[province_id] / float(center_counts[province_id])

	return {
		"tiles": tiles,
		"province_centers": province_centers,
		"province_polygons": province_polygons,
		"land_count": land_count,
		"water_count": water_count,
		"columns": COLUMNS,
		"rows": ROWS,
		"labels": [
			{"text": "중국 동부", "position": _hex_center(4, 9), "kind": "land"},
			{"text": "한반도", "position": _hex_center(14, 7), "kind": "land"},
			{"text": "황해", "position": _hex_center(11, 11), "kind": "sea"},
			{"text": "동해", "position": _hex_center(18, 6), "kind": "sea"},
			{"text": "일본 열도", "position": _hex_center(23, 13), "kind": "land"},
		],
	}

static func _land_zone(column: int, row: int) -> String:
	if column <= int(CHINA_COAST[row]):
		return "china"
	if row in [2, 3, 4] and column == 9:
		return "china"
	var korea_range := _korea_range(row)
	if korea_range.x >= 0 and column >= korea_range.x and column <= korea_range.y:
		return "korea"
	if (row == 14 and column == 13) or _is_japan(column, row):
		return "korea" if column == 13 else "japan"
	return ""

static func _korea_range(row: int) -> Vector2i:
	var ranges := {
		1: Vector2i(10, 12),
		2: Vector2i(10, 13),
		3: Vector2i(10, 13),
		4: Vector2i(11, 14),
		5: Vector2i(11, 14),
		6: Vector2i(12, 15),
		7: Vector2i(12, 15),
		8: Vector2i(13, 16),
		9: Vector2i(13, 16),
		10: Vector2i(13, 16),
		11: Vector2i(14, 16),
		12: Vector2i(14, 16),
	}
	return ranges.get(row, Vector2i(-1, -1))

static func _is_japan(column: int, row: int) -> bool:
	var kyushu_ranges := {
		11: Vector2i(18, 20), 12: Vector2i(18, 20), 13: Vector2i(18, 20),
		14: Vector2i(19, 20), 15: Vector2i(20, 20),
	}
	var honshu_ranges := {
		7: Vector2i(26, 27), 8: Vector2i(24, 27), 9: Vector2i(22, 27),
		10: Vector2i(22, 25), 11: Vector2i(22, 23),
	}
	var kyushu: Vector2i = kyushu_ranges.get(row, Vector2i(-1, -1))
	var honshu: Vector2i = honshu_ranges.get(row, Vector2i(-1, -1))
	var on_kyushu := kyushu.x >= 0 and column >= kyushu.x and column <= kyushu.y
	var on_honshu := honshu.x >= 0 and column >= honshu.x and column <= honshu.y
	var on_shikoku := row == 12 and column in [23, 24]
	return on_kyushu or on_honshu or on_shikoku

static func _nearest_province(zone: String, coordinate: Vector2i, province_by_source: Dictionary) -> int:
	var best_id := -1
	var best_distance := INF
	for source_id in ZONE_SOURCES.get(zone, []):
		if not province_by_source.has(source_id):
			continue
		var anchor: Vector2i = ANCHORS[source_id]
		var dx := float(coordinate.x - anchor.x)
		var dy := float(coordinate.y - anchor.y)
		var distance := dx * dx + dy * dy * 1.15
		if distance < best_distance:
			best_distance = distance
			best_id = int(province_by_source[source_id])
	return best_id

static func _tile_terrain(column: int, row: int, province_id: int, coastal: bool, provinces: Dictionary) -> String:
	if province_id == -1:
		return "coastal_water" if coastal else "deep_water"
	var base := String(provinces.get(province_id, {}).get("terrain", "plains"))
	if base == "hills" or (row < 5 and (column + row) % 4 == 0):
		return "hills"
	if coastal:
		return "coast"
	if (column * 7 + row * 11) % 13 <= 1:
		return "forest"
	return "plains"

static func _touches_other_type(column: int, row: int, water: bool, cells: Dictionary) -> bool:
	for neighbor in _neighbors(column, row):
		var value: Dictionary = cells.get(_cell_key(neighbor.x, neighbor.y), {})
		if not value.is_empty() and bool(value.water) != water:
			return true
	return false

static func _touches_other_province(column: int, row: int, province_id: int, cells: Dictionary) -> bool:
	for neighbor in _neighbors(column, row):
		var value: Dictionary = cells.get(_cell_key(neighbor.x, neighbor.y), {})
		if value.is_empty() or bool(value.water) or int(value.province_id) != province_id:
			return true
	return false

static func _neighbors(column: int, row: int) -> Array[Vector2i]:
	var offsets := [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1),
	] if row % 2 == 0 else [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	var result: Array[Vector2i] = []
	for offset in offsets:
		result.append(Vector2i(column, row) + offset)
	return result

static func _hex_center(column: int, row: int) -> Vector2:
	return ORIGIN + Vector2(
		HEX_RADIUS * SQRT_THREE * (float(column) + 0.5 * float(row & 1)),
		HEX_RADIUS * 1.5 * float(row)
	)

static func _hex_polygon(center: Vector2) -> Array:
	var result: Array = []
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index) - 90.0)
		result.append([center.x + HEX_RADIUS * cos(angle), center.y + HEX_RADIUS * sin(angle)])
	return result

static func _cell_key(column: int, row: int) -> String:
	return "%d:%d" % [column, row]
