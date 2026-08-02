class_name StrategicMap
extends Control


signal province_selected(province_id: int)
signal selection_changed(province_ids: Array[int])
signal province_dropped(from_id: int, to_id: int)
signal command_target_selected(province_id: int)
signal city_selected(city_id: String)
signal city_selection_changed(city_id: String)
signal command_target_rejected(
    reason: String,
    source_id: int,
    target_id: int
)
signal interaction_feedback_changed(message: String)
signal tooltip_changed(text: String, screen_position: Vector2)
signal camera_changed(zoom: float)


enum InputState {
    IDLE,
    CHOOSING_MOVE_TARGET,
    CHOOSING_ATTACK_TARGET,
    SELECTING_PEACE_TERMS,
    DRAGGING_MAP,
    MODAL_OPEN
}


const MODE_LABELS := {
    "political": "정치",
    "relations": "외교 관계",
    "war": "전쟁",
    "economy": "경제",
    "population": "인구",
    "development": "개발도",
    "manpower": "인력",
    "stability": "안정도",
    "revolt": "반란 위험",
    "terrain": "지형",
    "fort": "요새",
    "supply": "보급"
}

const WORLD_LABELS := [
    ["중국 대륙", 105.0, 37.0, false],
    ["한반도", 127.3, 38.2, false],
    ["일본 열도", 137.8, 37.0, false],
    ["황해", 123.5, 35.0, true],
    ["동해", 132.7, 40.0, true],
    ["동중국해", 125.0, 28.0, true]
]

const WorldMapDataScript = preload("res://src/map/world_map_data.gd")
const StrategicMapGeometryScript = preload(
    "res://src/map/strategic_map_geometry.gd"
)
const StrategicMapPaletteScript = preload(
    "res://src/map/strategic_map_palette.gd"
)

const PICK_BUCKET_SIZE := 160.0
const MAP_DRAG_THRESHOLD := 8.0
const CITY_PICK_RADIUS_SCREEN := 10.0
const MINOR_CITY_MIN_ZOOM := 0.24
const CITY_LABEL_MIN_ZOOM := 0.64
const ALL_CITY_LABEL_MIN_ZOOM := 1.10
const DEFAULT_PLAY_LONGITUDE := 126.9780
const DEFAULT_PLAY_LATITUDE := 37.5665
const DEFAULT_PLAY_ZOOM := 0.72


# Runtime snapshot ------------------------------------------------------------

var provinces: Dictionary = {}
var map_tiles: Array = []
var map_labels: Array = []
var world_map: WorldMapData
var world_map_id := ""
var countries: Dictionary = {}
var armies: Dictionary = {}
var relations: Dictionary = {}
var wars: Array = []
var player_country_id := ""
var _visual_revision := 0
var _last_snapshot_turn := -1
var _loaded_world_map_id := ""


# Selection and command interaction -----------------------------------------

var selected_province_id := -1
var selected_province_ids: Array[int] = []
var command_source_id := -1
var map_mode := "political"
var input_state: InputState = InputState.IDLE

var _selection_dragging := false
var _selection_origin := Vector2.ZERO
var _selection_current := Vector2.ZERO
var _selection_additive := false
var _command_drag := false
var _drag_source_id := -1
var _command_paths: Array[Dictionary] = []
var _peace_demands: Array[int] = []
var _hovered_id := -1
var selected_city_id := ""
var _city_capital_ids: Dictionary = {}
var _city_warning_ids: Dictionary = {}
var _city_navigation_order: Array[String] = []
var _command_valid_target_ids: Dictionary = {}
var _command_target_reasons: Dictionary = {}


# Camera and drag state -------------------------------------------------------

var zoom := 1.0
var pan := Vector2.ZERO
var min_zoom := 0.05
var max_zoom := 8.0

var _drag_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _drag_button := MOUSE_BUTTON_NONE
var _did_drag := false
var _state_before_drag: InputState = InputState.IDLE
var _drag_cursor_active := false


# Rendering and spatial indexes ---------------------------------------------

var _world_rect := Rect2(0, 0, 800, 560)
var _spatial_buckets: Dictionary = {}
var _tile_spatial_buckets: Dictionary = {}
var _selection_center_buckets: Dictionary = {}
var _screen_text_commands: Array[Dictionary] = []
var _city_label_slots: Dictionary = {}

var spatial_index_rebuild_count := 0
var snapshot_apply_time_us := 0
var turn_update_time_us := 0
var map_mode_switch_time_us := 0
var hover_pick_total_time_us := 0
var hover_pick_max_time_us := 0
var hover_pick_count := 0

var debug_map_enabled := false
var show_chunk_boundaries := false
var show_coast_highlight := false
var show_region_ids := false
var visible_chunk_count := 0
var last_rendered_tile_count := 0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    clip_contents = true
    resized.connect(_clamp_pan)


# Public map contract ---------------------------------------------------------

func set_snapshot(snapshot: Dictionary) -> void:
    var started_at := Time.get_ticks_usec()
    var next_provinces := _shallow_dictionary(snapshot.get("provinces", {}))
    var next_map_tiles := _shallow_array(snapshot.get("map_tiles", []))
    var next_map_labels := _shallow_array(snapshot.get("map_labels", []))
    var next_countries := _shallow_dictionary(snapshot.get("countries", {}))
    var next_armies := _shallow_dictionary(snapshot.get("armies", {}))
    var next_relations := _shallow_dictionary(snapshot.get("relations", {}))
    var next_wars := _shallow_array(snapshot.get("wars", []))
    var next_player_country_id := String(snapshot.get("player_country_id", ""))
    var next_world_map_id := String(snapshot.get("world_map_id", ""))
    var next_turn := int(snapshot.get("turn", -1))
    # Dictionary equality is exact for the snapshot value graph and avoids the
    # allocation-heavy JSON serialization that used to dominate no-op syncs.
    var geometry_changed := next_world_map_id != world_map_id
    if next_world_map_id.is_empty():
        geometry_changed = (
            geometry_changed
            or next_map_tiles != map_tiles
        )
    var visual_changed := (
        next_countries != countries
        or next_provinces != provinces
        or next_armies != armies
        or next_relations != relations
        or next_wars != wars
        or next_player_country_id != player_country_id
        or next_map_labels != map_labels
    )

    provinces = next_provinces
    map_tiles = next_map_tiles
    map_labels = next_map_labels
    countries = next_countries
    armies = next_armies
    relations = next_relations
    wars = next_wars
    player_country_id = next_player_country_id
    world_map_id = next_world_map_id

    var runtime_mapping_changed := _load_world_map_if_needed()
    if geometry_changed or runtime_mapping_changed:
        _recalculate_world_rect()
        _rebuild_spatial_index()
    if visual_changed or runtime_mapping_changed:
        _visual_revision += 1

    _prune_invalid_selections()
    snapshot_apply_time_us = Time.get_ticks_usec() - started_at
    if _last_snapshot_turn != -1 and next_turn != _last_snapshot_turn:
        turn_update_time_us = snapshot_apply_time_us
    _last_snapshot_turn = next_turn

    if geometry_changed or visual_changed or runtime_mapping_changed:
        queue_redraw()


