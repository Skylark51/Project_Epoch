class_name StrategicMap
extends Control

signal province_selected(province_id: int)
signal selection_changed(province_ids: Array[int])
signal province_dropped(from_id: int, to_id: int)
signal command_target_selected(province_id: int)
signal city_selected(city_id: String)
signal tooltip_changed(text: String, screen_position: Vector2)
signal camera_changed(zoom: float)
signal zoom_tier_changed(tier: String)

enum InputState { IDLE, CHOOSING_MOVE_TARGET, CHOOSING_ATTACK_TARGET, SELECTING_PEACE_TERMS, DRAGGING_MAP, MODAL_OPEN }

const MODE_LABELS := {
    "political": "정치", "relations": "외교 관계", "war": "전쟁", "economy": "경제",
    "population": "인구", "development": "개발도", "manpower": "인력", "stability": "안정도",
    "revolt": "반란 위험", "terrain": "지형", "fort": "요새", "supply": "보급"
}
const WorldMapDataScript = preload("res://src/map/world_map_data.gd")
const BattlefieldUnitRendererScript = preload("res://src/map/battlefield_unit_renderer.gd")

const TERRAIN_COLORS := {
    "plains": Color("#7d8a63"), "hills": Color("#81725b"), "forest": Color("#4f6c55"),
    "coast": Color("#58788a"), "coastal_water": Color("#1d4b60"), "deep_water": Color("#102f42")
}

var provinces: Dictionary = {}
var map_tiles: Array = []
var map_labels: Array = []
var world_map: WorldMapData
var world_map_id := ""
var countries: Dictionary = {}
var armies: Dictionary = {}
var army_groups: Array = []
var show_battlefield_units := false
var relations: Dictionary = {}
var wars: Array = []
var player_country_id := ""
var selected_province_id := -1
var selected_province_ids: Array[int] = []
var _selection_dragging := false
var _selection_origin := Vector2.ZERO
var _selection_current := Vector2.ZERO
var _selection_additive := false
var _command_drag := false
var _drag_source_id := -1
var command_source_id := -1
var map_mode := "political"
var input_state: InputState = InputState.IDLE
var zoom := 1.0
var pan := Vector2.ZERO
var min_zoom := 0.05
var max_zoom := 8.0
var _drag_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _drag_button := MOUSE_BUTTON_NONE
var _did_drag := false
var _state_before_drag: InputState = InputState.IDLE
var _hovered_id := -1
var _command_paths: Array[Dictionary] = []
var _peace_demands: Array[int] = []
var _world_rect := Rect2(0, 0, 800, 560)
var _spatial_buckets: Dictionary = {}
var _tile_spatial_buckets: Dictionary = {}
var debug_map_enabled := false
var show_chunk_boundaries := false
var show_coast_highlight := false
var show_region_ids := false
var visible_chunk_count := 0
var last_rendered_tile_count := 0
var notification_markers: Array[Dictionary] = []
var _last_zoom_tier := ""
var _battlefield_unit_renderer = BattlefieldUnitRendererScript.new()
const PICK_BUCKET_SIZE := 160.0
const ZOOM_TIERS := {"strategy": 0.18, "region": 0.68, "close": 1.65}
const PLAY_AREA_TILES := Vector2(172.0, 118.0)
const PLAY_AREA_MIN_ZOOM := 0.30
const PLAY_AREA_MAX_ZOOM := 0.78
const CITY_ROUTE_PAIRS := [
    ["pyongyang", "gaeseong"], ["gaeseong", "seoul"], ["seoul", "incheon"],
    ["seoul", "suwon"], ["seoul", "chuncheon"], ["chuncheon", "gangneung"],
    ["suwon", "cheongju"], ["cheongju", "daejeon"], ["daejeon", "jeonju"],
    ["jeonju", "gwangju"], ["gwangju", "mokpo"], ["daejeon", "daegu"],
    ["daegu", "gyeongju"], ["gyeongju", "busan"], ["gyeongju", "pohang"]
]

# A reversible 2:1 dimetric (3/4) projection. World data stays in its existing
# geographic coordinate space; all camera and picking paths use this same basis.
const ISO_HORIZONTAL := 0.72
const ISO_VERTICAL := 0.36

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    clip_contents = true
    resized.connect(_clamp_pan)

func world_to_screen(world_position: Vector2) -> Vector2:
    return pan + _project_world_point(world_position) * zoom

func screen_to_world(screen_position: Vector2) -> Vector2:
    var projected := (screen_position - pan) / maxf(zoom, 0.0001)
    return _unproject_world_point(projected)

func _project_world_point(world_position: Vector2) -> Vector2:
    return Vector2(
        (world_position.x - world_position.y) * ISO_HORIZONTAL,
        (world_position.x + world_position.y) * ISO_VERTICAL
    )

func _unproject_world_point(projected_position: Vector2) -> Vector2:
    return Vector2(
        (projected_position.x / ISO_HORIZONTAL + projected_position.y / ISO_VERTICAL) * 0.5,
        (-projected_position.x / ISO_HORIZONTAL + projected_position.y / ISO_VERTICAL) * 0.5
    )

func _world_draw_transform() -> Transform2D:
    return Transform2D(
        Vector2(ISO_HORIZONTAL * zoom, ISO_VERTICAL * zoom),
        Vector2(-ISO_HORIZONTAL * zoom, ISO_VERTICAL * zoom),
        pan
    )

func _projected_bounds_for_rect(world_rect: Rect2) -> Rect2:
    var corners: Array[Vector2] = [
        world_rect.position,
        Vector2(world_rect.end.x, world_rect.position.y),
        world_rect.end,
        Vector2(world_rect.position.x, world_rect.end.y)
    ]
    var minimum: Vector2 = _project_world_point(corners[0])
    var maximum: Vector2 = minimum
    for corner: Vector2 in corners:
        var projected: Vector2 = _project_world_point(corner)
        minimum = Vector2(minf(minimum.x, projected.x), minf(minimum.y, projected.y))
        maximum = Vector2(maxf(maximum.x, projected.x), maxf(maximum.y, projected.y))
    return Rect2(minimum, maximum - minimum)

