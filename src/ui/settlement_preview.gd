class_name SettlementPreview
extends Control

const CITY_VISUAL_PATHS := {
	"camp":"res://assets/city_visuals/city_camp.svg",
	"survey":"res://assets/city_visuals/city_stage_survey.svg",
	"frame":"res://assets/city_visuals/city_stage_frame.svg",
	"well_storage":"res://assets/city_visuals/city_well_storage.svg",
	"farmland":"res://assets/city_visuals/city_farmland.svg",
	"palisade":"res://assets/city_visuals/city_palisade.svg",
}
var variant := "camp"
var construction_stage := 3
var view_mode := "three_quarter"
var _city_textures: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(360, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in CITY_VISUAL_PATHS:
		var path:=String(CITY_VISUAL_PATHS[key])
		if ResourceLoader.exists(path): _city_textures[key]=load(path)

func visual_asset_key() -> String:
	if construction_stage==1: return "survey"
	if construction_stage==2: return "frame"
	return variant if CITY_VISUAL_PATHS.has(variant) else "camp"
func set_variant(value: String) -> void:
	variant = value
	queue_redraw()

func set_construction_stage(value: int) -> void:
	construction_stage = clampi(value, 1, 3)
	queue_redraw()
func _draw() -> void:
	var asset_key:=visual_asset_key()
	var texture:Texture2D=_city_textures.get(asset_key)
	if texture!=null:
		var target_height:=minf(size.y-8.0,(size.x-12.0)*0.75)
		var target_size:=Vector2(target_height*4.0/3.0,target_height)
		draw_texture_rect(texture,Rect2((size-target_size)*0.5,target_size),false)
		return
	var center := size * Vector2(0.5, 0.58)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-180, 15), center + Vector2(-105, -82),
		center + Vector2(115, -82), center + Vector2(180, 15),
		center + Vector2(92, 82), center + Vector2(-112, 82),
	]), Color("#59684c"))
	draw_polyline(PackedVector2Array([
		center + Vector2(-180, 15), center + Vector2(-105, -82),
		center + Vector2(115, -82), center + Vector2(180, 15),
		center + Vector2(92, 82), center + Vector2(-112, 82),
		center + Vector2(-180, 15),
	]), Color("#9b895d"), 2.0, true)
	if construction_stage == 1:
		_draw_survey_stage(center)
	elif construction_stage == 2:
		_draw_frame_stage(center)
	else:
		match variant:
			"well_storage": _draw_well_storage(center)
			"farmland": _draw_farmland(center)
			"palisade": _draw_palisade(center)
			_: _draw_camp(center)
func _draw_hut(position: Vector2, scale_value := 1.0) -> void:
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(-20, -3) * scale_value, position + Vector2(10, 4) * scale_value,
		position + Vector2(10, 25) * scale_value, position + Vector2(-20, 18) * scale_value,
	]), Color("#9d825d"))
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(10, 4) * scale_value, position + Vector2(25, -4) * scale_value,
		position + Vector2(25, 17) * scale_value, position + Vector2(10, 25) * scale_value,
	]), Color("#735b43"))
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(-27, -3) * scale_value, position + Vector2(-2, -25) * scale_value,
		position + Vector2(28, -10) * scale_value, position + Vector2(10, 5) * scale_value,
	]), Color("#513a2b"))
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(10, 5) * scale_value, position + Vector2(28, -10) * scale_value,
		position + Vector2(33, -4) * scale_value, position + Vector2(24, 3) * scale_value,
	]), Color("#3b2d25"))
	draw_rect(Rect2(position + Vector2(-6, 8) * scale_value, Vector2(8, 13) * scale_value), Color("#2d2924"), true)

func _draw_survey_stage(center: Vector2) -> void:
	for offset in [Vector2(-115,-42),Vector2(105,-38),Vector2(-96,58),Vector2(92,55)]:
		draw_line(center+offset,center+offset+Vector2(0,-25),Color("#d1b77d"),3.0)
		draw_line(center+offset+Vector2(-6,-18),center+offset+Vector2(7,-18),Color("#d1b77d"),2.0)
	for x in [-52.0,-18.0,16.0,50.0]: draw_rect(Rect2(center+Vector2(x,18),Vector2(24,14)),Color("#8d7049"),true)
	for index in range(5): draw_line(center+Vector2(-80+index*40,-20),center+Vector2(-60+index*35,48),Color(0.83,0.72,0.47,0.58),1.5)
	_draw_camp(center+Vector2(0,-25))