func set_mode(value: String) -> void:
    if not MODE_LABELS.has(value) or map_mode == value:
        return
    var started_at := Time.get_ticks_usec()
    map_mode = value
    map_mode_switch_time_us = Time.get_ticks_usec() - started_at
    queue_redraw()


func set_command_target_validation(
    valid_target_ids: Array,
    rejection_reasons: Dictionary = {}
) -> void:
    _command_valid_target_ids.clear()
    for province_id_value in valid_target_ids:
        _command_valid_target_ids[int(province_id_value)] = true
    _command_target_reasons = rejection_reasons.duplicate(false)
    queue_redraw()


func set_city_highlights(
    capital_city_ids: Array,
    warning_city_ids: Array
) -> void:
    _city_capital_ids = _id_set(capital_city_ids)
    _city_warning_ids = _id_set(warning_city_ids)
    queue_redraw()


func set_city_navigation_order(city_ids: Array) -> void:
    _city_navigation_order.clear()
    for city_id_value in city_ids:
        var city_id := String(city_id_value)
        if not city_id.is_empty() and city_id not in _city_navigation_order:
            _city_navigation_order.append(city_id)


func select_city(city_id: String, center_camera := true) -> bool:
    if world_map == null or world_map.city_record(city_id).is_empty():
        return false

    selected_city_id = city_id
    city_selected.emit(city_id)
    city_selection_changed.emit(city_id)
    if center_camera:
        focus_city(city_id)
    else:
        queue_redraw()
    return true


func clear_city_selection() -> void:
    if selected_city_id.is_empty():
        return
    selected_city_id = ""
    city_selection_changed.emit("")
    queue_redraw()


func select_next_city(direction := 1) -> String:
    var city_ids := _resolved_city_navigation_order()
    if city_ids.is_empty():
        return ""

    var step := 1 if direction >= 0 else -1
    var selected_index := city_ids.find(selected_city_id)
    if selected_index == -1:
        selected_index = -1 if step > 0 else 0
    var next_index := posmod(selected_index + step, city_ids.size())
    var next_city_id := city_ids[next_index]
    select_city(next_city_id, true)
    return next_city_id


func focus_city(city_id: String, target_zoom := -1.0) -> bool:
    if world_map == null or world_map.city_record(city_id).is_empty():
        return false
    if target_zoom > 0.0:
        zoom = clampf(target_zoom, min_zoom, max_zoom)
    pan = StrategicMapGeometryScript.focus_pan(
        size,
        world_map.city_position_for(city_id),
        zoom
    )
    _clamp_pan()
    camera_changed.emit(zoom)
    queue_redraw()
    return true


func frame_play_area() -> void:
    if world_map == null:
        frame_world()
        return
    go_to_lonlat(
        DEFAULT_PLAY_LONGITUDE,
        DEFAULT_PLAY_LATITUDE,
        DEFAULT_PLAY_ZOOM
    )


func city_pick_radius_for_zoom(value: float = zoom) -> float:
    return CITY_PICK_RADIUS_SCREEN / maxf(value, 0.001)


func performance_metrics() -> Dictionary:
    return {
        "snapshot_apply_us": snapshot_apply_time_us,
        "turn_update_us": turn_update_time_us,
        "spatial_index_rebuilds": spatial_index_rebuild_count,
        "visual_revision": _visual_revision,
        "map_mode_switch_us": map_mode_switch_time_us,
        "hover_pick_count": hover_pick_count,
        "hover_pick_average_us": (
            float(hover_pick_total_time_us) / hover_pick_count
            if hover_pick_count > 0 else 0.0
        ),
        "hover_pick_max_us": hover_pick_max_time_us,
        "visible_chunks": visible_chunk_count,
        "rendered_tiles": last_rendered_tile_count,
        "world_map": world_map.performance_metrics() if world_map != null else {}
    }


func _shallow_dictionary(value: Variant) -> Dictionary:
    if value is Dictionary:
        return value.duplicate(false)
    return {}


func _shallow_array(value: Variant) -> Array:
    if value is Array:
        return value.duplicate(false)
    return []


func _id_set(values: Array) -> Dictionary:
    var result: Dictionary = {}
    for value in values:
        var id := String(value)
        if not id.is_empty():
            result[id] = true
    return result


func _resolved_city_navigation_order() -> Array[String]:
    if world_map == null:
        return []
    var result: Array[String] = []
    for city_id in _city_navigation_order:
        if not world_map.city_record(city_id).is_empty():
            result.append(city_id)
    if not result.is_empty():
        return result
    return world_map.city_ids_in_display_order()


func _prune_invalid_selections() -> void:
    var retained_provinces: Array[int] = []
    for province_id in selected_province_ids:
        if provinces.has(province_id):
            retained_provinces.append(province_id)
    selected_province_ids = retained_provinces
    selected_province_id = (
        selected_province_ids.back()
        if not selected_province_ids.is_empty() else -1
    )
    if world_map != null and not selected_city_id.is_empty():
        if world_map.city_record(selected_city_id).is_empty():
            selected_city_id = ""


func mode_label() -> String:
    return String(MODE_LABELS.get(map_mode, map_mode))


func set_interaction_state(value: InputState, source_id: int = -1) -> void:
    input_state = value
    command_source_id = source_id
    if value == InputState.IDLE:
        _command_valid_target_ids.clear()
        _command_target_reasons.clear()
    queue_redraw()


func clear_interaction() -> void:
    input_state = InputState.IDLE
    command_source_id = -1
    _peace_demands.clear()
    _command_valid_target_ids.clear()
    _command_target_reasons.clear()
    queue_redraw()