func _visible_world_bounds() -> Rect2:
    var corners: Array[Vector2] = [
        screen_to_world(Vector2.ZERO),
        screen_to_world(Vector2(size.x, 0.0)),
        screen_to_world(size),
        screen_to_world(Vector2(0.0, size.y))
    ]
    var minimum: Vector2 = corners[0]
    var maximum: Vector2 = minimum
    for corner: Vector2 in corners:
        minimum = Vector2(minf(minimum.x, corner.x), minf(minimum.y, corner.y))
        maximum = Vector2(maxf(maximum.x, corner.x), maxf(maximum.y, corner.y))
    var grow_amount: float = world_map.tile_size * 2.0 if world_map != null else 16.0
    return Rect2(minimum, maximum - minimum).grow(grow_amount)

func _center_world(world_position: Vector2) -> void:
    pan = size * 0.5 - _project_world_point(world_position) * zoom

func set_snapshot(snapshot: Dictionary) -> void:
    provinces = snapshot.get("provinces", {}).duplicate(true)
    map_tiles = snapshot.get("map_tiles", []).duplicate(true)
    map_labels = snapshot.get("map_labels", []).duplicate(true)
    countries = snapshot.get("countries", {}).duplicate(true)
    armies = snapshot.get("armies", {}).duplicate(true)
    army_groups = snapshot.get("army_groups", []).duplicate(true)
    relations = snapshot.get("relations", {}).duplicate(true)
    wars = snapshot.get("wars", []).duplicate(true)
    player_country_id = String(snapshot.get("player_country_id", ""))
    world_map_id = String(snapshot.get("world_map_id", ""))
    if not world_map_id.is_empty():
        if world_map == null:
            world_map = WorldMapDataScript.new()
            if not world_map.load_default():
                push_error("Strategic map fell back to legacy geometry: %s" % world_map.error_message)
                world_map = null
        if world_map != null:
            world_map.bind_runtime_provinces(provinces)
    _recalculate_world_rect()
    _rebuild_spatial_index()
    queue_redraw()

func set_mode(value: String) -> void:
    if not MODE_LABELS.has(value):
        return
    map_mode = value
    queue_redraw()

func mode_label() -> String:
    return String(MODE_LABELS.get(map_mode, map_mode))

func set_interaction_state(value: InputState, source_id := -1) -> void:
    input_state = value
    command_source_id = source_id
    queue_redraw()

func clear_interaction() -> void:
    input_state = InputState.IDLE
    command_source_id = -1
    _peace_demands.clear()
    queue_redraw()

func set_command_paths(paths: Array) -> void:
    _command_paths.clear()
    for value in paths:
        if value is Dictionary:
            _command_paths.append(value.duplicate(true))
    queue_redraw()

func set_peace_demands(ids: Array[int]) -> void:
    _peace_demands = ids.duplicate()
    queue_redraw()

func frame_world() -> void:
    if size.x <= 1.0 or size.y <= 1.0:
        return
    if world_map != null:
        var play_area := PLAY_AREA_TILES * world_map.tile_size
        var focus := _preferred_world_focus()
        var projected_play_area := _projected_bounds_for_rect(Rect2(focus - play_area * 0.5, play_area))
        var target_zoom := minf(
            size.x / maxf(projected_play_area.size.x, 1.0),
            size.y / maxf(projected_play_area.size.y, 1.0)
        )
        zoom = clampf(target_zoom, maxf(min_zoom, PLAY_AREA_MIN_ZOOM), PLAY_AREA_MAX_ZOOM)
        _center_world(focus)
        _clamp_pan()
        _emit_camera_state()
        queue_redraw()
        return
    var projected_world := _projected_bounds_for_rect(_world_rect)
    var zx := size.x / maxf(projected_world.size.x + 120.0, 1.0)
    var zy := size.y / maxf(projected_world.size.y + 120.0, 1.0)
    zoom = clampf(minf(zx, zy), min_zoom, 1.8)
    _center_world(_world_rect.get_center())
    _clamp_pan()
    _emit_camera_state()
    queue_redraw()

func _preferred_world_focus() -> Vector2:
    var country: Dictionary = countries.get(player_country_id, {})
    var capital_id := int(country.get("capital_province", -1))
    if provinces.has(capital_id):
        return _province_center(provinces[capital_id])
    return world_map.world_from_lonlat(127.25, 37.55)
func focus_province(province_id: int) -> void:
    var province: Dictionary = provinces.get(province_id, {})
    if province.is_empty():
        return
    _center_world(_province_center(province))
    _clamp_pan()
    queue_redraw()

func focus_city(city_id: String) -> bool:
    if world_map == null:
        return false
    for city_value in world_map.cities:
        if city_value is Dictionary and String(city_value.get("id", "")) == city_id:
            var position := Vector2(float(city_value.get("mapX", 0.0)), float(city_value.get("mapY", 0.0))) * world_map.tile_size
            _center_world(position)
            _clamp_pan()
            queue_redraw()
            return true
    return false

func nudge_camera(delta:Vector2) -> void:
    pan+=delta; _clamp_pan(); queue_redraw()

func set_zoom_tier(tier: String) -> void:
    if ZOOM_TIERS.has(tier):
        set_zoom_level(float(ZOOM_TIERS[tier]))

func set_zoom_level(value: float, screen_point := Vector2(-1, -1)) -> void:
    var anchor := screen_point
    if anchor.x < 0.0 or anchor.y < 0.0:
        anchor = size * 0.5
    var before := screen_to_world(anchor)
    zoom = clampf(value, min_zoom, max_zoom)
    pan = anchor - _project_world_point(before) * zoom
    _clamp_pan()
    _emit_camera_state()
    queue_redraw()

func semantic_zoom_tier() -> String:
    if zoom < 0.38:
        return "strategy"
    if zoom < 1.1:
        return "region"
    return "close"

