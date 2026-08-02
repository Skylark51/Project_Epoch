class_name WorldMapData
extends RefCounted


const MANIFEST_PATH := "res://data/maps/generated/east_asia_world_map_manifest.json"
const CITY_PICK_BUCKET_SIZE := 160.0
const MAX_CACHED_VISUAL_REVISIONS := 2

const TERRAIN_COLORS := {
    0: Color("#143548"), 1: Color("#1c4e67"), 2: Color("#367085"),
    3: Color("#b2a670"), 4: Color("#9d9d67"), 5: Color("#6f8b55"),
    6: Color("#386747"), 7: Color("#77684c"), 8: Color("#665b52"),
    9: Color("#b79d5e"), 10: Color("#898e53"), 11: Color("#487760"),
    12: Color("#3b7b99"), 13: Color("#2f6987")
}


# The terrain, province-source layer, city records, and overview texture are
# immutable for a loaded map identity. Three StrategicMap instances can share
# these resources instead of re-reading the 307,200-cell files per screen.
static var _shared_static_data: Dictionary = {}
static var static_data_load_count := 0
static var static_data_reuse_count := 0


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
var error_message := ""

var _chunk_texture_cache: Dictionary = {}
var _overview_mode_cache: Dictionary = {}
var _province_color_cache: Dictionary = {}
var _cached_visual_namespaces: Array[String] = []
var _runtime_mapping_signature := ""
var _runtime_mapping_revision := 0
var _city_spatial_buckets: Dictionary = {}
var _city_by_id: Dictionary = {}
var _city_positions: Dictionary = {}

var runtime_binding_rebuild_count := 0
var city_index_rebuild_count := 0
var texture_generation_count := 0
var chunk_texture_generation_count := 0
var overview_texture_generation_count := 0
var province_style_generation_count := 0


func load_default() -> bool:
    if not _load_shared_static_data():
        error_message = "Map manifest could not be loaded: %s" % MANIFEST_PATH
        push_error(error_message)
        return false

    manifest = _shared_static_data["manifest"]
    width = int(manifest.get("width", 0))
    height = int(manifest.get("height", 0))
    chunk_size = int(manifest.get("chunk_size", 16))
    tile_size = float(manifest.get("tile_size", 8))
    province_sources = _shared_static_data["province_sources"]
    terrain = _shared_static_data["terrain"]
    province_layer = _shared_static_data["province_layer"]
    assigned_indices = _shared_static_data["assigned_indices"]
    cities = _shared_static_data["cities"]
    overview_texture = _shared_static_data["overview_texture"]
    projection.configure(manifest)
    _rebuild_city_index()
    error_message = ""
    return true


func bind_runtime_provinces(provinces: Dictionary) -> bool:
    var next_source_to_runtime: Dictionary = {}
    var next_runtime_to_source: Dictionary = {}
    var signature_parts: Array[String] = []

    for id_value in provinces.keys():
        var province_value = provinces[id_value]
        if province_value is not Dictionary:
            continue
        var runtime_id := int(id_value)
        var source_id := String(province_value.get("source_province_id", ""))
        if source_id.is_empty():
            continue
        next_source_to_runtime[source_id] = runtime_id
        next_runtime_to_source[runtime_id] = source_id
        signature_parts.append("%s=%d" % [source_id, runtime_id])

    signature_parts.sort()
    var next_signature := "|".join(signature_parts)
    if next_signature == _runtime_mapping_signature:
        return false

    source_to_runtime_id = next_source_to_runtime
    runtime_to_source_id = next_runtime_to_source
    _runtime_mapping_signature = next_signature
    _runtime_mapping_revision += 1
    runtime_binding_rebuild_count += 1
    return true


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
    return Vector2i(
        floori(world_position.x / tile_size),
        floori(world_position.y / tile_size)
    )


func tile_center(column: int, row: int) -> Vector2:
    return Vector2(
        (float(column) + 0.5) * tile_size,
        (float(row) + 0.5) * tile_size
    )


