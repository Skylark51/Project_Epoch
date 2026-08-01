class_name BattlefieldUnitRenderer
extends RefCounted

const Formation = preload("res://src/map/battlefield_unit_formation.gd")
const Demo = preload("res://src/map/battlefield_unit_demo.gd")

const NEUTRAL_SKIN := Color("#c99b73")
const INFANTRY_TUNIC := Color("#59604e")
const ARCHER_TUNIC := Color("#716247")
const LEATHER := Color("#332b25")
const METAL := Color("#beb8a4")
const SHADOW := Color(0.035, 0.045, 0.035, 0.28)
const FACTION_FALLBACKS := [Color("#527da8"), Color("#ae5d50"), Color("#8c7447"), Color("#6f8d70")]
const FactionAccents := {
	"goguryeo": Color("#527da8"),
	"northern_china_frontier": Color("#ae5d50"),
	"baekje": Color("#9e7652"),
	"silla": Color("#61866f")
}

var last_rendered_soldier_count := 0
var last_rendered_group_count := 0
var last_demo_used := false


func render(canvas: CanvasItem, army_groups: Array, provinces: Dictionary, countries: Dictionary, world_map, zoom: float, allow_demo: bool) -> void:
	last_rendered_soldier_count = 0
	last_rendered_group_count = 0
	last_demo_used = false
	if world_map == null:
		return
	var groups := army_groups.duplicate(true)
	if groups.is_empty() and allow_demo:
		groups = Demo.fallback_groups(provinces, world_map)
		last_demo_used = not groups.is_empty()
	var world_scale := _world_scale(zoom)
	var soldiers: Array[Dictionary] = []
	var banners: Array[Dictionary] = []
	for group_value in groups:
		if group_value is not Dictionary:
			continue
		var group: Dictionary = group_value
		var base_center := _group_position(group, provinces)
		var center := _formation_center(base_center, group, world_scale, world_map)
		if not _is_land(world_map, center):
			continue
		var accent := _faction_color(group, countries)
		var added := 0
		for slot in Formation.make_slots(group, world_scale):
			var position := center + Vector2(slot.get("offset", Vector2.ZERO))
			if not _is_land(world_map, position):
				continue
			soldiers.append({
				"position": position,
				"visual_type": String(slot.get("visual_type", "infantry")),
				"facing": int(slot.get("facing", -1)),
				"accent": accent,
				"scale": world_scale,
				"rank": int(slot.get("rank", 0))
			})
			added += 1
		if added > 0:
			last_rendered_group_count += 1
			banners.append({"position": center, "accent": accent, "scale": world_scale, "facing": int(group.get("facing", -1))})
	soldiers.sort_custom(_sort_by_depth)
	for soldier in soldiers:
		_draw_shadow(canvas, soldier)
	for soldier in soldiers:
		if String(soldier.visual_type) == "archer":
			_draw_archer(canvas, soldier)
		else:
			_draw_infantry(canvas, soldier)
		last_rendered_soldier_count += 1
	for banner in banners:
		_draw_banner(canvas, banner)


func stats() -> Dictionary:
	return {
		"soldier_count": last_rendered_soldier_count,
		"group_count": last_rendered_group_count,
		"demo_used": last_demo_used
	}


func _world_scale(zoom: float) -> float:
	var screen_scale := clampf(0.78 + zoom * 0.18, 0.78, 1.32)
	return screen_scale / maxf(zoom, 0.05)


func _group_position(group: Dictionary, provinces: Dictionary) -> Vector2:
	var direct = group.get("world_position", null)
	if direct is Vector2:
		return direct
	if direct is Array and direct.size() >= 2:
		return Vector2(float(direct[0]), float(direct[1]))
	var province: Dictionary = provinces.get(int(group.get("province_id", -1)), {})
	var center = province.get("map_center", [])
	if center is Array and center.size() >= 2:
		return Vector2(float(center[0]), float(center[1]))
	if center is Vector2:
		return center
	return Vector2.ZERO


func _formation_center(base_center: Vector2, group: Dictionary, world_scale: float, world_map) -> Vector2:
	var facing := int(group.get("facing", -1))
	var candidate := base_center + Vector2(13.0 * facing, 28.0) * world_scale
	return candidate if _is_land(world_map, candidate) else base_center


func _is_land(world_map, world_position: Vector2) -> bool:
	var tile: Vector2i = world_map.tile_at_world(world_position)
	var terrain: int = int(world_map.terrain_id(tile.x, tile.y))
	return terrain >= 3 and terrain != 12 and terrain != 13


func _faction_color(group: Dictionary, countries: Dictionary) -> Color:
	var owner_id := String(group.get("owner_id", ""))
	if FactionAccents.has(owner_id):
		return FactionAccents[owner_id]
	var country: Dictionary = countries.get(owner_id, {})
	var raw_color := String(country.get("color", ""))
	if not raw_color.is_empty() and Color.html_is_valid(raw_color):
		return Color(raw_color).darkened(0.08)
	return FACTION_FALLBACKS[abs(hash(owner_id)) % FACTION_FALLBACKS.size()]


func _sort_by_depth(left: Dictionary, right: Dictionary) -> bool:
	var left_position: Vector2 = left.get("position", Vector2.ZERO)
	var right_position: Vector2 = right.get("position", Vector2.ZERO)
	if is_equal_approx(left_position.y, right_position.y):
		return int(left.get("rank", 0)) < int(right.get("rank", 0))
	return left_position.y < right_position.y