func set_command_paths(paths: Array) -> void:
    _command_paths.clear()
    for path_value in paths:
        if path_value is Dictionary:
            _command_paths.append(path_value.duplicate(true))
    queue_redraw()


func set_peace_demands(province_ids: Array[int]) -> void:
    _peace_demands = province_ids.duplicate()
    queue_redraw()


func set_selected_provinces(province_ids: Array[int]) -> void:
    selected_province_ids = province_ids.duplicate()
    if selected_province_ids.is_empty():
        selected_province_id = -1
    else:
        selected_province_id = selected_province_ids.back()

    selection_changed.emit(selected_province_ids.duplicate())
    if selected_province_id != -1:
        province_selected.emit(selected_province_id)
    queue_redraw()


func frame_world() -> void:
    var camera := StrategicMapGeometryScript.frame_world(
        size,
        _world_rect,
        min_zoom
    )
    if camera.is_empty():
        return

    zoom = float(camera.get("zoom", zoom))
    pan = Vector2(camera.get("pan", pan))
    _clamp_pan()
    queue_redraw()


func focus_province(province_id: int) -> void:
    var province: Dictionary = provinces.get(province_id, {})
    if province.is_empty():
        return

    pan = StrategicMapGeometryScript.focus_pan(
        size,
        _province_center(province),
        zoom
    )
    _clamp_pan()
    queue_redraw()


func go_to_lonlat(
    longitude: float,
    latitude: float,
    target_zoom: float = 1.2
) -> void:
    if world_map == null:
        return

    zoom = clampf(target_zoom, min_zoom, max_zoom)
    pan = StrategicMapGeometryScript.focus_pan(
        size,
        world_map.world_from_lonlat(longitude, latitude),
        zoom
    )
    _clamp_pan()
    queue_redraw()


func nudge_camera(delta: Vector2) -> void:
    pan += delta
    _clamp_pan()
    queue_redraw()


func export_world_map_png(
    path: String = "user://east_asia_world_map.png"
) -> Error:
    if world_map == null or world_map.overview_texture == null:
        return ERR_UNAVAILABLE
    return world_map.overview_texture.get_image().save_png(path)


# Input ----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
    if input_state == InputState.MODAL_OPEN:
        accept_event()
        return

    if event is InputEventKey and event.pressed:
        _handle_key_input(event)
    elif event is InputEventMouseButton:
        _handle_mouse_button(event)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event)


func _handle_key_input(event: InputEventKey) -> void:
    match event.keycode:
        KEY_F6:
            debug_map_enabled = not debug_map_enabled
        KEY_F7:
            show_coast_highlight = not show_coast_highlight
        KEY_F8:
            show_chunk_boundaries = not show_chunk_boundaries
        KEY_F9:
            show_region_ids = not show_region_ids
        KEY_HOME:
            frame_world()
            accept_event()
            return
        _:
            return

    queue_redraw()
    accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
    if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        _zoom_at(event.position, 1.14)
        accept_event()
        return

    if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        _zoom_at(event.position, 1.0 / 1.14)
        accept_event()
        return

    if event.button_index == MOUSE_BUTTON_LEFT:
        _handle_left_button(event)
        accept_event()
        return

    if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
        if event.pressed:
            _begin_map_drag(event.button_index, event.position)
        else:
            _finish_map_drag(event.button_index, event.position)
        accept_event()