func world_from_lonlat(longitude: float, latitude: float) -> Vector2:
    return projection.lonlat_to_tile(longitude, latitude) * tile_size


func lonlat_from_world(world_position: Vector2) -> Vector2:
    return projection.tile_to_lonlat(world_position / tile_size)


func city_at_world(world_position: Vector2, world_radius: float) -> Dictionary:
    var radius := maxf(0.0, world_radius)
    var minimum_cell := _city_bucket_for(world_position - Vector2.ONE * radius)
    var maximum_cell := _city_bucket_for(world_position + Vector2.ONE * radius)
    var closest_id := ""
    var closest_distance := INF

    for column in range(minimum_cell.x, maximum_cell.x + 1):
        for row in range(minimum_cell.y, maximum_cell.y + 1):
            for city_id_value in _city_spatial_buckets.get(Vector2i(column, row), []):
                var city_id := String(city_id_value)
                var city_position := city_position_for(city_id)
                var distance := world_position.distance_to(city_position)
                if distance <= radius and distance < closest_distance:
                    closest_id = city_id
                    closest_distance = distance

    return city_record(closest_id)


func city_record(city_id: String) -> Dictionary:
    var city_value = _city_by_id.get(city_id, {})
    return city_value if city_value is Dictionary else {}


func city_position_for(city_id: String) -> Vector2:
    var position = _city_positions.get(city_id, Vector2.ZERO)
    return position if position is Vector2 else Vector2.ZERO


func cities_in_world_rect(world_view: Rect2) -> Array[Dictionary]:
    var visible_rect := world_view.abs()
    var minimum_cell := _city_bucket_for(visible_rect.position)
    var maximum_cell := _city_bucket_for(visible_rect.end)
    var result: Array[Dictionary] = []

    for column in range(minimum_cell.x, maximum_cell.x + 1):
        for row in range(minimum_cell.y, maximum_cell.y + 1):
            for city_id_value in _city_spatial_buckets.get(Vector2i(column, row), []):
                var city_id := String(city_id_value)
                if visible_rect.has_point(city_position_for(city_id)):
                    var city := city_record(city_id)
                    if not city.is_empty():
                        result.append(city)
    return result


func city_ids_in_display_order() -> Array[String]:
    var city_ids: Array[String] = []
    for city_id_value in _city_by_id.keys():
        city_ids.append(String(city_id_value))

    city_ids.sort_custom(
        func(first_id: String, second_id: String) -> bool:
            var first_position := city_position_for(first_id)
            var second_position := city_position_for(second_id)
            if is_equal_approx(first_position.x, second_position.x):
                return first_position.y < second_position.y
            return first_position.x < second_position.x
    )
    return city_ids


func chunk_texture(
    chunk_x: int,
    chunk_y: int,
    mode: String,
    countries: Dictionary,
    provinces: Dictionary,
    player_country_id := "",
    relations := {},
    wars := [],
    visual_revision := 0
) -> Texture2D:
    var cache_namespace := _retain_visual_namespace(visual_revision)
    var key := "%s|chunk|%s|%d|%d" % [cache_namespace, mode, chunk_x, chunk_y]
    if _chunk_texture_cache.has(key):
        return _chunk_texture_cache[key]

    var province_colors := _province_colors_for_mode(
        cache_namespace,
        mode,
        countries,
        provinces,
        player_country_id,
        relations,
        wars
    )
    var image := Image.create_empty(chunk_size, chunk_size, false, Image.FORMAT_RGBA8)
    for local_y in range(chunk_size):
        for local_x in range(chunk_size):
            var column := chunk_x * chunk_size + local_x
            var row := chunk_y * chunk_size + local_y
            var color := Color("#0c1821")
            if contains(column, row):
                var index := row * width + column
                color = _cell_color(index, mode, province_colors)
            image.set_pixel(local_x, local_y, color)

    var texture := ImageTexture.create_from_image(image)
    _chunk_texture_cache[key] = texture
    texture_generation_count += 1
    chunk_texture_generation_count += 1
    return texture