func _draw_shadow(canvas: CanvasItem, soldier: Dictionary) -> void:
	var position: Vector2 = soldier.position
	var scale := float(soldier.scale)
	_draw_ellipse(canvas, position + Vector2(0.0, 1.0 * scale), 4.5 * scale, 1.45 * scale, SHADOW)
	_draw_ellipse(canvas, position + Vector2(0.0, 1.1 * scale), 3.1 * scale, 0.9 * scale, Color(0.02, 0.03, 0.02, 0.20))


func _draw_infantry(canvas: CanvasItem, soldier: Dictionary) -> void:
	var position: Vector2 = soldier.position
	var scale := float(soldier.scale)
	var facing := int(soldier.facing)
	var accent: Color = soldier.accent
	canvas.draw_line(position + Vector2(-1.5, -2.0) * scale, position + Vector2(-1.9, 1.4) * scale, LEATHER, 1.15 * scale, true)
	canvas.draw_line(position + Vector2(1.5, -2.0) * scale, position + Vector2(1.9, 1.4) * scale, LEATHER, 1.15 * scale, true)
	canvas.draw_rect(Rect2(position + Vector2(-2.6, -8.2) * scale, Vector2(5.2, 6.6) * scale), INFANTRY_TUNIC, true)
	canvas.draw_circle(position + Vector2(0.0, -10.1) * scale, 1.85 * scale, NEUTRAL_SKIN)
	canvas.draw_arc(position + Vector2(0.0, -10.25) * scale, 1.9 * scale, PI, TAU, 8, METAL.darkened(0.30), 0.85 * scale, true)
	var shield_center := position + Vector2(-3.0 * facing, -5.1) * scale
	canvas.draw_circle(shield_center, 2.3 * scale, accent)
	canvas.draw_arc(shield_center, 2.3 * scale, 0.0, TAU, 8, LEATHER, 0.65 * scale, true)
	var spear_base := position + Vector2(2.0 * facing, -1.0) * scale
	var spear_tip := position + Vector2(5.0 * facing, -17.0) * scale
	canvas.draw_line(spear_base, spear_tip, Color("#9d7e57"), 0.75 * scale, true)
	canvas.draw_line(spear_tip, spear_tip + Vector2(1.5 * facing, 2.8) * scale, METAL, 1.0 * scale, true)


func _draw_archer(canvas: CanvasItem, soldier: Dictionary) -> void:
	var position: Vector2 = soldier.position
	var scale := float(soldier.scale)
	var facing := int(soldier.facing)
	var accent: Color = soldier.accent
	canvas.draw_line(position + Vector2(-1.25, -1.8) * scale, position + Vector2(-1.7, 1.2) * scale, LEATHER, 1.0 * scale, true)
	canvas.draw_line(position + Vector2(1.25, -1.8) * scale, position + Vector2(1.7, 1.2) * scale, LEATHER, 1.0 * scale, true)
	canvas.draw_rect(Rect2(position + Vector2(-2.35, -7.6) * scale, Vector2(4.7, 6.0) * scale), ARCHER_TUNIC, true)
	canvas.draw_circle(position + Vector2(0.0, -9.55) * scale, 1.7 * scale, NEUTRAL_SKIN)
	canvas.draw_arc(position + Vector2(0.0, -9.65) * scale, 1.75 * scale, PI, TAU, 8, LEATHER, 0.8 * scale, true)
	var quiver := Rect2(position + Vector2(2.1 * facing, -7.2) * scale, Vector2(1.65, 4.3) * scale)
	canvas.draw_rect(quiver, accent.darkened(0.2), true)
	canvas.draw_line(position + Vector2(3.1 * facing, -3.7) * scale, position + Vector2(6.0 * facing, -10.4) * scale, Color("#a58158"), 0.8 * scale, true)
	var bow_center := position + Vector2(5.4 * facing, -7.2) * scale
	var bow_start := -1.25 if facing > 0 else PI - 1.25
	var bow_end := 1.25 if facing > 0 else PI + 1.25
	canvas.draw_arc(bow_center, 3.25 * scale, bow_start, bow_end, 10, Color("#c79c61"), 0.8 * scale, true)
	canvas.draw_line(bow_center + Vector2(0.0, -3.25) * scale, bow_center + Vector2(0.0, 3.25) * scale, Color("#ddd2b4"), 0.45 * scale, true)


func _draw_banner(canvas: CanvasItem, banner: Dictionary) -> void:
	var position: Vector2 = banner.position
	var scale := float(banner.scale)
	var facing := int(banner.facing)
	var accent: Color = banner.accent
	var pole_base := position + Vector2(-1.6 * facing, -2.0) * scale
	var pole_top := position + Vector2(-1.6 * facing, -20.5) * scale
	canvas.draw_line(pole_base, pole_top, Color("#8d704c"), 0.85 * scale, true)
	var flag := PackedVector2Array([
		pole_top,
		pole_top + Vector2(5.0 * facing, 1.4) * scale,
		pole_top + Vector2(4.0 * facing, 5.3) * scale,
		pole_top + Vector2(0.0, 4.2) * scale
	])
	canvas.draw_colored_polygon(flag, accent)
	canvas.draw_polyline(flag + PackedVector2Array([flag[0]]), LEATHER, 0.55 * scale, true)


func _draw_ellipse(canvas: CanvasItem, center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	canvas.draw_colored_polygon(points, color)