func _handle_left_button(event: InputEventMouseButton) -> void:
    if event.pressed:
        var province_id := _province_at(event.position)
        if (
            event.ctrl_pressed
            and province_id != -1
            and input_state == InputState.IDLE
        ):
            _command_drag = true
            _drag_source_id = province_id
            _selection_origin = event.position
            _selection_current = event.position
            _set_drag_cursor(Control.CURSOR_CROSS)
            queue_redraw()
            return

        if event.shift_pressed and input_state == InputState.IDLE:
            _selection_dragging = true
            _selection_additive = true
            _selection_origin = event.position
            _selection_current = event.position
            _set_drag_cursor(Control.CURSOR_CROSS)
            queue_redraw()
            return

        _selection_additive = event.shift_pressed
        _begin_map_drag(event.button_index, event.position)
        return

    if _selection_dragging:
        _finish_selection(event.position)
        _set_drag_cursor(Control.CURSOR_ARROW)
        return

    if _command_drag:
        var target_id := _province_at(event.position)
        if target_id != -1 and target_id != _drag_source_id:
            province_dropped.emit(_drag_source_id, target_id)
        elif target_id == _drag_source_id:
            command_target_rejected.emit(
                "??? ?? ????? ??? ? ? ????.",
                _drag_source_id,
                target_id
            )
        else:
            command_target_rejected.emit(
                "?? ?? ?? ??? ??? ?? ? ????.",
                _drag_source_id,
                target_id
            )
        _command_drag = false
        _drag_source_id = -1
        _set_drag_cursor(Control.CURSOR_ARROW)
        queue_redraw()
        return

    _finish_map_drag(event.button_index, event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
    if _command_drag:
        _selection_current = event.position
        _update_hovered_province(_province_at(event.position), event.global_position)
        queue_redraw()
        accept_event()
        return

    if _selection_dragging:
        _selection_current = event.position
        queue_redraw()
        accept_event()
        return

    if _drag_button != MOUSE_BUTTON_NONE:
        _continue_map_drag(event.position)
        accept_event()
        return

    if _update_hovered_province(
        _province_at(event.position),
        event.global_position
    ):
        queue_redraw()


func _update_hovered_province(
    next_hovered_id: int,
    global_position: Vector2
) -> bool:
    if next_hovered_id == _hovered_id:
        return false
    _hovered_id = next_hovered_id
    tooltip_changed.emit(_tooltip_for(next_hovered_id), global_position)
    return true


func _begin_map_drag(button: MouseButton, position: Vector2) -> void:
    _drag_button = button
    _drag_origin = position
    _pan_origin = pan
    _did_drag = false


func _continue_map_drag(position: Vector2) -> void:
    if not _did_drag and position.distance_to(_drag_origin) >= MAP_DRAG_THRESHOLD:
        _state_before_drag = input_state
        _did_drag = true
        input_state = InputState.DRAGGING_MAP
        _set_drag_cursor(Control.CURSOR_DRAG)
        interaction_feedback_changed.emit("?? ?? ?")

    if not _did_drag:
        return

    pan = _pan_origin + position - _drag_origin
    _clamp_pan()
    queue_redraw()


func _finish_map_drag(button: MouseButton, position: Vector2) -> void:
    if _drag_button != button:
        return

    var did_drag := _did_drag
    _drag_button = MOUSE_BUTTON_NONE
    _set_drag_cursor(Control.CURSOR_ARROW)

    if input_state == InputState.DRAGGING_MAP:
        input_state = _state_before_drag

    if did_drag:
        queue_redraw()
        return

    if button == MOUSE_BUTTON_RIGHT:
        _handle_target_click(_province_at(position))
        return

    if button == MOUSE_BUTTON_LEFT:
        var province_id := _province_at(position)
        if input_state in [
            InputState.CHOOSING_MOVE_TARGET,
            InputState.CHOOSING_ATTACK_TARGET,
            InputState.SELECTING_PEACE_TERMS
        ]:
            _handle_target_click(province_id)
            return

        var clicked_city := _city_at(position)
        if not clicked_city.is_empty():
            select_city(clicked_city, false)

        _selection_origin = position
        _finish_selection(position)


func _finish_selection(position: Vector2) -> void:
    _selection_current = position
    _selection_dragging = false

    var next_selection: Array[int] = []
    if _selection_additive:
        next_selection.assign(selected_province_ids)

    if _selection_origin.distance_to(position) < MAP_DRAG_THRESHOLD:
        _toggle_clicked_province(position, next_selection)
    else:
        _append_provinces_in_rectangle(position, next_selection)

    set_selected_provinces(next_selection)


func _toggle_clicked_province(
    position: Vector2,
    next_selection: Array[int]
) -> void:
    var province_id := _province_at(position)
    if province_id == -1:
        return

    if _selection_additive and province_id in next_selection:
        next_selection.erase(province_id)
    elif province_id not in next_selection:
        next_selection.append(province_id)


func _append_provinces_in_rectangle(
    position: Vector2,
    next_selection: Array[int]
) -> void:
    var selection_rect := Rect2(
        _selection_origin,
        position - _selection_origin
    ).abs()
    var world_selection_rect := Rect2(
        _screen_to_world(selection_rect.position),
        selection_rect.size / zoom
    ).abs()
    var minimum_cell := _selection_bucket_for(world_selection_rect.position)
    var maximum_cell := _selection_bucket_for(world_selection_rect.end)

    for column in range(minimum_cell.x, maximum_cell.x + 1):
        for row in range(minimum_cell.y, maximum_cell.y + 1):
            for province_id_value in _selection_center_buckets.get(
                Vector2i(column, row),
                []
            ):
                var province_id := int(province_id_value)
                if not provinces.has(province_id):
                    continue
                var screen_center := (
                    _province_center(provinces[province_id]) * zoom + pan
                )
                if (
                    selection_rect.has_point(screen_center)
                    and province_id not in next_selection
                ):
                    next_selection.append(province_id)


func _handle_target_click(province_id: int) -> void:
    var is_target_selection := input_state in [
        InputState.CHOOSING_MOVE_TARGET,
        InputState.CHOOSING_ATTACK_TARGET,
        InputState.SELECTING_PEACE_TERMS
    ]
    if is_target_selection:
        var rejection_reason := _command_target_rejection_reason(province_id)
        if not rejection_reason.is_empty():
            command_target_rejected.emit(
                rejection_reason,
                command_source_id,
                province_id
            )
            interaction_feedback_changed.emit(rejection_reason)
            queue_redraw()
            return

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


func _command_target_rejection_reason(province_id: int) -> String:
    if province_id == -1:
        return "?? ?? ?? ??? ??? ?? ? ????."
    if province_id == command_source_id and command_source_id != -1:
        return "??? ?? ????? ??? ? ? ????."
    if (
        not _command_valid_target_ids.is_empty()
        and not _command_valid_target_ids.has(province_id)
    ):
        return String(
            _command_target_reasons.get(
                province_id,
                "?? ??? ?? ??? ????."
            )
        )
    return ""


func _set_drag_cursor(cursor_shape: int) -> void:
    mouse_default_cursor_shape = cursor_shape
    _drag_cursor_active = cursor_shape != Control.CURSOR_ARROW


# Camera calculations --------------------------------------------------------

func _zoom_at(screen_point: Vector2, factor: float) -> void:
    var camera := StrategicMapGeometryScript.zoom_at(
        screen_point,
        factor,
        pan,
        zoom,
        min_zoom,
        max_zoom
    )
    zoom = float(camera.get("zoom", zoom))
    pan = Vector2(camera.get("pan", pan))
    _clamp_pan()
    camera_changed.emit(zoom)
    queue_redraw()


func _clamp_pan() -> void:
    pan = StrategicMapGeometryScript.clamp_pan(
        pan,
        size,
        _world_rect,
        zoom
    )


func _screen_to_world(point: Vector2) -> Vector2:
    return StrategicMapGeometryScript.screen_to_world(point, pan, zoom)


# Picking --------------------------------------------------------------------

func _city_at(screen_point: Vector2) -> String:
    var started_at := Time.get_ticks_usec()
    if world_map == null:
        _record_hover_pick(Time.get_ticks_usec() - started_at)
        return ""

    var city := world_map.city_at_world(
        _screen_to_world(screen_point),
        city_pick_radius_for_zoom()
    )
    _record_hover_pick(Time.get_ticks_usec() - started_at)
    return String(city.get("id", ""))


func _province_at(screen_point: Vector2) -> int:
    var started_at := Time.get_ticks_usec()
    var world_position := _screen_to_world(screen_point)
    var province_id := -1

    if world_map != null:
        var tile := world_map.tile_at_world(world_position)
        province_id = world_map.province_id(tile.x, tile.y)
    else:
        var cell := Vector2i(
            floori(world_position.x / PICK_BUCKET_SIZE),
            floori(world_position.y / PICK_BUCKET_SIZE)
        )
        if not map_tiles.is_empty():
            province_id = _province_from_tile_candidates(world_position, cell)
        else:
            province_id = _province_from_polygon_candidates(world_position, cell)

    _record_hover_pick(Time.get_ticks_usec() - started_at)
    return province_id


func _record_hover_pick(elapsed_us: int) -> void:
    hover_pick_count += 1
    hover_pick_total_time_us += elapsed_us
    hover_pick_max_time_us = maxi(hover_pick_max_time_us, elapsed_us)


func _province_from_tile_candidates(
    world_position: Vector2,
    cell: Vector2i
) -> int:
    var tile_candidates: Array = _tile_spatial_buckets.get(cell, [])
    for tile_index_value in tile_candidates:
        var tile: Dictionary = map_tiles[int(tile_index_value)]
        var polygon := _tile_polygon(tile)
        if (
            polygon.size() >= 3
            and Geometry2D.is_point_in_polygon(world_position, polygon)
        ):
            if bool(tile.get("water", false)):
                return -1
            return int(tile.get("province_id", -1))
    return -1


func _province_from_polygon_candidates(
    world_position: Vector2,
    cell: Vector2i
) -> int:
    var candidates: Array = _spatial_buckets.get(cell, provinces.keys())
    for province_id_value in candidates:
        var province_id := int(province_id_value)
        var polygon := _polygon_for(provinces[province_id])
        if (
            polygon.size() >= 3
            and Geometry2D.is_point_in_polygon(world_position, polygon)
        ):
            return province_id
    return -1


# Rendering entrypoint -------------------------------------------------------

func _draw() -> void:
    _screen_text_commands.clear()
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0c1821"))

    draw_set_transform(pan, 0.0, Vector2(zoom, zoom))
    var numeric_range := _robust_range(_numeric_values(map_mode))
    _draw_map_body(numeric_range)
    _draw_command_paths()
    _draw_icons_and_labels()

    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    _draw_screen_text_commands()
    _draw_active_drag_feedback()

    if debug_map_enabled and world_map != null:
        _draw_map_debug_overlay()


func _draw_map_body(numeric_range: Vector2) -> void:
    if world_map != null:
        _draw_world_map(numeric_range)
    elif map_tiles.is_empty():
        _draw_grid()
        _draw_province_polygons(numeric_range)
    else:
        _draw_hex_tiles(numeric_range)
        _draw_region_labels()


func _draw_active_drag_feedback() -> void:
    if _selection_dragging:
        var selection_rect := Rect2(
            _selection_origin,
            _selection_current - _selection_origin
        ).abs()
        draw_rect(
            selection_rect,
            Color(0.35, 0.78, 0.88, 0.16),
            true
        )
        draw_rect(selection_rect, Color("#6ec7d8"), false, 2.0)

    if _command_drag:
        draw_dashed_line(
            _selection_origin,
            _selection_current,
            Color("#f0c66b"),
            3.0,
            10.0,
            true
        )


# Screen-space text ----------------------------------------------------------

func _queue_map_text(
    world_position: Vector2,
    text: String,
    font_size: int,
    color: Color,
    screen_offset: Vector2 = Vector2.ZERO,
    centered: bool = false
) -> void:
    if text.is_empty():
        return

    _screen_text_commands.append({
        "world_position": world_position,
        "text": text,
        "font_size": font_size,
        "color": color,
        "screen_offset": screen_offset,
        "centered": centered
    })


func _draw_screen_text_commands() -> void:
    var font := ThemeDB.fallback_font
    var visible_bounds := Rect2(Vector2.ZERO, size).grow(256.0)

    for command in _screen_text_commands:
        var screen_position := (
            Vector2(command.get("world_position", Vector2.ZERO)) * zoom
            + pan
            + Vector2(command.get("screen_offset", Vector2.ZERO))
        )
        if not visible_bounds.has_point(screen_position):
            continue

        var text := String(command.get("text", ""))
        var font_size := int(command.get("font_size", 14))
        if bool(command.get("centered", false)):
            var text_size := font.get_string_size(
                text,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                font_size
            )
            screen_position.x -= text_size.x * 0.5

        draw_string(
            font,
            screen_position,
            text,
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            font_size,
            Color(command.get("color", Color.WHITE))
        )


# Geographic world-map rendering -------------------------------------------

func _draw_world_map(_numeric_range: Vector2) -> void:
    var world_view := Rect2(
        _screen_to_world(Vector2.ZERO),
        size / zoom
    ).grow(world_map.tile_size * 2.0)
    var chunks := world_map.visible_chunk_bounds(world_view)

    visible_chunk_count = chunks.size.x * chunks.size.y
    last_rendered_tile_count = (
        visible_chunk_count
        * world_map.chunk_size
        * world_map.chunk_size
    )
    _city_label_slots.clear()

    if zoom < 0.32 and world_map.overview_texture != null:
        _draw_world_overview()
    else:
        _draw_visible_world_chunks(chunks)
        _draw_world_selection(world_view)
        if show_coast_highlight:
            _draw_coast_highlight(world_view)

    _draw_world_labels(world_view)
    if show_region_ids:
        _draw_region_ids()
    _draw_cities(world_view)


func _draw_world_overview() -> void:
    var overview := world_map.overview_texture_for_mode(
        map_mode,
        countries,
        provinces,
        player_country_id,
        relations,
        wars,
        _visual_revision
    )
    draw_texture_rect(overview, world_map.world_rect(), false)
    last_rendered_tile_count = 0


func _draw_visible_world_chunks(chunks: Rect2i) -> void:
    var chunk_world_size := (
        float(world_map.chunk_size) * world_map.tile_size
    )

    for chunk_y in range(chunks.position.y, chunks.end.y):
        for chunk_x in range(chunks.position.x, chunks.end.x):
            var texture := world_map.chunk_texture(
                chunk_x,
                chunk_y,
                map_mode,
                countries,
                provinces,
                player_country_id,
                relations,
                wars,
                _visual_revision
            )
            var rect := Rect2(
                Vector2(float(chunk_x), float(chunk_y)) * chunk_world_size,
                Vector2.ONE * chunk_world_size
            )
            draw_texture_rect(texture, rect, false)

            if show_chunk_boundaries:
                draw_rect(
                    rect,
                    Color(0.95, 0.75, 0.25, 0.72),
                    false,
                    1.0 / zoom
                )


func _draw_world_selection(world_view: Rect2) -> void:
    var is_target_selection := input_state in [
        InputState.CHOOSING_MOVE_TARGET,
        InputState.CHOOSING_ATTACK_TARGET,
        InputState.SELECTING_PEACE_TERMS
    ]
    if (
        selected_province_ids.is_empty()
        and _hovered_id == -1
        and (not is_target_selection or command_source_id == -1)
    ):
        return

    var tile_minimum := world_map.tile_at_world(world_view.position)
    var tile_maximum := world_map.tile_at_world(world_view.end)

    for row in range(
        maxi(0, tile_minimum.y),
        mini(world_map.height - 1, tile_maximum.y) + 1
    ):
        for column in range(
            maxi(0, tile_minimum.x),
            mini(world_map.width - 1, tile_maximum.x) + 1
        ):
            var province_id := world_map.province_id(column, row)
            var color := Color.TRANSPARENT
            if is_target_selection and province_id == command_source_id:
                color = Color(0.30, 0.72, 0.96, 0.52)
            elif province_id in selected_province_ids:
                color = Color(0.96, 0.83, 0.45, 0.43)
            elif province_id == _hovered_id:
                color = _hover_overlay_color(province_id, is_target_selection)

            if is_zero_approx(color.a):
                continue
            draw_rect(
                Rect2(
                    Vector2(column, row) * world_map.tile_size,
                    Vector2.ONE * world_map.tile_size
                ),
                color,
                false,
                1.5 / zoom
            )


func _hover_overlay_color(
    province_id: int,
    is_target_selection: bool
) -> Color:
    if not is_target_selection:
        return Color(0.86, 0.91, 0.92, 0.28)
    if _command_target_rejection_reason(province_id).is_empty():
        return Color(0.36, 0.88, 0.62, 0.58)
    return Color(0.94, 0.35, 0.31, 0.60)


func _draw_coast_highlight(world_view: Rect2) -> void:
    var tile_minimum := world_map.tile_at_world(world_view.position)
    var tile_maximum := world_map.tile_at_world(world_view.end)

    for row in range(
        maxi(0, tile_minimum.y),
        mini(world_map.height - 1, tile_maximum.y) + 1
    ):
        for column in range(
            maxi(0, tile_minimum.x),
            mini(world_map.width - 1, tile_maximum.x) + 1
        ):
            if world_map.terrain_id(column, row) != 3:
                continue

            draw_rect(
                Rect2(
                    Vector2(column, row) * world_map.tile_size,
                    Vector2.ONE * world_map.tile_size
                ),
                Color(1.0, 0.3, 0.25, 0.58),
                false,
                1.0 / zoom
            )


func _draw_world_labels(world_view: Rect2) -> void:
    if zoom < 0.16:
        return

    var label_view := world_view.grow(160.0 / zoom)
    for label in WORLD_LABELS:
        var position := world_map.world_from_lonlat(
            float(label[1]),
            float(label[2])
        )
        if not label_view.has_point(position):
            continue
        var color := Color(0.94, 0.88, 0.68, 0.56)
        if bool(label[3]):
            color = Color(0.60, 0.80, 0.88, 0.62)
        _queue_map_text(
            position,
            String(label[0]),
            18,
            color,
            Vector2.ZERO,
            true
        )


func _draw_cities(world_view: Rect2) -> void:
    var city_view := world_view.grow(city_pick_radius_for_zoom() * 2.0)
    for city_value in world_map.cities_in_world_rect(city_view):
        var city: Dictionary = city_value
        var city_id := String(city.get("id", ""))
        var is_major_city := String(city.get("type", "")) == "major_city"
        var is_capital := _city_capital_ids.has(city_id)
        var is_warning := _city_warning_ids.has(city_id)
        var is_selected := city_id == selected_city_id
        if (
            zoom < MINOR_CITY_MIN_ZOOM
            and not is_major_city
            and not is_capital
            and not is_warning
            and not is_selected
        ):
            continue

        var position := world_map.city_position_for(city_id)
        var radius := (4.0 if is_major_city else 2.6) / zoom
        if is_capital:
            draw_circle(position, radius * 1.95, Color(0.95, 0.72, 0.24, 0.24))
            _draw_star(position + Vector2(0.0, -radius * 1.15), radius * 0.95, Color("#f5c85c"))
        if is_warning:
            draw_arc(
                position,
                radius * 1.78,
                0.0,
                TAU,
                16,
                Color("#ef7564"),
                1.8 / zoom
            )
        if is_selected:
            draw_arc(
                position,
                radius * 1.48,
                0.0,
                TAU,
                16,
                Color("#75d7e7"),
                1.7 / zoom
            )

        draw_circle(position, radius, Color("#f4d58a"))
        draw_arc(
            position,
            radius,
            0.0,
            TAU,
            12,
            Color("#1c1e1f"),
            1.2 / zoom
        )

        var show_label := (
            zoom >= ALL_CITY_LABEL_MIN_ZOOM
            or (
                zoom >= CITY_LABEL_MIN_ZOOM
                and (is_major_city or is_capital or is_warning or is_selected)
            )
            or is_selected
        )
        if show_label and _reserve_city_label_slot(position, is_selected):
            _queue_map_text(
                position,
                String(city.get("name", city_id)),
                12,
                Color("#f2ead8"),
                Vector2(6.0, -3.0)
            )


func _reserve_city_label_slot(
    world_position: Vector2,
    force_label: bool
) -> bool:
    if force_label:
        return true
    var screen_position := world_position * zoom + pan
    var slot := Vector2i(
        floori(screen_position.x / 112.0),
        floori(screen_position.y / 24.0)
    )
    if _city_label_slots.has(slot):
        return false
    _city_label_slots[slot] = true
    return true


func _draw_region_ids() -> void:
    var anchors: Dictionary = world_map.manifest.get("province_anchors", {})
    for source_id in anchors.keys():
        var anchor: Dictionary = anchors[source_id]
        var position := Vector2(
            float(anchor.get("map_x", 0.0)),
            float(anchor.get("map_y", 0.0))
        ) * world_map.tile_size
        _queue_map_text(
            position,
            String(source_id),
            10,
            Color("#f4d58a")
        )


func _draw_map_debug_overlay() -> void:
    var mouse_world := _screen_to_world(get_local_mouse_position())
    var tile := world_map.tile_at_world(mouse_world)
    var lonlat := world_map.lonlat_from_world(mouse_world)
    var terrain_name := world_map.terrain_name(
        world_map.terrain_id(tile.x, tile.y)
    )
    var lines := [
        "MAP DEBUG  F6: panel  F7: coast  F8: chunks  F9: regions  Home: overview",
        "tile %d,%d  lon %.3f°  lat %.3f°  terrain %s" % [
            tile.x,
            tile.y,
            lonlat.x,
            lonlat.y,
            terrain_name
        ],
        "zoom %.3f  visible chunks %d  detailed tiles <= %d" % [
            zoom,
            visible_chunk_count,
            last_rendered_tile_count
        ]
    ]

    draw_rect(
        Rect2(12, 12, 610, 72),
        Color(0.02, 0.04, 0.06, 0.88),
        true
    )
    for line_index in range(lines.size()):
        draw_string(
            ThemeDB.fallback_font,
            Vector2(22, 33 + line_index * 20),
            lines[line_index],
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            13,
            Color("#d9e4e6")
        )


# Legacy polygon and tile rendering -----------------------------------------

func _draw_province_polygons(numeric_range: Vector2) -> void:
    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var polygon := _polygon_for(province)
        if polygon.size() < 3:
            continue

        draw_colored_polygon(
            polygon,
            _province_color(province, numeric_range)
        )

        var border := _border_color(province)
        var width := 1.4 / zoom
        if (
            province_id in selected_province_ids
            or province_id == selected_province_id
        ):
            border = Color("#f4d58a")
            width = 4.0 / zoom
        elif province_id == _hovered_id:
            border = Color("#d9e4e6")
            width = 2.5 / zoom

        draw_polyline(
            polygon + PackedVector2Array([polygon[0]]),
            border,
            width,
            true
        )

        if province_id in _peace_demands:
            draw_polyline(
                polygon + PackedVector2Array([polygon[0]]),
                Color("#f0a25b"),
                6.0 / zoom,
                true
            )


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
        var province: Dictionary = provinces.get(province_id, {})
        var fill := StrategicMapPaletteScript.terrain_color(
            String(tile.get("terrain", "deep_water")),
            Color("#102f42")
        )
        if not is_water:
            fill = _tile_land_color(tile, province, numeric_range)

        var variation := (
            int(tile.get("column", 0))
            + int(tile.get("row", 0)) * 3
        ) % 5 - 2
        if variation > 0:
            fill = fill.lightened(float(variation) * 0.018)
        elif variation < 0:
            fill = fill.darkened(float(-variation) * 0.018)

        draw_colored_polygon(polygon, fill)
        _draw_hex_tile_border(
            tile,
            polygon,
            province_id,
            is_water
        )


func _draw_hex_tile_border(
    tile: Dictionary,
    polygon: PackedVector2Array,
    province_id: int,
    is_water: bool
) -> void:
    var border := Color("#285568") if is_water else Color(0.08, 0.11, 0.12, 0.58)
    var width := 0.65 / zoom

    if not is_water and bool(tile.get("boundary", false)):
        border = Color("#1b2224")
        width = 1.35 / zoom

    if (
        not is_water
        and (
            province_id in selected_province_ids
            or province_id == selected_province_id
        )
    ):
        border = Color("#f4d58a")
        width = 2.5 / zoom
    elif not is_water and province_id == _hovered_id:
        border = Color("#d9e4e6")
        width = 1.9 / zoom

    draw_polyline(
        polygon + PackedVector2Array([polygon[0]]),
        border,
        width,
        true
    )

    if not is_water and province_id in _peace_demands:
        draw_polyline(
            polygon + PackedVector2Array([polygon[0]]),
            Color("#f0a25b"),
            3.2 / zoom,
            true
        )


func _draw_region_labels() -> void:
    if zoom < 0.5:
        return

    for label_value in map_labels:
        if label_value is not Dictionary:
            continue

        var label: Dictionary = label_value
        var position := _vector_from_value(label.get("position", Vector2.ZERO))
        var color := Color(0.91, 0.85, 0.69, 0.30)
        if String(label.get("kind", "")) == "sea":
            color = Color(0.56, 0.76, 0.84, 0.55)

        _queue_map_text(
            position,
            String(label.get("text", "")),
            19,
            color,
            Vector2.ZERO,
            true
        )


func _draw_grid() -> void:
    var start_x := int(floor(_world_rect.position.x / 80.0)) * 80
    var end_x := int(ceil(_world_rect.end.x / 80.0)) * 80
    var start_y := int(floor(_world_rect.position.y / 80.0)) * 80
    var end_y := int(ceil(_world_rect.end.y / 80.0)) * 80

    for x in range(start_x, end_x + 1, 80):
        draw_line(
            Vector2(x, start_y),
            Vector2(x, end_y),
            Color(0.20, 0.28, 0.33, 0.18),
            1.0 / zoom
        )
    for y in range(start_y, end_y + 1, 80):
        draw_line(
            Vector2(start_x, y),
            Vector2(end_x, y),
            Color(0.20, 0.28, 0.33, 0.18),
            1.0 / zoom
        )


# Strategic overlays ---------------------------------------------------------

func _draw_icons_and_labels() -> void:
    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var center := _province_center(province)
        var owner_id := String(province.get("owner", ""))
        var country: Dictionary = countries.get(owner_id, {})

        if int(country.get("capital_province", -1)) == province_id:
            _draw_star(
                center + Vector2(0, -18),
                7.0,
                Color("#f0c66b")
            )

        if int(province.get("fort", 0)) > 0 and zoom >= 0.78:
            draw_rect(
                Rect2(center + Vector2(24, -12), Vector2(12, 12)),
                Color("#c5b28a"),
                true
            )
            draw_rect(
                Rect2(center + Vector2(24, -12), Vector2(12, 12)),
                Color("#3a3028"),
                false,
                1.5 / zoom
            )

        if zoom >= 0.72:
            var font_size := 14 if zoom >= 1.35 else 11
            _queue_map_text(
                center,
                String(province.get("name", "Province")),
                font_size,
                Color("#f2ead8"),
                Vector2.ZERO,
                true
            )

        if zoom >= 0.58:
            var amount := int(
                armies.get(province_id, province.get("army", 0))
            )
            var badge := Rect2(
                center + Vector2(-17, 8),
                Vector2(34, 20)
            )
            draw_style_box(_badge_style(), badge)
            _queue_map_text(
                badge.position + Vector2(7, 15),
                str(amount),
                11,
                Color.WHITE
            )


func _draw_command_paths() -> void:
    for path in _command_paths:
        var from_id := int(path.get("from_id", -1))
        var to_id := int(path.get("to_id", -1))
        if not provinces.has(from_id) or not provinces.has(to_id):
            continue

        var start := _province_center(provinces[from_id])
        var finish := _province_center(provinces[to_id])
        var color := Color("#6ed7dd")
        if String(path.get("type", "move")) != "move":
            color = Color("#ef806f")

        draw_dashed_line(
            start,
            finish,
            color,
            3.0 / zoom,
            8.0 / zoom,
            true
        )

        var direction := (finish - start).normalized()
        var side := direction.orthogonal()
        var tip := finish - direction * 18.0
        var arrow := PackedVector2Array([
            finish,
            tip + side * 8.0,
            tip - side * 8.0
        ])
        draw_colored_polygon(arrow, color)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for point_index in range(10):
        var angle := -PI * 0.5 + float(point_index) * PI / 5.0
        var point_radius := radius
        if point_index % 2 != 0:
            point_radius = radius * 0.44
        points.append(
            center
            + Vector2(cos(angle), sin(angle)) * point_radius
        )
    draw_colored_polygon(points, color)


func _badge_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.06, 0.09, 0.12, 0.90)
    style.border_color = Color("#bda36f")
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    return style