func overview_texture_for_mode(
    mode: String,
    countries: Dictionary,
    provinces: Dictionary,
    player_country_id := "",
    relations := {},
    wars := [],
    visual_revision := 0
) -> Texture2D:
    if mode == "terrain" and overview_texture != null:
        return overview_texture

    var cache_namespace := _retain_visual_namespace(visual_revision)
    var key := "%s|overview|%s" % [cache_namespace, mode]
    if _overview_mode_cache.has(key):
        return _overview_mode_cache[key]

    var province_colors := _province_colors_for_mode(
        cache_namespace,
        mode,
        countries,
        provinces,
        player_country_id,
        relations,
        wars
    )
    var image := (
        overview_texture.get_image()
        if overview_texture != null
        else Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
    )
    for index_value in assigned_indices:
        var index := int(index_value)
        var row := floori(float(index) / float(width))
        var column := index % width
        image.set_pixel(column, row, _cell_color(index, mode, province_colors))

    var texture := ImageTexture.create_from_image(image)
    _overview_mode_cache[key] = texture
    texture_generation_count += 1
    overview_texture_generation_count += 1
    return texture


func clear_chunk_cache() -> void:
    _chunk_texture_cache.clear()
    _overview_mode_cache.clear()
    _province_color_cache.clear()
    _cached_visual_namespaces.clear()


func performance_metrics() -> Dictionary:
    return {
        "runtime_binding_rebuilds": runtime_binding_rebuild_count,
        "city_index_rebuilds": city_index_rebuild_count,
        "texture_generations": texture_generation_count,
        "chunk_texture_generations": chunk_texture_generation_count,
        "overview_texture_generations": overview_texture_generation_count,
        "province_style_generations": province_style_generation_count,
        "cached_chunks": _chunk_texture_cache.size(),
        "cached_overviews": _overview_mode_cache.size(),
        "cached_visual_revisions": _cached_visual_namespaces.size(),
        "static_data_loads": static_data_load_count,
        "static_data_reuses": static_data_reuse_count
    }


func terrain_name(terrain_value: int) -> String:
    for key in manifest.get("terrain_ids", {}).keys():
        if int(manifest.terrain_ids[key]) == terrain_value:
            return String(key)
    return "unknown"


func visible_chunk_bounds(world_view: Rect2) -> Rect2i:
    var chunk_world_size := float(chunk_size) * tile_size
    var min_x := clampi(
        floori(world_view.position.x / chunk_world_size),
        0,
        maxi(0, ceili(float(width) / chunk_size) - 1)
    )
    var min_y := clampi(
        floori(world_view.position.y / chunk_world_size),
        0,
        maxi(0, ceili(float(height) / chunk_size) - 1)
    )
    var max_x := clampi(
        floori(world_view.end.x / chunk_world_size),
        min_x,
        maxi(min_x, ceili(float(width) / chunk_size) - 1)
    )
    var max_y := clampi(
        floori(world_view.end.y / chunk_world_size),
        min_y,
        maxi(min_y, ceili(float(height) / chunk_size) - 1)
    )
    return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _load_shared_static_data() -> bool:
    if not _shared_static_data.is_empty():
        static_data_reuse_count += 1
        return true

    var loaded_manifest := _load_json(MANIFEST_PATH)
    if loaded_manifest.is_empty():
        return false

    var loaded_width := int(loaded_manifest.get("width", 0))
    var loaded_height := int(loaded_manifest.get("height", 0))
    var loaded_terrain := _load_bytes(String(loaded_manifest.get("terrain_file", "")))
    var loaded_provinces := _load_bytes(String(loaded_manifest.get("province_file", "")))
    if (
        loaded_width <= 0
        or loaded_height <= 0
        or loaded_terrain.size() != loaded_width * loaded_height
        or loaded_provinces.size() != loaded_width * loaded_height
    ):
        error_message = "Map layer size mismatch: expected %d, terrain=%d, province=%d" % [
            loaded_width * loaded_height,
            loaded_terrain.size(),
            loaded_provinces.size()
        ]
        push_error(error_message)
        return false

    var loaded_indices := PackedInt32Array()
    for index in range(loaded_provinces.size()):
        if int(loaded_provinces[index]) > 0:
            loaded_indices.append(index)

    var city_data := _load_json(String(loaded_manifest.get("cities_file", "")))
    var loaded_overview: Texture2D
    var overview_path := String(loaded_manifest.get("overview_file", ""))
    if ResourceLoader.exists(overview_path):
        loaded_overview = load(overview_path)

    _shared_static_data = {
        "manifest": loaded_manifest,
        "terrain": loaded_terrain,
        "province_layer": loaded_provinces,
        "assigned_indices": loaded_indices,
        "cities": city_data.get("cities", []),
        "province_sources": loaded_manifest.get("province_sources", []),
        "overview_texture": loaded_overview
    }
    static_data_load_count += 1
    return true