func center_from_minimap(normalized_position: Vector2) -> void:
    var normalized := normalized_position.clamp(Vector2.ZERO, Vector2.ONE)
    var center := _world_rect.position + _world_rect.size * normalized
    _center_world(center)
    _clamp_pan()
    queue_redraw()

func set_notification_markers(markers: Array) -> void:
    notification_markers.clear()
    for marker in markers:
        if marker is Dictionary:
            notification_markers.append(marker.duplicate(true))
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if input_state == InputState.MODAL_OPEN:
        accept_event(); return
    if event is InputEventKey and event.pressed:
        var key := event as InputEventKey
        if key.keycode == KEY_F6:
            debug_map_enabled = not debug_map_enabled
            queue_redraw(); accept_event()
        elif key.keycode == KEY_F7:
            show_coast_highlight = not show_coast_highlight
            queue_redraw(); accept_event()
        elif key.keycode == KEY_F8:
            show_chunk_boundaries = not show_chunk_boundaries
            queue_redraw(); accept_event()
        elif key.keycode == KEY_F9:
            show_region_ids = not show_region_ids
            queue_redraw(); accept_event()
        elif key.keycode == KEY_HOME:
            frame_world(); accept_event()
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
            _zoom_at(button.position, 1.14); accept_event()
        elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
            _zoom_at(button.position, 1.0 / 1.14); accept_event()
        elif button.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
            if button.pressed:
                _drag_button = button.button_index; _drag_origin = button.position; _pan_origin = pan; _did_drag = false
            else:
                if _drag_button == button.button_index and not _did_drag and button.button_index == MOUSE_BUTTON_RIGHT:
                    _handle_target_click(_province_at(button.position))
                _drag_button = MOUSE_BUTTON_NONE
                if input_state == InputState.DRAGGING_MAP: input_state = _state_before_drag
            accept_event()
        elif button.button_index == MOUSE_BUTTON_LEFT:
            if button.pressed:
                var clicked_city := _city_at(button.position)
                if not clicked_city.is_empty():
                    city_selected.emit(clicked_city)
                    accept_event()
                    return
                var province_id := _province_at(button.position)
                if button.ctrl_pressed and province_id != -1 and input_state == InputState.IDLE:
                    _command_drag = true; _drag_source_id = province_id; _selection_origin = button.position; _selection_current = button.position
                elif input_state in [InputState.CHOOSING_MOVE_TARGET, InputState.CHOOSING_ATTACK_TARGET, InputState.SELECTING_PEACE_TERMS]:
                    _handle_target_click(province_id)
                else:
                    _selection_dragging = true; _selection_origin = button.position; _selection_current = button.position
                    _selection_additive = button.shift_pressed
            elif _command_drag:
                var target_id := _province_at(button.position)
                if target_id != -1 and target_id != _drag_source_id: province_dropped.emit(_drag_source_id, target_id)
                _command_drag = false; _drag_source_id = -1; queue_redraw()
            elif _selection_dragging:
                _finish_selection(button.position)
            accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _command_drag:
            _selection_current = motion.position; queue_redraw(); accept_event()
        elif _selection_dragging:
            _selection_current = motion.position; queue_redraw(); accept_event()
        elif _drag_button != MOUSE_BUTTON_NONE:
            if not _did_drag and motion.position.distance_to(_drag_origin) > 5.0:
                _state_before_drag = input_state; _did_drag = true; input_state = InputState.DRAGGING_MAP
            if _did_drag:
                pan = _pan_origin + motion.position - _drag_origin; _clamp_pan(); queue_redraw()
            accept_event()
        else:
            var next_hover := _province_at(motion.position)
            if next_hover != _hovered_id:
                _hovered_id = next_hover; tooltip_changed.emit(_tooltip_for(next_hover), motion.global_position); queue_redraw()

func _finish_selection(position: Vector2) -> void:
    _selection_current = position
    _selection_dragging = false
    var next: Array[int] = []
    if _selection_additive:
        next.assign(selected_province_ids)
    if _selection_origin.distance_to(position) < 7.0:
        var id := _province_at(position)
        if id != -1:
            if _selection_additive and id in next:
                next.erase(id)
            elif id not in next:
                next.append(id)
    else:
        var rect := Rect2(_selection_origin, position - _selection_origin).abs()
        for id_value in provinces.keys():
            var id := int(id_value)
            if rect.has_point(world_to_screen(_province_center(provinces[id]))) and id not in next:
                next.append(id)
    set_selected_provinces(next)

func set_selected_provinces(ids: Array[int]) -> void:
    selected_province_ids = ids.duplicate()
    selected_province_id = selected_province_ids.back() if not selected_province_ids.is_empty() else -1
    selection_changed.emit(selected_province_ids.duplicate())
    if selected_province_id != -1: province_selected.emit(selected_province_id)
    queue_redraw()

func _handle_target_click(province_id: int) -> void:
    if province_id == -1:
        return
    if input_state == InputState.SELECTING_PEACE_TERMS:
        if province_id in _peace_demands:
            _peace_demands.erase(province_id)
        else:
            _peace_demands.append(province_id)
        command_target_selected.emit(province_id)
        queue_redraw()
        return
    if province_id != command_source_id:
        command_target_selected.emit(province_id)

func _zoom_at(screen_point: Vector2, factor: float) -> void:
    set_zoom_level(zoom * factor, screen_point)

func _emit_camera_state() -> void:
    camera_changed.emit(zoom)
    var tier := semantic_zoom_tier()
    if tier != _last_zoom_tier:
        _last_zoom_tier = tier
        zoom_tier_changed.emit(tier)

func _clamp_pan() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var margin := 90.0
    var projected_bounds := _projected_bounds_for_rect(_world_rect)
    var minimum := projected_bounds.position * zoom
    var maximum := projected_bounds.end * zoom
    var min_pan_x := size.x - maximum.x - margin
    var max_pan_x := -minimum.x + margin
    var min_pan_y := size.y - maximum.y - margin
    var max_pan_y := -minimum.y + margin
    pan.x = (min_pan_x + max_pan_x) * 0.5 if min_pan_x > max_pan_x else clampf(pan.x, min_pan_x, max_pan_x)
    pan.y = (min_pan_y + max_pan_y) * 0.5 if min_pan_y > max_pan_y else clampf(pan.y, min_pan_y, max_pan_y)