# Pure calculation adapters --------------------------------------------------

func _province_color(
    province: Dictionary,
    robust_range: Vector2
) -> Color:
    return StrategicMapPaletteScript.province_color(
        province,
        map_mode,
        robust_range,
        countries,
        armies,
        relations,
        wars,
        player_country_id
    )


func _border_color(province: Dictionary) -> Color:
    return StrategicMapPaletteScript.border_color(
        province,
        player_country_id,
        relations,
        wars
    )


func _tile_land_color(
    tile: Dictionary,
    province: Dictionary,
    robust_range: Vector2
) -> Color:
    return StrategicMapPaletteScript.tile_land_color(
        tile,
        province,
        map_mode,
        robust_range,
        countries,
        armies,
        relations,
        wars,
        player_country_id
    )


func _numeric_values(mode: String) -> Array[float]:
    return StrategicMapPaletteScript.numeric_values(
        provinces,
        mode,
        countries,
        armies
    )


func _numeric_value(province: Dictionary, mode: String) -> float:
    return StrategicMapPaletteScript.numeric_value(
        province,
        mode,
        countries,
        armies
    )


func _robust_range(values: Array[float]) -> Vector2:
    return StrategicMapGeometryScript.robust_range(values)


func _polygon_for(province: Dictionary) -> PackedVector2Array:
    return StrategicMapGeometryScript.polygon_from(
        province.get("polygon", [])
    )