func _rebuild_city_index() -> void:
    _city_spatial_buckets.clear()
    _city_by_id.clear()
    _city_positions.clear()

    for city_value in cities:
        if city_value is not Dictionary:
            continue
        var city: Dictionary = city_value
        if not bool(city.get("enabled", true)) or not bool(city.get("inBounds", false)):
            continue
        var city_id := String(city.get("id", ""))
        if city_id.is_empty():
            continue
        var position := Vector2(
            float(city.get("mapX", 0.0)),
            float(city.get("mapY", 0.0))
        ) * tile_size
        var cell := _city_bucket_for(position)
        if not _city_spatial_buckets.has(cell):
            _city_spatial_buckets[cell] = []
        _city_spatial_buckets[cell].append(city_id)
        _city_by_id[city_id] = city
        _city_positions[city_id] = position

    city_index_rebuild_count += 1


func _city_bucket_for(world_position: Vector2) -> Vector2i:
    return Vector2i(
        floori(world_position.x / CITY_PICK_BUCKET_SIZE),
        floori(world_position.y / CITY_PICK_BUCKET_SIZE)
    )


func _retain_visual_namespace(visual_revision: int) -> String:
    var cache_namespace := "%d:%d" % [
        _runtime_mapping_revision,
        visual_revision
    ]
    if cache_namespace in _cached_visual_namespaces:
        return cache_namespace

    _cached_visual_namespaces.append(cache_namespace)
    while _cached_visual_namespaces.size() > MAX_CACHED_VISUAL_REVISIONS:
        var expired_namespace := String(_cached_visual_namespaces.pop_front())
        _clear_visual_namespace(expired_namespace)
    return cache_namespace


func _clear_visual_namespace(cache_namespace: String) -> void:
    var prefix := cache_namespace + "|"
    for key_value in _chunk_texture_cache.keys():
        var key := String(key_value)
        if key.begins_with(prefix):
            _chunk_texture_cache.erase(key_value)
    for key_value in _overview_mode_cache.keys():
        var key := String(key_value)
        if key.begins_with(prefix):
            _overview_mode_cache.erase(key_value)
    for key_value in _province_color_cache.keys():
        var key := String(key_value)
        if key.begins_with(prefix):
            _province_color_cache.erase(key_value)


func _province_colors_for_mode(
    cache_namespace: String,
    mode: String,
    countries: Dictionary,
    provinces: Dictionary,
    player_country_id: String,
    relations: Dictionary,
    wars: Array
) -> Dictionary:
    var key := "%s|styles|%s" % [cache_namespace, mode]
    if _province_color_cache.has(key):
        return _province_color_cache[key]

    var war_pairs := _war_pairs(wars)
    var colors: Dictionary = {}
    for runtime_id_value in runtime_to_source_id.keys():
        var runtime_id := int(runtime_id_value)
        var province_value = provinces.get(runtime_id, {})
        if province_value is not Dictionary or province_value.is_empty():
            continue
        colors[runtime_id] = _province_visual_color(
            province_value,
            mode,
            countries,
            player_country_id,
            relations,
            war_pairs
        )

    _province_color_cache[key] = colors
    province_style_generation_count += colors.size()
    return colors