func _screen_to_world(point: Vector2) -> Vector2:
    return screen_to_world(point)

func battlefield_render_stats() -> Dictionary:
    return _battlefield_unit_renderer.stats()

func _city_at(screen_point: Vector2) -> String:
    if world_map == null:
        return ""
    for city_value in world_map.cities:
        if city_value is not Dictionary or not bool(city_value.get("enabled", true)) or not bool(city_value.get("inBounds", false)):
            continue
        var position := Vector2(float(city_value.get("mapX", 0.0)), float(city_value.get("mapY", 0.0))) * world_map.tile_size
        var major := String(city_value.get("type", "")) == "major_city"
        var hit_radius := 18.0 if major else 14.0
        if screen_point.distance_to(world_to_screen(position)) <= hit_radius:
            return String(city_value.get("id", ""))
    return ""

func _province_at(screen_point: Vector2) -> int:
    var world := _screen_to_world(screen_point)
    if world_map != null:
        var tile := world_map.tile_at_world(world)
        return world_map.province_id(tile.x, tile.y)
    var cell := Vector2i(floori(world.x / PICK_BUCKET_SIZE), floori(world.y / PICK_BUCKET_SIZE))
    if not map_tiles.is_empty():
        var tile_candidates: Array = _tile_spatial_buckets.get(cell, [])
        for tile_index_value in tile_candidates:
            var tile: Dictionary = map_tiles[int(tile_index_value)]
            var tile_polygon := _tile_polygon(tile)
            if tile_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world, tile_polygon):
                return -1 if bool(tile.get("water", false)) else int(tile.get("province_id", -1))
        return -1
    var candidates: Array = _spatial_buckets.get(cell, provinces.keys())
    for id_value in candidates:
        var id := int(id_value)
        var polygon := _polygon_for(provinces[id])
        if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world, polygon):
            return id
    return -1
func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0c1821"))
    draw_set_transform_matrix(_world_draw_transform())
    var numeric_range := _robust_range(_numeric_values(map_mode))
    if world_map != null:
        _draw_world_map(numeric_range)
    elif map_tiles.is_empty():
        _draw_grid()
        _draw_province_polygons(numeric_range)
    else:
        _draw_hex_tiles(numeric_range)
    _draw_command_paths()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if world_map != null:
        _draw_world_labels()
        _draw_city_labels()
        if show_region_ids:
            _draw_region_ids()
        _draw_notification_markers()
    elif not map_tiles.is_empty():
        _draw_region_labels()
    _draw_icons_and_labels()
    if _selection_dragging:
        var selection_rect := Rect2(_selection_origin, _selection_current - _selection_origin).abs()
        draw_rect(selection_rect, Color(0.35, 0.78, 0.88, 0.16), true)
        draw_rect(selection_rect, Color("#6ec7d8"), false, 2.0)
    if _command_drag:
        draw_dashed_line(_selection_origin, _selection_current, Color("#f0c66b"), 3.0, 10.0, true)
    if debug_map_enabled and world_map != null:
        _draw_map_debug_overlay()

func _draw_province_polygons(numeric_range: Vector2) -> void:
    for id_value in provinces.keys():
        var id := int(id_value)
        var province: Dictionary = provinces[id]
        var polygon := _polygon_for(province)
        if polygon.size() < 3:
            continue
        draw_colored_polygon(polygon, _province_color(province, numeric_range))
        var border := _border_color(province)
        var width := 1.4 / zoom
        if id in selected_province_ids or id == selected_province_id:
            border = Color("#f4d58a")
            width = 4.0 / zoom
        elif id == _hovered_id:
            border = Color("#d9e4e6")
            width = 2.5 / zoom
        draw_polyline(polygon + PackedVector2Array([polygon[0]]), border, width, true)
        if id in _peace_demands:
            draw_polyline(polygon + PackedVector2Array([polygon[0]]), Color("#f0a25b"), 6.0 / zoom, true)

func _draw_world_map(_numeric_range: Vector2) -> void:
    var world_view := _visible_world_bounds()
    var chunks := world_map.visible_chunk_bounds(world_view)
    visible_chunk_count = chunks.size.x * chunks.size.y
    last_rendered_tile_count = visible_chunk_count * world_map.chunk_size * world_map.chunk_size
    var chunk_world_size := float(world_map.chunk_size) * world_map.tile_size
    if zoom < 0.32 and world_map.overview_texture != null:
        var overview := world_map.overview_texture_for_mode(map_mode, countries, provinces, player_country_id, relations, wars)
        draw_texture_rect(overview, world_map.world_rect(), false)
        last_rendered_tile_count = 0
    else:
        for chunk_y in range(chunks.position.y, chunks.end.y):
            for chunk_x in range(chunks.position.x, chunks.end.x):
                var texture := world_map.chunk_texture(chunk_x, chunk_y, map_mode, countries, provinces, player_country_id, relations, wars)
                var rect := Rect2(Vector2(float(chunk_x), float(chunk_y)) * chunk_world_size, Vector2.ONE * chunk_world_size)
                draw_texture_rect(texture, rect, false)
                if show_chunk_boundaries:
                    draw_rect(rect, Color(0.95, 0.75, 0.25, 0.72), false, 1.0 / zoom)
        _draw_world_selection(world_view)
        if show_coast_highlight:
            _draw_coast_highlight(world_view)
    _draw_city_routes()
    _draw_battlefield_units()
    _draw_cities()