func _tile_polygon(tile: Dictionary) -> PackedVector2Array:
    return StrategicMapGeometryScript.polygon_from(
        tile.get("polygon", [])
    )


func _province_center(province: Dictionary) -> Vector2:
    return StrategicMapGeometryScript.province_center(province)


func _pair_key(first_country_id: String, second_country_id: String) -> String:
    return StrategicMapPaletteScript.pair_key(
        first_country_id,
        second_country_id
    )


func _relation(first_country_id: String, second_country_id: String) -> int:
    return StrategicMapPaletteScript.relation(
        first_country_id,
        second_country_id,
        relations
    )


func _at_war(first_country_id: String, second_country_id: String) -> bool:
    return StrategicMapPaletteScript.at_war(
        first_country_id,
        second_country_id,
        wars
    )


# Spatial index and data loading --------------------------------------------

func _load_world_map_if_needed() -> bool:
    if world_map_id.is_empty():
        if world_map != null:
            world_map = null
            _loaded_world_map_id = ""
        return false

    if world_map == null or _loaded_world_map_id != world_map_id:
        world_map = WorldMapDataScript.new()
        if not world_map.load_default():
            push_error(
                "Strategic map fell back to legacy geometry: %s"
                % world_map.error_message
            )
            world_map = null
            _loaded_world_map_id = ""
            return false
        _loaded_world_map_id = world_map_id

    return world_map.bind_runtime_provinces(provinces)