func _cell_color(
    index: int,
    mode: String,
    province_colors: Dictionary
) -> Color:
    var terrain_color: Color = TERRAIN_COLORS.get(
        int(terrain[index]),
        Color("#143548")
    )
    if mode == "terrain" or int(terrain[index]) <= 3 or int(terrain[index]) == 13:
        return terrain_color

    var source_index := int(province_layer[index])
    if source_index <= 0 or source_index >= province_sources.size():
        return terrain_color.darkened(0.08)
    var runtime_id := int(
        source_to_runtime_id.get(String(province_sources[source_index]), -1)
    )
    if not province_colors.has(runtime_id):
        return terrain_color

    var province_color: Color = province_colors[runtime_id]
    if mode == "political":
        return terrain_color.lerp(province_color, 0.72)
    return province_color


func _province_visual_color(
    province: Dictionary,
    mode: String,
    countries: Dictionary,
    player_country_id: String,
    relations: Dictionary,
    war_pairs: Dictionary
) -> Color:
    var owner := String(province.get("owner", ""))
    var country_color := Color(
        String(countries.get(owner, {}).get("color", "#6b7378"))
    )
    if mode == "political":
        return country_color
    if mode == "relations":
        if owner == player_country_id:
            return Color("#4f8a72")
        if war_pairs.has(_pair_key(player_country_id, owner)):
            return Color("#9c4343")
        var relation := int(relations.get(_pair_key(player_country_id, owner), 0))
        return (
            Color("#4d7f91")
            if relation >= 25
            else Color("#8f6447") if relation <= -25 else Color("#777a70")
        )
    if mode == "war":
        if owner == player_country_id:
            return Color("#3f7580")
        return (
            Color("#9b3e3e")
            if war_pairs.has(_pair_key(player_country_id, owner))
            else Color("#4e5458")
        )

    var value := 0.0
    match mode:
        "economy":
            value = float(province.get("economy", 0.0)) / 100.0
        "population":
            value = log(1.0 + float(province.get("population", 0.0))) / 13.0
        "development":
            value = float(province.get("development", 0.0)) / 10.0
        "manpower":
            value = log(
                1.0 + float(
                    province.get(
                        "manpower",
                        province.get("population", 0.0) * 0.2
                    )
                )
            ) / 12.0
        "stability":
            value = float(province.get("stability", 50.0)) / 100.0
        "revolt":
            value = float(
                province.get("revolt_risk", province.get("unrest", 0.0))
            ) / 100.0
        "fort":
            value = float(province.get("fort", 0.0)) / 5.0
        "supply":
            value = (
                float(province.get("development", 0.0)) * 18.0
                + float(province.get("economy", 0.0))
            ) / 200.0
        _:
            return country_color

    var high := Color("#b34c45") if mode == "revolt" else Color("#d2a75f")
    if mode == "stability":
        high = Color("#4d9a78")
    elif mode == "fort":
        high = Color("#9e87bd")
    return Color("#27343b").lerp(high, clampf(value, 0.0, 1.0))


func _war_pairs(wars: Array) -> Dictionary:
    var pairs: Dictionary = {}
    for war_value in wars:
        if war_value is not Dictionary:
            continue
        var attacker := String(war_value.get("attacker", ""))
        var defender := String(war_value.get("defender", ""))
        if not attacker.is_empty() and not defender.is_empty():
            pairs[_pair_key(attacker, defender)] = true
    return pairs


func _pair_key(first_country_id: String, second_country_id: String) -> String:
    if first_country_id < second_country_id:
        return first_country_id + "|" + second_country_id
    return second_country_id + "|" + first_country_id


func _load_bytes(path: String) -> PackedByteArray:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error(
            "Map binary could not be opened: %s (error %s)"
            % [path, error_string(FileAccess.get_open_error())]
        )
        return PackedByteArray()
    return file.get_buffer(file.get_length())


func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error(
            "Map JSON could not be opened: %s (error %s)"
            % [path, error_string(FileAccess.get_open_error())]
        )
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed
    push_error("Map JSON is invalid: %s" % path)
    return {}
