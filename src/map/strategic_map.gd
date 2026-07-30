class_name StrategicMap
extends Control


signal province_selected(province_id: int)
signal selection_changed(province_ids: Array[int])
signal province_dropped(from_id: int, to_id: int)
signal command_target_selected(province_id: int)
signal city_selected(city_id: String)
signal founding_site_selected(site_id: String)
signal settlement_double_clicked(settlement_id: String)
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

const REGIONAL_PLACE_LABELS := {
    "guknae_basin":["국내성","환도산성","압록강 나루","혼강 산길"],
    "pyongyang_basin":["평양성","대성산성","대동강 나루","남강 교차로"],
    "han_river_basin":["한성","북한산성","한강 나루","중랑 교차로"],
    "yeongsan_basin":["영산 성읍","무등산성","영산강 나루","나주 들판"],
    "gyeongju_basin":["금성","명활산성","형산강 나루","죽령 산길"],
    "guya_basin":["구야 성읍","분산성","낙동강 하류","김해 철산"],
    "daegaya_basin":["대가야 성읍","주산성","낙동강 상류","가야산 길"],
    "aragaya_basin":["안라 성읍","성산산성","남강 나루","아라 들판"],
    "liaodong_corridor":["요동성","백암성","요하 나루","천산 길"],
    "qingzhou_corridor":["청주 치소","광고성","치수 나루","산동 염전"],
    "tsukushi_plain":["쓰쿠시","미즈키","지쿠고강","하카타만"],
    "kibi_plain":["기비","쓰쿠리야마","아사히강","세토 내해"],
    "yamato_basin":["야마토","가쓰라기","야마토강","다케노우치 길"],
}
const CITY_VISUAL_PATHS := {
    "camp":"res://assets/city_visuals/city_camp.svg",
    "survey":"res://assets/city_visuals/city_stage_survey.svg",
    "frame":"res://assets/city_visuals/city_stage_frame.svg",
    "well_storage":"res://assets/city_visuals/city_well_storage.svg",
    "farmland":"res://assets/city_visuals/city_farmland.svg",
    "palisade":"res://assets/city_visuals/city_palisade.svg",
}
const PICK_BUCKET_SIZE := 160.0


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


# Rendering and spatial indexes ---------------------------------------------

var _world_rect := Rect2(0, 0, 800, 560)
var _spatial_buckets: Dictionary = {}
var _tile_spatial_buckets: Dictionary = {}
var _screen_text_commands: Array[Dictionary] = []
var founding_sites: Array[Dictionary] = []
var selected_founding_site_id := ""
var settlement_markers: Array[Dictionary] = []
var _last_drawn_text_rects: Array[Rect2] = []
var _last_drawn_texts: Array[String] = []
var _city_visual_textures: Dictionary = {}
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
    for key in CITY_VISUAL_PATHS:
        var path:=String(CITY_VISUAL_PATHS[key])
        if ResourceLoader.exists(path): _city_visual_textures[key]=load(path)
    resized.connect(_clamp_pan)


# Public map contract ---------------------------------------------------------

func set_snapshot(snapshot: Dictionary) -> void:
    provinces = snapshot.get("provinces", {}).duplicate(true)
    map_tiles = snapshot.get("map_tiles", []).duplicate(true)
    map_labels = snapshot.get("map_labels", []).duplicate(true)
    countries = snapshot.get("countries", {}).duplicate(true)
    armies = snapshot.get("armies", {}).duplicate(true)
    relations = snapshot.get("relations", {}).duplicate(true)
    wars = snapshot.get("wars", []).duplicate(true)
    player_country_id = String(snapshot.get("player_country_id", ""))
    world_map_id = String(snapshot.get("world_map_id", ""))

    _load_world_map_if_needed()
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


func set_interaction_state(value: InputState, source_id: int = -1) -> void:
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