func _rebuild_spatial_index() -> void:
    _spatial_buckets.clear()
    _tile_spatial_buckets.clear()
    _selection_center_buckets.clear()

    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var center := _province_center(province)
        var center_cell := _selection_bucket_for(center)
        if not _selection_center_buckets.has(center_cell):
            _selection_center_buckets[center_cell] = []
        _selection_center_buckets[center_cell].append(province_id)

        if world_map != null:
            continue
        var polygon := _polygon_for(province)
        StrategicMapGeometryScript.add_polygon_to_buckets(
            _spatial_buckets,
            province_id,
            polygon,
            PICK_BUCKET_SIZE
        )

    if world_map == null:
        for tile_index in range(map_tiles.size()):
            var tile_value = map_tiles[tile_index]
            if tile_value is not Dictionary:
                continue

            StrategicMapGeometryScript.add_polygon_to_buckets(
                _tile_spatial_buckets,
                tile_index,
                _tile_polygon(tile_value),
                PICK_BUCKET_SIZE
            )

    spatial_index_rebuild_count += 1


func _selection_bucket_for(world_position: Vector2) -> Vector2i:
    return Vector2i(
        floori(world_position.x / PICK_BUCKET_SIZE),
        floori(world_position.y / PICK_BUCKET_SIZE)
    )


