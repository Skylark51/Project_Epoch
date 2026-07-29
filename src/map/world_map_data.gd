class_name WorldMapData
extends RefCounted

const MANIFEST_PATH := "res://data/maps/generated/east_asia_world_map_manifest.json"

const TERRAIN_COLORS := {
	0: Color("#143548"), 1: Color("#1c4e67"), 2: Color("#367085"),
	3: Color("#b2a670"), 4: Color("#9d9d67"), 5: Color("#6f8b55"),
	6: Color("#386747"), 7: Color("#77684c"), 8: Color("#665b52"),
	9: Color("#b79d5e"), 10: Color("#898e53"), 11: Color("#487760"),
	12: Color("#3b7b99"), 13: Color("#2f6987")
}

var manifest: Dictionary = {}
var projection := MapProjection.new()
var width := 0
var height := 0
var chunk_size := 16
var tile_size := 8.0
var terrain := PackedByteArray()
var province_layer := PackedByteArray()
var assigned_indices := PackedInt32Array()
var cities: Array = []
var province_sources: Array = []
var source_to_runtime_id: Dictionary = {}
var runtime_to_source_id: Dictionary = {}
var overview_texture: Texture2D
var _chunk_texture_cache: Dictionary = {}
var _overview_mode_cache: Dictionary = {}
var error_message := ""

func load_default() -> bool:
	manifest = _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		error_message = "Map manifest could not be loaded: %s" % MANIFEST_PATH
		push_error(error_message)
		return false
	width = int(manifest.get("width", 0))
	height = int(manifest.get("height", 0))
	chunk_size = int(manifest.get("chunk_size", 16))
	tile_size = float(manifest.get("tile_size", 8))
	province_sources = manifest.get("province_sources", []).duplicate()
	projection.configure(manifest)
	terrain = _load_bytes(String(manifest.get("terrain_file", "")))
	province_layer = _load_bytes(String(manifest.get("province_file", "")))
	assigned_indices.clear()
	for index in range(province_layer.size()):
		if int(province_layer[index]) > 0:
			assigned_indices.append(index)
	if terrain.size() != width * height or province_layer.size() != width * height:
		error_message = "Map layer size mismatch: expected %d, terrain=%d, province=%d" % [width * height, terrain.size(), province_layer.size()]
		push_error(error_message)
		return false
	var city_data := _load_json(String(manifest.get("cities_file", "")))
	cities = city_data.get("cities", []).duplicate(true)
	var overview_path := String(manifest.get("overview_file", ""))
	if ResourceLoader.exists(overview_path):
		overview_texture = load(overview_path)
	error_message = ""
	return true

func bind_runtime_provinces(provinces: Dictionary) -> void:
	source_to_runtime_id.clear()
	runtime_to_source_id.clear()
	for id_value in provinces.keys():
		var runtime_id := int(id_value)
		var source_id := String(provinces[id_value].get("source_province_id", ""))
		if not source_id.is_empty():
			source_to_runtime_id[source_id] = runtime_id
			runtime_to_source_id[runtime_id] = source_id
	_chunk_texture_cache.clear()
	_overview_mode_cache.clear()

func terrain_id(column: int, row: int) -> int:
	if not contains(column, row):
		return 0
	return int(terrain[row * width + column])

func province_id(column: int, row: int) -> int:
	if not contains(column, row):
		return -1
	var source_index := int(province_layer[row * width + column])
	if source_index <= 0 or source_index >= province_sources.size():
		return -1
	return int(source_to_runtime_id.get(String(province_sources[source_index]), -1))

func contains(column: int, row: int) -> bool:
	return column >= 0 and row >= 0 and column < width and row < height

func world_rect() -> Rect2:
	return Rect2(0.0, 0.0, float(width) * tile_size, float(height) * tile_size)

func tile_at_world(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / tile_size), floori(world_position.y / tile_size))

func tile_center(column: int, row: int) -> Vector2:
	return Vector2((float(column) + 0.5) * tile_size, (float(row) + 0.5) * tile_size)

func world_from_lonlat(longitude: float, latitude: float) -> Vector2:
	return projection.lonlat_to_tile(longitude, latitude) * tile_size

func lonlat_from_world(world_position: Vector2) -> Vector2:
	return projection.tile_to_lonlat(world_position / tile_size)

func chunk_texture(chunk_x: int, chunk_y: int, mode: String, countries: Dictionary, provinces: Dictionary, player_country_id := "", relations := {}, wars := []) -> Texture2D:
	var key := "%s:%d:%d" % [mode, chunk_x, chunk_y]
	if _chunk_texture_cache.has(key):
		return _chunk_texture_cache[key]
	var image := Image.create_empty(chunk_size, chunk_size, false, Image.FORMAT_RGBA8)
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var column := chunk_x * chunk_size + local_x
			var row := chunk_y * chunk_size + local_y
			var color := Color("#0c1821")
			if contains(column, row):
				var index := row * width + column
				color = _cell_color(index, mode, countries, provinces, player_country_id, relations, wars)
			image.set_pixel(local_x, local_y, color)
	var texture := ImageTexture.create_from_image(image)
	_chunk_texture_cache[key] = texture
	return texture