func focus_province(province_id: int, target_zoom := -1.0) -> void:
    var province: Dictionary = provinces.get(province_id, {})
    if province.is_empty():
        return
    if target_zoom > 0.0:
        zoom = clampf(target_zoom, min_zoom, max_zoom)
    var center := _province_center(province)
    pan = size * 0.5 - center * zoom
    _clamp_pan()
    camera_changed.emit(zoom)
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
    if event.pressed and event.double_click:
        var settlement_id:=_settlement_at(event.position)
        if not settlement_id.is_empty():
            settlement_double_clicked.emit(settlement_id)
            return
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
            return

        _selection_additive = event.shift_pressed
        _begin_map_drag(event.button_index, event.position)
        return

    if _command_drag:
        var target_id := _province_at(event.position)
        if target_id != -1 and target_id != _drag_source_id:
            province_dropped.emit(_drag_source_id, target_id)
        _command_drag = false
        _drag_source_id = -1
        queue_redraw()
        return

    _finish_map_drag(event.button_index, event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
    if _command_drag:
        _selection_current = event.position
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

    var next_hovered_id := _province_at(event.position)
    if next_hovered_id == _hovered_id:
        return

    _hovered_id = next_hovered_id
    tooltip_changed.emit(
        _tooltip_for(next_hovered_id),
        event.global_position
    )
    queue_redraw()


func _begin_map_drag(button: MouseButton, position: Vector2) -> void:
    _drag_button = button
    _drag_origin = position
    _pan_origin = pan
    _did_drag = false


func _continue_map_drag(position: Vector2) -> void:
    if not _did_drag and position.distance_to(_drag_origin) > 5.0:
        _state_before_drag = input_state
        _did_drag = true
        input_state = InputState.DRAGGING_MAP

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

    if input_state == InputState.DRAGGING_MAP:
        input_state = _state_before_drag

    if did_drag:
        return

    if button == MOUSE_BUTTON_RIGHT:
        _handle_target_click(_province_at(position))
        return

    if button == MOUSE_BUTTON_LEFT:
        var clicked_site := _founding_site_at(position)
        if not clicked_site.is_empty():
            founding_site_selected.emit(clicked_site)
            return
        var clicked_city := _city_at(position)
        if not clicked_city.is_empty():
            city_selected.emit(clicked_city)

        var province_id := _province_at(position)
        if input_state in [
            InputState.CHOOSING_MOVE_TARGET,
            InputState.CHOOSING_ATTACK_TARGET,
            InputState.SELECTING_PEACE_TERMS
        ]:
            _handle_target_click(province_id)
            return

        _selection_origin = position
        _finish_selection(position)


func _finish_selection(position: Vector2) -> void:
    _selection_current = position
    _selection_dragging = false

    var next_selection: Array[int] = []
    if _selection_additive:
        next_selection.assign(selected_province_ids)

    if _selection_origin.distance_to(position) < 7.0:
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

    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var screen_center := (
            _province_center(provinces[province_id]) * zoom + pan
        )
        if (
            selection_rect.has_point(screen_center)
            and province_id not in next_selection
        ):
            next_selection.append(province_id)


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

func set_founding_sites(value: Array) -> void:
    founding_sites.clear()
    for site_value in value:
        if site_value is Dictionary:
            founding_sites.append(site_value.duplicate(true))
    selected_founding_site_id = ""
    queue_redraw()

func select_founding_site(site_id: String) -> void:
    selected_founding_site_id = site_id
    queue_redraw()

func clear_founding_sites() -> void:
    founding_sites.clear()
    selected_founding_site_id = ""
    queue_redraw()

func set_settlement_markers(value: Array) -> void:
    settlement_markers.clear()
    for marker_value in value:
        if marker_value is Dictionary:
            settlement_markers.append(marker_value.duplicate(true))
    queue_redraw()
func founding_site_candidates(province_id: int) -> Array[Dictionary]:
    var specs: Array[Dictionary] = [
        {"id":"waterside","letter":"A","name":"물길 가까운 터","summary":"식수와 교역로 확보가 쉽다.","tradeoff":"홍수와 기습에 취약하다.","bucket":"waterside"},
        {"id":"farmland","letter":"B","name":"넓은 들판","summary":"경작지와 주거지를 빠르게 늘릴 수 있다.","tradeoff":"방어 시설에 더 많은 자재가 든다.","bucket":"farmland"},
        {"id":"highland","letter":"C","name":"숲과 구릉의 목","summary":"감시와 방어에 유리하다.","tradeoff":"개간과 운송이 느리다.","bucket":"highland"},
    ]
    if world_map == null:
        var province: Dictionary = provinces.get(province_id, {})
        var center := _province_center(province)
        var offsets := [Vector2(-52,24),Vector2(46,38),Vector2(8,-54)]
        for index in range(specs.size()): specs[index]["position"]=center+offsets[index]
        return specs
    var buckets := {"waterside":[],"farmland":[],"highland":[],"all":[]}
    for index_value in world_map.assigned_indices:
        var tile_index:=int(index_value)
        var row:=tile_index/world_map.width; var column:=tile_index%world_map.width
        if world_map.province_id(column,row)!=province_id: continue
        var terrain_id:=world_map.terrain_id(column,row)
        if terrain_id<=2 or terrain_id==13: continue
        var candidate:={"position":world_map.tile_center(column,row),"terrain":world_map.terrain_name(terrain_id)}
        buckets.all.append(candidate)
        if terrain_id in [4,5,10]: buckets.farmland.append(candidate)
        if terrain_id in [6,7,8]: buckets.highland.append(candidate)
        if _tile_touches_water(column,row): buckets.waterside.append(candidate)
    var used:Array[Vector2]=[]; var result:Array[Dictionary]=[]
    for spec_value in specs:
        var spec:Dictionary=spec_value.duplicate(true)
        var pool:Array=buckets.get(String(spec.bucket),[])
        if pool.is_empty(): pool=buckets.all
        var picked:=_spread_candidate(pool,used)
        if picked.is_empty(): continue
        var position:=Vector2(picked.position); used.append(position)
        spec.position=position; spec.terrain=String(picked.get("terrain","unknown")); result.append(spec)
    return result

func _tile_touches_water(column:int,row:int) -> bool:
    for offset in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
        var terrain_id:=world_map.terrain_id(column+offset.x,row+offset.y)
        if terrain_id<=2 or terrain_id==13: return true
    return false

func _spread_candidate(pool:Array,used:Array[Vector2]) -> Dictionary:
    if pool.is_empty(): return {}
    if used.is_empty(): return Dictionary(pool[int(pool.size()/2)]).duplicate(true)
    var best:Dictionary={}; var best_distance:=-1.0
    for candidate_value in pool:
        var candidate:Dictionary=candidate_value; var position:=Vector2(candidate.position); var nearest:=INF
        for used_position in used: nearest=minf(nearest,position.distance_to(used_position))
        if nearest>best_distance: best_distance=nearest; best=candidate
    return best.duplicate(true)

func _settlement_at(screen_point:Vector2) -> String:
    var world_position:=_screen_to_world(screen_point)
    for marker in settlement_markers:
        if world_position.distance_to(Vector2(marker.get("position",Vector2.ZERO)))<=26.0/maxf(zoom,0.01):
            return String(marker.get("id",""))
    return ""
func _founding_site_at(screen_point:Vector2) -> String:
    var world_position:=_screen_to_world(screen_point)
    for site in founding_sites:
        if world_position.distance_to(Vector2(site.get("position",Vector2.ZERO)))<=18.0/maxf(zoom,0.01):
            return String(site.get("id",""))
    return ""
func _city_at(screen_point: Vector2) -> String:
    if world_map == null:
        return ""

    var world_position := _screen_to_world(screen_point)
    for city_value in world_map.cities:
        if city_value is not Dictionary:
            continue

        var city: Dictionary = city_value
        if not bool(city.get("enabled", true)):
            continue
        if not bool(city.get("inBounds", false)):
            continue

        var position := Vector2(
            float(city.get("mapX", 0.0)),
            float(city.get("mapY", 0.0))
        ) * world_map.tile_size
        if world_position.distance_to(position) <= 9.0 / zoom:
            return String(city.get("id", ""))

    return ""


func _province_at(screen_point: Vector2) -> int:
    var world_position := _screen_to_world(screen_point)

    if world_map != null:
        var tile := world_map.tile_at_world(world_position)
        return world_map.province_id(tile.x, tile.y)

    var cell := Vector2i(
        floori(world_position.x / PICK_BUCKET_SIZE),
        floori(world_position.y / PICK_BUCKET_SIZE)
    )

    if not map_tiles.is_empty():
        return _province_from_tile_candidates(world_position, cell)
    return _province_from_polygon_candidates(world_position, cell)


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
    _draw_founding_sites()
    _draw_settlement_markers()

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

func _queue_map_text(world_position: Vector2, text: String, font_size: int, color: Color, screen_offset := Vector2.ZERO, centered := false, priority := 0) -> void:
    if text.is_empty():
        return
    _screen_text_commands.append({
        "world_position": world_position,
        "text": text,
        "font_size": font_size,
        "color": color,
        "screen_offset": screen_offset,
        "centered": centered,
        "priority": priority,
    })


func _draw_screen_text_commands() -> void:
    var font := ThemeDB.fallback_font
    var visible_bounds := Rect2(Vector2.ZERO, size).grow(24.0)
    var commands:=_screen_text_commands.duplicate()
    commands.sort_custom(func(a,b): return int(a.get("priority",0))>int(b.get("priority",0)))
    _last_drawn_text_rects.clear(); _last_drawn_texts.clear()
    for command in commands:
        var screen_position: Vector2 = Vector2(command.get("world_position", Vector2.ZERO)) * zoom + pan + Vector2(command.get("screen_offset", Vector2.ZERO))
        var text := String(command.get("text", "")); var font_size := int(command.get("font_size", 14))
        var text_size:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
        if bool(command.get("centered", false)): screen_position.x-=text_size.x*0.5
        var text_rect:=Rect2(screen_position-Vector2(2.0,float(font_size)+2.0),text_size+Vector2(4.0,6.0))
        var collision_rect:=text_rect.grow(2.0)
        if not visible_bounds.intersects(text_rect): continue
        var overlaps:=false
        for occupied in _last_drawn_text_rects:
            if occupied.intersects(collision_rect): overlaps=true; break
        if overlaps: continue
        draw_string(font,screen_position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(command.get("color",Color.WHITE)))
        _last_drawn_text_rects.append(collision_rect); _last_drawn_texts.append(text)

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

    if zoom < 0.32 and world_map.overview_texture != null:
        _draw_world_overview()
    else:
        _draw_visible_world_chunks(chunks)
        _draw_world_selection(world_view)
        if show_coast_highlight:
            _draw_coast_highlight(world_view)

    _draw_world_labels()
    _draw_regional_place_labels()
    if show_region_ids:
        _draw_region_ids()
    _draw_cities()


func _draw_world_overview() -> void:
    var overview := world_map.overview_texture_for_mode(
        map_mode,
        countries,
        provinces,
        player_country_id,
        relations,
        wars
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
                wars
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
    if selected_province_ids.is_empty() and _hovered_id == -1:
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
            if (
                province_id not in selected_province_ids
                and province_id != _hovered_id
            ):
                continue

            var color := Color(0.86, 0.91, 0.92, 0.28)
            if province_id in selected_province_ids:
                color = Color(0.96, 0.83, 0.45, 0.43)

            draw_rect(
                Rect2(
                    Vector2(column, row) * world_map.tile_size,
                    Vector2.ONE * world_map.tile_size
                ),
                color,
                false,
                1.5 / zoom
            )


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


func _draw_world_labels() -> void:
    if zoom < 0.16:
        return

    for label in WORLD_LABELS:
        var position := world_map.world_from_lonlat(
            float(label[1]),
            float(label[2])
        )
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


func _draw_regional_place_labels() -> void:
    if zoom < 1.05: return
    var anchors:Dictionary=world_map.manifest.get("province_anchors",{})
    var offsets:=[Vector2(-72,-52),Vector2(62,-44),Vector2(-58,50),Vector2(70,54)]
    for source_id in REGIONAL_PLACE_LABELS.keys():
        var anchor:Dictionary=anchors.get(source_id,{})
        if anchor.is_empty(): continue
        var center:=Vector2(float(anchor.get("map_x",0.0)),float(anchor.get("map_y",0.0)))*world_map.tile_size
        var names:Array=REGIONAL_PLACE_LABELS[source_id]
        for index in range(mini(names.size(),offsets.size())):
            _queue_map_text(center+offsets[index],String(names[index]),11,Color("#c8bea0"),Vector2.ZERO,true,46)

func _draw_cities() -> void:
    for city_value in world_map.cities:
        if city_value is not Dictionary:
            continue

        var city: Dictionary = city_value
        if not bool(city.get("enabled", true)):
            continue
        if not bool(city.get("inBounds", false)):
            continue

        var is_major_city := String(city.get("type", "")) == "major_city"
        if zoom < 0.14 and not is_major_city:
            continue

        var position := Vector2(
            float(city.get("mapX", 0.0)),
            float(city.get("mapY", 0.0))
        ) * world_map.tile_size
        var radius := (4.0 if is_major_city else 2.6) / zoom

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

        if zoom >= 0.52:
            _queue_map_text(
                position,
                String(city.get("name", city.get("id", ""))),
                12,
                Color("#f2ead8"),
                Vector2(6.0, -3.0)
            )


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


func _draw_founding_sites() -> void:
    for site in founding_sites:
        var position:=Vector2(site.get("position",Vector2.ZERO))
        var selected:=String(site.get("id",""))==selected_founding_site_id
        var fill:=Color("#e5bd66") if selected else Color("#63b9b2")
        var radius:=14.0/maxf(zoom,0.01)
        draw_circle(position,radius,Color(0.04,0.07,0.08,0.92))
        draw_arc(position,radius,0.0,TAU,24,fill,3.0/maxf(zoom,0.01),true)
        draw_circle(position,4.0/maxf(zoom,0.01),fill)
        _queue_map_text(position,"%s · %s" % [String(site.get("letter","?")),String(site.get("name","후보지"))],13,fill,Vector2(0,-22),true,100)
func settlement_visual_key(marker:Dictionary) -> String:
    var stage:=int(marker.get("stage",3))
    if stage<=1: return "survey"
    if stage==2: return "frame"
    var appearance:=String(marker.get("appearance","camp"))
    return appearance if CITY_VISUAL_PATHS.has(appearance) else "camp"

func _draw_settlement_markers() -> void:
    for marker in settlement_markers:
        var position:=Vector2(marker.get("position",Vector2.ZERO))
        var asset_key:=settlement_visual_key(marker); var texture:Texture2D=_city_visual_textures.get(asset_key)
        var households:=int(marker.get("households",0)); var population_scale:=1.0+minf(float(households),30.0)/150.0
        var screen_scale:=population_scale/maxf(zoom,0.01); var target_size:=Vector2(96,72)*screen_scale
        if texture!=null:
            draw_texture_rect(texture,Rect2(position-target_size*Vector2(0.5,0.68),target_size),false)
        else:
            draw_circle(position,22.0*screen_scale,Color("#a17b4d")); draw_arc(position,22.0*screen_scale,0.0,TAU,24,Color("#e5bd66"),2.4*screen_scale,true)
        var stage:=int(marker.get("stage",3)); var stage_suffix:=" · 공사 %d/3" % stage if stage<3 else ""
        _queue_map_text(position,String(marker.get("name","첫 도시"))+stage_suffix,14,Color("#f1d58b"),Vector2(0,-42*population_scale),true,120)
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

func _load_world_map_if_needed() -> void:
    if world_map_id.is_empty():
        return

    if world_map == null:
        world_map = WorldMapDataScript.new()
        if not world_map.load_default():
            push_error(
                "Strategic map fell back to legacy geometry: %s"
                % world_map.error_message
            )
            world_map = null

    if world_map != null:
        world_map.bind_runtime_provinces(provinces)


func _rebuild_spatial_index() -> void:
    _spatial_buckets.clear()
    _tile_spatial_buckets.clear()

    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var polygon := _polygon_for(provinces[province_id])
        StrategicMapGeometryScript.add_polygon_to_buckets(
            _spatial_buckets,
            province_id,
            polygon,
            PICK_BUCKET_SIZE
        )

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