func _add_polygon_to_buckets(
    buckets: Dictionary,
    value: int,
    polygon: PackedVector2Array
) -> void:
    StrategicMapGeometryScript.add_polygon_to_buckets(
        buckets,
        value,
        polygon,
        PICK_BUCKET_SIZE
    )


func _recalculate_world_rect() -> void:
    _world_rect = StrategicMapGeometryScript.calculate_world_rect(
        provinces,
        map_tiles,
        world_map
    )


func _vector_from_value(value: Variant) -> Vector2:
    if value is Vector2:
        return value
    if value is Array and value.size() >= 2:
        return Vector2(float(value[0]), float(value[1]))
    return Vector2.ZERO


# Tooltip --------------------------------------------------------------------

func _tooltip_for(province_id: int) -> String:
    if province_id == -1 or not provinces.has(province_id):
        return ""

    var province: Dictionary = provinces[province_id]
    var owner_id := String(province.get("owner", ""))
    var owner_name := String(
        countries.get(owner_id, {}).get("name", owner_id)
    )
    var army := int(
        armies.get(province_id, province.get("army", 0))
    )

    return "%s\n%s · 병력 %d\n인구 %s · 경제 %s · 요새 %s" % [
        String(province.get("name", "Province")),
        owner_name,
        army,
        str(province.get("population", 0)),
        str(province.get("economy", 0)),
        str(province.get("fort", 0))
    ]