func overview_texture_for_mode(mode: String, countries: Dictionary, provinces: Dictionary, player_country_id := "", relations := {}, wars := []) -> Texture2D:
	if mode == "terrain" and overview_texture != null:
		return overview_texture
	if _overview_mode_cache.has(mode):
		return _overview_mode_cache[mode]
	var image := overview_texture.get_image() if overview_texture != null else Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for index in assigned_indices:
		var row := floori(float(index) / float(width))
		var column := int(index) % width
		image.set_pixel(column, row, _cell_color(int(index), mode, countries, provinces, player_country_id, relations, wars))
	var texture := ImageTexture.create_from_image(image)
	_overview_mode_cache[mode] = texture
	return texture

func clear_chunk_cache() -> void:
	_chunk_texture_cache.clear()
	_overview_mode_cache.clear()

func terrain_name(terrain_value: int) -> String:
	for key in manifest.get("terrain_ids", {}).keys():
		if int(manifest.terrain_ids[key]) == terrain_value:
			return String(key)
	return "unknown"

func visible_chunk_bounds(world_view: Rect2) -> Rect2i:
	var chunk_world_size := float(chunk_size) * tile_size
	var min_x := clampi(floori(world_view.position.x / chunk_world_size), 0, maxi(0, ceili(float(width) / chunk_size) - 1))
	var min_y := clampi(floori(world_view.position.y / chunk_world_size), 0, maxi(0, ceili(float(height) / chunk_size) - 1))
	var max_x := clampi(floori(world_view.end.x / chunk_world_size), min_x, maxi(min_x, ceili(float(width) / chunk_size) - 1))
	var max_y := clampi(floori(world_view.end.y / chunk_world_size), min_y, maxi(min_y, ceili(float(height) / chunk_size) - 1))
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _cell_color(index: int, mode: String, countries: Dictionary, provinces: Dictionary, player_country_id: String, relations: Dictionary, wars: Array) -> Color:
	var terrain_color: Color = TERRAIN_COLORS.get(int(terrain[index]), Color("#143548"))
	if mode == "terrain" or int(terrain[index]) <= 3 or int(terrain[index]) == 13:
		return terrain_color
	var source_index := int(province_layer[index])
	if source_index <= 0 or source_index >= province_sources.size():
		return terrain_color.darkened(0.08)
	var runtime_id := int(source_to_runtime_id.get(String(province_sources[source_index]), -1))
	var province: Dictionary = provinces.get(runtime_id, {})
	if province.is_empty():
		return terrain_color
	var owner := String(province.get("owner", ""))
	var country_color := Color(String(countries.get(owner, {}).get("color", "#6b7378")))
	if mode == "political":
		return terrain_color.lerp(country_color, 0.72)
	if mode == "relations":
		if owner == player_country_id:
			return Color("#4f8a72")
		if _countries_at_war(player_country_id, owner, wars):
			return Color("#9c4343")
		var relation := int(relations.get(_pair_key(player_country_id, owner), 0))
		return Color("#4d7f91") if relation >= 25 else Color("#8f6447") if relation <= -25 else Color("#777a70")
	if mode == "war":
		if owner == player_country_id:
			return Color("#3f7580")
		return Color("#9b3e3e") if _countries_at_war(player_country_id, owner, wars) else Color("#4e5458")
	var value := 0.0
	match mode:
		"economy": value = float(province.get("economy", 0.0)) / 100.0
		"population": value = log(1.0 + float(province.get("population", 0.0))) / 13.0
		"development": value = float(province.get("development", 0.0)) / 10.0
		"manpower": value = log(1.0 + float(province.get("manpower", province.get("population", 0.0) * 0.2))) / 12.0
		"stability": value = float(province.get("stability", 50.0)) / 100.0
		"revolt": value = float(province.get("revolt_risk", province.get("unrest", 0.0))) / 100.0
		"fort": value = float(province.get("fort", 0.0)) / 5.0
		"supply": value = (float(province.get("development", 0.0)) * 18.0 + float(province.get("economy", 0.0))) / 200.0
		_: return terrain_color.lerp(country_color, 0.72)
	var high := Color("#b34c45") if mode == "revolt" else Color("#d2a75f")
	if mode == "stability":
		high = Color("#4d9a78")
	elif mode == "fort":
		high = Color("#9e87bd")
	return Color("#27343b").lerp(high, clampf(value, 0.0, 1.0))

func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _countries_at_war(a: String, b: String, wars: Array) -> bool:
	for war_value in wars:
		if war_value is Dictionary:
			var attacker := String(war_value.get("attacker", ""))
			var defender := String(war_value.get("defender", ""))
			if (attacker == a and defender == b) or (attacker == b and defender == a):
				return true
	return false

func _load_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Map binary could not be opened: %s (error %s)" % [path, error_string(FileAccess.get_open_error())])
		return PackedByteArray()
	return file.get_buffer(file.get_length())

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Map JSON could not be opened: %s (error %s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("Map JSON is invalid: %s" % path)
	return {}