func _draw_frame_stage(center: Vector2) -> void:
	for origin in [center+Vector2(-65,-22),center+Vector2(48,5)]:
		draw_line(origin+Vector2(-22,20),origin+Vector2(-22,-20),Color("#6f4b31"),5.0)
		draw_line(origin+Vector2(22,20),origin+Vector2(22,-20),Color("#6f4b31"),5.0)
		draw_line(origin+Vector2(-22,-20),origin+Vector2(22,-20),Color("#9a7549"),5.0)
		draw_line(origin+Vector2(-22,-20),origin+Vector2(0,-38),Color("#9a7549"),4.0)
		draw_line(origin+Vector2(22,-20),origin+Vector2(0,-38),Color("#9a7549"),4.0)
	for x in [-88.0,-44.0,0.0,44.0,88.0]: draw_line(center+Vector2(x,55),center+Vector2(x+24,35),Color("#b3955f"),4.0)
	draw_rect(Rect2(center+Vector2(-12,35),Vector2(24,17)),Color("#8d7049"),true)
func _draw_camp(center: Vector2) -> void:
	for offset in [Vector2(-58, 12), Vector2(8, -24), Vector2(66, 22)]:
		draw_colored_polygon(PackedVector2Array([
			center + offset + Vector2(-20, 15),
			center + offset + Vector2(0, -19),
			center + offset + Vector2(20, 15),
		]), Color("#b5a06d"))
	draw_circle(center + Vector2(0, 38), 7.0, Color("#d27645"))

func _draw_well_storage(center: Vector2) -> void:
	_draw_hut(center + Vector2(-75, -14), 0.9)
	_draw_hut(center + Vector2(74, -4), 1.05)
	for x in [-30.0, 8.0, 46.0]:
		draw_rect(Rect2(center + Vector2(x - 13, 34), Vector2(26, 24)), Color("#a68857"), true)
		draw_line(center + Vector2(x - 13, 40), center + Vector2(x + 13, 40), Color("#594834"), 2.0)
	var well_center := center + Vector2(0, -18)
	draw_circle(well_center, 19.0, Color("#6f6b60"))
	draw_circle(well_center, 13.0, Color("#315f72"))
	draw_arc(well_center, 19.0, 0.0, TAU, 24, Color("#c0ad7d"), 3.0)
	draw_line(well_center + Vector2(-22, -4), well_center + Vector2(-22, -32), Color("#4a3627"), 4.0)
	draw_line(well_center + Vector2(22, -4), well_center + Vector2(22, -32), Color("#4a3627"), 4.0)
	draw_line(well_center + Vector2(-22, -30), well_center + Vector2(22, -30), Color("#4a3627"), 4.0)

func _draw_farmland(center: Vector2) -> void:
	for row in range(5):
		var y := -55.0 + float(row) * 22.0
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-148, y),
			center + Vector2(-45, y - 8),
			center + Vector2(-45, y + 5),
			center + Vector2(-148, y + 14),
		]), Color("#889253") if row % 2 == 0 else Color("#b49a54"))
	for row in range(4):
		var y := -42.0 + float(row) * 27.0
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(45, y - 6),
			center + Vector2(145, y + 2),
			center + Vector2(145, y + 16),
			center + Vector2(45, y + 8),
		]), Color("#788b4d") if row % 2 == 0 else Color("#a98f49"))
	_draw_hut(center + Vector2(0, -5), 1.05)
	draw_line(center + Vector2(-42, 52), center + Vector2(48, 52), Color("#396f85"), 5.0)

func _draw_palisade(center: Vector2) -> void:
	var wall := PackedVector2Array([
		center + Vector2(-120, 42), center + Vector2(-86, -55),
		center + Vector2(82, -55), center + Vector2(122, 40),
		center + Vector2(70, 68), center + Vector2(-72, 68),
		center + Vector2(-120, 42),
	])
	draw_polyline(wall, Color("#4a3022"), 13.0, true)
	draw_polyline(wall, Color("#a17b4d"), 7.0, true)
	for offset in [Vector2(-95, -40), Vector2(92, -38)]:
		draw_rect(Rect2(center + offset + Vector2(-12, -24), Vector2(24, 42)), Color("#6e4b31"), true)
		draw_colored_polygon(PackedVector2Array([
			center + offset + Vector2(-17, -24),
			center + offset + Vector2(0, -39),
			center + offset + Vector2(17, -24),
		]), Color("#3f2e27"))
	_draw_hut(center + Vector2(-28, -3), 0.8)
	_draw_hut(center + Vector2(42, 12), 0.72)
	draw_rect(Rect2(center + Vector2(-14, 49), Vector2(28, 20)), Color("#262321"), true)