func _draw_world_selection(world_view: Rect2) -> void:
    if selected_province_ids.is_empty() and _hovered_id == -1:
        return
    var tile_min := world_map.tile_at_world(world_view.position)
    var tile_max := world_map.tile_at_world(world_view.end)
    for row in range(maxi(0, tile_min.y), mini(world_map.height - 1, tile_max.y) + 1):
        for column in range(maxi(0, tile_min.x), mini(world_map.width - 1, tile_max.x) + 1):
            var province_id := world_map.province_id(column, row)
            if province_id in selected_province_ids or province_id == _hovered_id:
                var color := Color(0.96, 0.83, 0.45, 0.43) if province_id in selected_province_ids else Color(0.86, 0.91, 0.92, 0.28)
                draw_rect(Rect2(Vector2(column, row) * world_map.tile_size, Vector2.ONE * world_map.tile_size), color, false, 1.5 / zoom)

func _draw_coast_highlight(world_view: Rect2) -> void:
    var tile_min := world_map.tile_at_world(world_view.position)
    var tile_max := world_map.tile_at_world(world_view.end)
    for row in range(maxi(0, tile_min.y), mini(world_map.height - 1, tile_max.y) + 1):
        for column in range(maxi(0, tile_min.x), mini(world_map.width - 1, tile_max.x) + 1):
            if world_map.terrain_id(column, row) == 3:
                draw_rect(Rect2(Vector2(column, row) * world_map.tile_size, Vector2.ONE * world_map.tile_size), Color(1.0, 0.3, 0.25, 0.58), false, 1.0 / zoom)

func _draw_world_labels() -> void:
    if zoom < 0.16:
        return
    var labels := [
        ["?? ??", 105.0, 37.0, false], ["???", 127.3, 38.2, false],
        ["?? ??", 137.8, 37.0, false], ["??", 123.5, 35.0, true],
        ["??", 132.7, 40.0, true], ["????", 125.0, 28.0, true]
    ]
    var font := ThemeDB.fallback_font
    var font_size := clampi(roundi(14.0 * clampf(zoom, 0.75, 1.2)), 10, 18)
    for label in labels:
        var position := world_to_screen(world_map.world_from_lonlat(float(label[1]), float(label[2])))
        var text := String(label[0])
        var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
        var color := Color(0.60, 0.80, 0.88, 0.62) if bool(label[3]) else Color(0.94, 0.88, 0.68, 0.56)
        draw_string(font, position - Vector2(text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_cities() -> void:
    var ordered_cities: Array = []
    for city_value in world_map.cities:
        if city_value is Dictionary:
            ordered_cities.append(city_value)
    ordered_cities.sort_custom(func(a, b):
        return float(a.get("mapX", 0.0)) + float(a.get("mapY", 0.0)) < float(b.get("mapX", 0.0)) + float(b.get("mapY", 0.0))
    )
    for city in ordered_cities:
        if not bool(city.get("enabled", true)) or not bool(city.get("inBounds", false)):
            continue
        var major := String(city.get("type", "")) == "major_city"
        var tier := semantic_zoom_tier()
        if tier == "strategy" and not major:
            continue
        if zoom < 0.62 and not major:
            continue
        var position := Vector2(float(city.get("mapX", 0.0)), float(city.get("mapY", 0.0))) * world_map.tile_size
        _draw_city_settlement(position, major, String(city.get("type", "")))

func _draw_city_labels() -> void:
    if world_map == null:
        return
    var font := ThemeDB.fallback_font
    var tier := semantic_zoom_tier()
    if tier == "strategy":
        return
    var font_size := clampi(roundi(11.0 * clampf(zoom, 0.82, 1.15)), 9, 13)
    for city_value in world_map.cities:
        if city_value is not Dictionary or not bool(city_value.get("enabled", true)) or not bool(city_value.get("inBounds", false)):
            continue
        var major := String(city_value.get("type", "")) == "major_city"
        if zoom < 0.62 and not major:
            continue
        var position := Vector2(float(city_value.get("mapX", 0.0)), float(city_value.get("mapY", 0.0))) * world_map.tile_size
        draw_string(
            font,
            world_to_screen(position) + Vector2(10.0, -9.0),
            String(city_value.get("name", city_value.get("id", ""))),
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            font_size,
            Color("#f2ead8")
        )

func _draw_city_routes() -> void:
    if world_map == null or zoom < 0.28:
        return
    var city_positions: Dictionary = {}
    for city_value in world_map.cities:
        if city_value is Dictionary and bool(city_value.get("enabled", true)) and bool(city_value.get("inBounds", false)):
            city_positions[String(city_value.get("id", ""))] = Vector2(float(city_value.get("mapX", 0.0)), float(city_value.get("mapY", 0.0))) * world_map.tile_size
    for pair in CITY_ROUTE_PAIRS:
        var start_id := String(pair[0])
        var finish_id := String(pair[1])
        if not city_positions.has(start_id) or not city_positions.has(finish_id):
            continue
        var start: Vector2 = city_positions[start_id]
        var finish: Vector2 = city_positions[finish_id]
        draw_line(start + Vector2(1.8 / zoom, 2.8 / zoom), finish + Vector2(1.8 / zoom, 2.8 / zoom), Color(0.08, 0.12, 0.10, 0.32), 5.0 / zoom, true)
        draw_line(start, finish, Color(0.70, 0.56, 0.32, 0.68), 2.0 / zoom, true)

func _draw_city_settlement(position: Vector2, major: bool, city_type: String) -> void:
    var radius := (8.0 if major else 5.0) / zoom
    var shadow_offset := Vector2(3.8 / zoom, 5.1 / zoom)
    _draw_ground_ellipse(position + shadow_offset, Vector2(radius * 1.9, radius * 0.66), Color(0.02, 0.04, 0.03, 0.42))
    var base := PackedVector2Array([
        position + Vector2(-radius * 1.25, 0.0), position + Vector2(0.0, radius * 0.62),
        position + Vector2(radius * 1.25, 0.0), position + Vector2(0.0, -radius * 0.62)
    ])
    draw_colored_polygon(base, Color("#a7966b") if major else Color("#8d865f"))
    var height := radius * (1.9 if major else 1.45)
    var wall := PackedVector2Array([
        position + Vector2(-radius * 0.68, 0.0), position + Vector2(radius * 0.68, 0.0),
        position + Vector2(radius * 0.68, -height * 0.62), position + Vector2(-radius * 0.68, -height * 0.62)
    ])
    draw_colored_polygon(wall, Color("#d1bf8a") if major else Color("#b4a878"))
    var roof := PackedVector2Array([
        position + Vector2(-radius * 0.95, -height * 0.61), position + Vector2(0.0, -height),
        position + Vector2(radius * 0.95, -height * 0.61), position + Vector2(0.0, -height * 0.26)
    ])
    draw_colored_polygon(roof, Color("#934f3d") if major else Color("#714438"))
    if city_type == "port":
        draw_line(position + Vector2(radius * 1.15, radius * 0.28), position + Vector2(radius * 2.2, radius * 0.75), Color("#c5b784"), 1.1 / zoom, true)

func _draw_ground_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
    var points := PackedVector2Array()
    for point_index in range(16):
        var angle := TAU * float(point_index) / 16.0
        points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
    draw_colored_polygon(points, color)

func _draw_notification_markers() -> void:
    for marker in notification_markers:
        var position := Vector2.ZERO
        var found := false
        var city_id := String(marker.get("city_id", ""))
        if not city_id.is_empty():
            for city_value in world_map.cities:
                if city_value is Dictionary and String(city_value.get("id", "")) == city_id:
                    position = Vector2(float(city_value.get("mapX", 0.0)), float(city_value.get("mapY", 0.0))) * world_map.tile_size
                    found = true
                    break
        if not found:
            var province_id := int(marker.get("province_id", -1))
            if provinces.has(province_id):
                position = _province_center(provinces[province_id])
                found = true
        if not found:
            continue
        var screen_position := world_to_screen(position)
        var color := Color("#f0cb72")
        if String(marker.get("severity", "")) in ["warning", "urgent", "decision_required"]:
            color = Color("#ef6f61")
        draw_circle(screen_position + Vector2(0.0, -12.0), 7.0, color)
        draw_string(ThemeDB.fallback_font, screen_position + Vector2(-2.4, -8.2), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#1a1512"))

func _draw_region_ids() -> void:
    var anchors: Dictionary = world_map.manifest.get("province_anchors", {})
    for source_id in anchors.keys():
        var anchor: Dictionary = anchors[source_id]
        var position := Vector2(float(anchor.get("map_x", 0.0)), float(anchor.get("map_y", 0.0))) * world_map.tile_size
        draw_string(ThemeDB.fallback_font, world_to_screen(position), String(source_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#f4d58a"))

func _draw_map_debug_overlay() -> void:
    var mouse_world := _screen_to_world(get_local_mouse_position())
    var tile := world_map.tile_at_world(mouse_world)
    var lonlat := world_map.lonlat_from_world(mouse_world)
    var terrain_name := world_map.terrain_name(world_map.terrain_id(tile.x, tile.y))
    var lines := [
        "MAP DEBUG  F6: panel  F7: coast  F8: chunks  F9: regions  Home: overview",
        "tile %d,%d  lon %.3f°  lat %.3f°  terrain %s" % [tile.x, tile.y, lonlat.x, lonlat.y, terrain_name],
        "zoom %.3f  visible chunks %d  detailed tiles <= %d" % [zoom, visible_chunk_count, last_rendered_tile_count]
    ]
    draw_rect(Rect2(12, 12, 610, 72), Color(0.02, 0.04, 0.06, 0.88), true)
    for index in range(lines.size()):
        draw_string(ThemeDB.fallback_font, Vector2(22, 33 + index * 20), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d9e4e6"))

func go_to_lonlat(longitude: float, latitude: float, target_zoom := 1.2) -> void:
    if world_map == null:
        return
    zoom = clampf(target_zoom, min_zoom, max_zoom)
    _center_world(world_map.world_from_lonlat(longitude, latitude))
    _clamp_pan()
    _emit_camera_state()
    queue_redraw()

func export_world_map_png(path := "user://east_asia_world_map.png") -> Error:
    if world_map == null or world_map.overview_texture == null:
        return ERR_UNAVAILABLE
    return world_map.overview_texture.get_image().save_png(path)

func _draw_hex_tiles(numeric_range: Vector2) -> void:
    for tile_value in map_tiles:
        if tile_value is not Dictionary:
            continue
        var tile: Dictionary = tile_value
        var polygon := _tile_polygon(tile)
        if polygon.size() < 3:
            continue
        var is_water := bool(tile.get("water", false))
        var province_id := int(tile.get("province_id", -1))
        var fill: Color = TERRAIN_COLORS.get(String(tile.get("terrain", "deep_water")), Color("#102f42")) if is_water else _tile_land_color(tile, provinces.get(province_id, {}), numeric_range)
        var variation := int((int(tile.get("column", 0)) + int(tile.get("row", 0)) * 3) % 5) - 2
        fill = fill.lightened(float(variation) * 0.018) if variation > 0 else fill.darkened(float(-variation) * 0.018)
        draw_colored_polygon(polygon, fill)
        var border := Color(0.08, 0.11, 0.12, 0.14)
        var width := 0.4 / zoom
        if not is_water and bool(tile.get("boundary", false)):
            border = Color(0.08, 0.11, 0.12, 0.26)
            width = 0.72 / zoom
        if not is_water and (province_id in selected_province_ids or province_id == selected_province_id):
            border = Color("#f4d58a")
            width = 2.5 / zoom
        elif not is_water and province_id == _hovered_id:
            border = Color("#d9e4e6")
            width = 1.9 / zoom
        draw_polyline(polygon + PackedVector2Array([polygon[0]]), border, width, true)
        if not is_water and province_id in _peace_demands:
            draw_polyline(polygon + PackedVector2Array([polygon[0]]), Color("#f0a25b"), 3.2 / zoom, true)

func _tile_land_color(tile: Dictionary, province: Dictionary, numeric_range: Vector2) -> Color:
    if map_mode == "terrain":
        return TERRAIN_COLORS.get(String(tile.get("terrain", province.get("terrain", "plains"))), Color("#6c735f"))
    var color := _province_color(province, numeric_range)
    if bool(tile.get("coastal", false)):
        color = color.lerp(Color("#527787"), 0.08)
    return color

func _draw_region_labels() -> void:
    if zoom < 0.5:
        return
    var font := ThemeDB.fallback_font
    for label_value in map_labels:
        if label_value is not Dictionary:
            continue
        var label: Dictionary = label_value
        var position_value = label.get("position", Vector2.ZERO)
        var position := Vector2.ZERO
        if position_value is Vector2:
            position = position_value
        elif position_value is Array and position_value.size() >= 2:
            position = Vector2(float(position_value[0]), float(position_value[1]))
        var text := String(label.get("text", ""))
        var font_size := 19
        var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
        var color := Color(0.56, 0.76, 0.84, 0.55) if String(label.get("kind", "")) == "sea" else Color(0.91, 0.85, 0.69, 0.30)
        draw_string(font, world_to_screen(position) - Vector2(text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_grid() -> void:
    var start_x := int(floor(_world_rect.position.x / 80.0)) * 80
    var end_x := int(ceil(_world_rect.end.x / 80.0)) * 80
    var start_y := int(floor(_world_rect.position.y / 80.0)) * 80
    var end_y := int(ceil(_world_rect.end.y / 80.0)) * 80
    for x in range(start_x, end_x + 1, 80):
        draw_line(Vector2(x, start_y), Vector2(x, end_y), Color(0.20, 0.28, 0.33, 0.18), 1.0 / zoom)
    for y in range(start_y, end_y + 1, 80):
        draw_line(Vector2(start_x, y), Vector2(end_x, y), Color(0.20, 0.28, 0.33, 0.18), 1.0 / zoom)

func _draw_icons_and_labels() -> void:
    var label_min_zoom := 1.15 if show_battlefield_units else 0.72
    for id_value in provinces.keys():
        var id := int(id_value)
        var province: Dictionary = provinces[id]
        var center := world_to_screen(_province_center(province))
        var owner := String(province.get("owner", ""))
        var country: Dictionary = countries.get(owner, {})
        if int(country.get("capital_province", -1)) == id:
            _draw_star(center + Vector2(0.0, -18.0), 7.0, Color("#f0c66b"))
        if int(province.get("fort", 0)) > 0 and zoom >= 0.78:
            draw_rect(Rect2(center + Vector2(24.0, -12.0), Vector2(12.0, 12.0)), Color("#c5b28a"), true)
            draw_rect(Rect2(center + Vector2(24.0, -12.0), Vector2(12.0, 12.0)), Color("#3a3028"), false, 1.5)
        if zoom >= label_min_zoom:
            var label := String(province.get("name", "Province"))
            var font := ThemeDB.fallback_font
            var font_size := 14 if zoom >= 1.35 else 11
            var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
            draw_string(font, center - Vector2(text_size.x * 0.5, 0.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f2ead8"))
        if zoom >= 0.58 and not show_battlefield_units:
            var amount := int(armies.get(id, province.get("army", 0)))
            var badge := Rect2(center + Vector2(-17.0, 8.0), Vector2(34.0, 20.0))
            draw_style_box(_badge_style(), badge)
            draw_string(ThemeDB.fallback_font, badge.position + Vector2(7.0, 15.0), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _draw_battlefield_units() -> void:
    if not show_battlefield_units or world_map == null:
        return
    _battlefield_unit_renderer.render(self, army_groups, provinces, countries, world_map, zoom, army_groups.is_empty())
func _draw_command_paths() -> void:
    for path in _command_paths:
        var from_id := int(path.get("from_id", -1))
        var to_id := int(path.get("to_id", -1))
        if not provinces.has(from_id) or not provinces.has(to_id):
            continue
        var start := _province_center(provinces[from_id])
        var finish := _province_center(provinces[to_id])
        var color := Color("#6ed7dd") if String(path.get("type", "move")) == "move" else Color("#ef806f")
        draw_dashed_line(start, finish, color, 3.0 / zoom, 8.0 / zoom, true)
        var direction := (finish - start).normalized()
        var side := direction.orthogonal()
        var tip := finish - direction * 18.0
        var arrow := PackedVector2Array([finish, tip + side * 8.0, tip - side * 8.0])
        draw_colored_polygon(arrow, color)

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(10):
        var angle := -PI * 0.5 + float(i) * PI / 5.0
        var r := radius if i % 2 == 0 else radius * 0.44
        points.append(center + Vector2(cos(angle), sin(angle)) * r)
    draw_colored_polygon(points, color)

func _badge_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.06, 0.09, 0.12, 0.90)
    style.border_color = Color("#bda36f")
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    return style

func _province_color(province: Dictionary, robust_range: Vector2) -> Color:
    var owner := String(province.get("owner", ""))
    if map_mode == "political":
        return Color(String(countries.get(owner, {}).get("color", "#6b7378")))
    if map_mode == "relations":
        if owner == player_country_id: return Color("#4f8a72")
        if _at_war(player_country_id, owner): return Color("#9c4343")
        var relation := _relation(player_country_id, owner)
        if relation >= 25: return Color("#4d7f91")
        if relation <= -25: return Color("#8f6447")
        return Color("#777a70")
    if map_mode == "war":
        if owner == player_country_id: return Color("#3f7580")
        return Color("#9b3e3e") if _at_war(player_country_id, owner) else Color("#4e5458")
    if map_mode == "terrain":
        return TERRAIN_COLORS.get(String(province.get("terrain", "plains")), Color("#6c735f"))
    var value := _numeric_value(province, map_mode)
    var t := inverse_lerp(robust_range.x, robust_range.y, clampf(value, robust_range.x, robust_range.y))
    var low := Color("#27343b")
    var high := Color("#d2a75f")
    if map_mode in ["revolt"]:
        high = Color("#b34c45")
    elif map_mode in ["stability"]:
        high = Color("#4d9a78")
    elif map_mode == "fort":
        high = Color("#9e87bd")
    return low.lerp(high, t)

func _border_color(province: Dictionary) -> Color:
    var owner := String(province.get("owner", ""))
    if owner == player_country_id:
        return Color("#87b6ba")
    if _at_war(player_country_id, owner):
        return Color("#e0655b")
    if _relation(player_country_id, owner) >= 25:
        return Color("#6e9aa5")
    return Color("#252a2d")

func _numeric_values(mode: String) -> Array[float]:
    var result: Array[float] = []
    for province in provinces.values():
        result.append(_numeric_value(province, mode))
    result.sort()
    return result

func _robust_range(values: Array[float]) -> Vector2:
    if values.is_empty(): return Vector2(0, 1)
    var low_index := int(floor((values.size() - 1) * 0.08))
    var high_index := int(ceil((values.size() - 1) * 0.92))
    var low := values[low_index]
    var high := values[high_index]
    if is_equal_approx(low, high): high = low + 1.0
    return Vector2(low, high)

func _numeric_value(province: Dictionary, mode: String) -> float:
    match mode:
        "economy": return float(province.get("economy", 0))
        "population": return log(1.0 + float(province.get("population", 0)))
        "development": return float(province.get("development", 0))
        "manpower": return float(province.get("manpower", province.get("population", 0) * 0.2))
        "stability": return float(province.get("stability", countries.get(String(province.get("owner", "")), {}).get("stability", 50)))
        "revolt": return float(province.get("revolt_risk", maxf(0.0, 100.0 - float(province.get("stability", 70)))))
        "fort": return float(province.get("fort", 0))
        "supply": return clampf(float(province.get("development", 0)) * 18.0 + float(province.get("economy", 0)) - float(armies.get(int(province.get("id", -1)), 0)) * 0.01, 0.0, 100.0)
    return 0.0

func _polygon_for(province: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    for point in province.get("polygon", []):
        if point is Array and point.size() >= 2:
            result.append(Vector2(float(point[0]), float(point[1])))
        elif point is Vector2:
            result.append(point)
    return result

func _tile_polygon(tile: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    for point in tile.get("polygon", []):
        if point is Array and point.size() >= 2:
            result.append(Vector2(float(point[0]), float(point[1])))
        elif point is Vector2:
            result.append(point)
    return result
func _province_center(province: Dictionary) -> Vector2:
    var center_value = province.get("map_center", [])
    if center_value is Array and center_value.size() >= 2:
        return Vector2(float(center_value[0]), float(center_value[1]))
    if center_value is Vector2:
        return center_value
    var polygon := _polygon_for(province)
    if polygon.is_empty(): return Vector2.ZERO
    var total := Vector2.ZERO
    for point in polygon: total += point
    return total / float(polygon.size())

func _rebuild_spatial_index() -> void:
    _spatial_buckets.clear()
    _tile_spatial_buckets.clear()
    for id_value in provinces.keys():
        var id := int(id_value)
        var polygon := _polygon_for(provinces[id])
        if polygon.is_empty():
            continue
        _add_polygon_to_buckets(_spatial_buckets, id, polygon)
    for tile_index in range(map_tiles.size()):
        var tile_value = map_tiles[tile_index]
        if tile_value is not Dictionary:
            continue
        var polygon := _tile_polygon(tile_value)
        if polygon.is_empty():
            continue
        _add_polygon_to_buckets(_tile_spatial_buckets, tile_index, polygon)

func _add_polygon_to_buckets(buckets: Dictionary, value: int, polygon: PackedVector2Array) -> void:
    var bounds := Rect2(polygon[0], Vector2.ZERO)
    for point in polygon:
        bounds = bounds.expand(point)
    var min_cell := Vector2i(floori(bounds.position.x / PICK_BUCKET_SIZE), floori(bounds.position.y / PICK_BUCKET_SIZE))
    var max_cell := Vector2i(floori(bounds.end.x / PICK_BUCKET_SIZE), floori(bounds.end.y / PICK_BUCKET_SIZE))
    for x in range(min_cell.x, max_cell.x + 1):
        for y in range(min_cell.y, max_cell.y + 1):
            var cell := Vector2i(x, y)
            if not buckets.has(cell):
                buckets[cell] = []
            buckets[cell].append(value)

func _recalculate_world_rect() -> void:
    if world_map != null:
        _world_rect = world_map.world_rect()
        return
    var first := true
    if not map_tiles.is_empty():
        for tile_value in map_tiles:
            if tile_value is not Dictionary:
                continue
            for point in _tile_polygon(tile_value):
                if first:
                    _world_rect = Rect2(point, Vector2.ZERO)
                    first = false
                else:
                    _world_rect = _world_rect.expand(point)
        if not first:
            return
    for province in provinces.values():
        for point in _polygon_for(province):
            if first:
                _world_rect = Rect2(point, Vector2.ZERO)
                first = false
            else:
                _world_rect = _world_rect.expand(point)
    if first:
        _world_rect = Rect2(0, 0, 800, 560)
func _pair_key(a: String, b: String) -> String:
    return a + "|" + b if a < b else b + "|" + a

func _relation(a: String, b: String) -> int:
    if a == b: return 100
    return int(relations.get(_pair_key(a, b), 0))

func _at_war(a: String, b: String) -> bool:
    for war in wars:
        if not war is Dictionary: continue
        var attacker := String(war.get("attacker", ""))
        var defender := String(war.get("defender", ""))
        if (attacker == a and defender == b) or (attacker == b and defender == a): return true
    return false

func _tooltip_for(province_id: int) -> String:
    if province_id == -1 or not provinces.has(province_id): return ""
    var province: Dictionary = provinces[province_id]
    var owner := String(province.get("owner", ""))
    return "%s\n%s · 병력 %d\n인구 %s · 경제 %s · 요새 %s" % [String(province.get("name", "Province")), String(countries.get(owner, {}).get("name", owner)), int(armies.get(province_id, province.get("army", 0))), str(province.get("population", 0)), str(province.get("economy", 0)), str(province.get("fort", 0))]
