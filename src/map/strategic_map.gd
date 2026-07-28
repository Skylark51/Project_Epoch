class_name StrategicMap
extends Control

signal province_selected(province_id: int)
signal selection_changed(province_ids: Array[int])
signal province_dropped(from_id: int, to_id: int)
signal command_target_selected(province_id: int)
signal tooltip_changed(text: String, screen_position: Vector2)
signal camera_changed(zoom: float)

enum InputState { IDLE, CHOOSING_MOVE_TARGET, CHOOSING_ATTACK_TARGET, SELECTING_PEACE_TERMS, DRAGGING_MAP, MODAL_OPEN }

const MODE_LABELS := {
    "political": "정치", "relations": "외교 관계", "war": "전쟁", "economy": "경제",
    "population": "인구", "development": "개발도", "manpower": "인력", "stability": "안정도",
    "revolt": "반란 위험", "terrain": "지형", "fort": "요새", "supply": "보급"
}
const TERRAIN_COLORS := {"plains": Color("#7d8a63"), "hills": Color("#81725b"), "forest": Color("#4f6c55"), "coast": Color("#58788a")}

var provinces: Dictionary = {}
var countries: Dictionary = {}
var armies: Dictionary = {}
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
var min_zoom := 0.55
var max_zoom := 4.0
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
const PICK_BUCKET_SIZE := 160.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    clip_contents = true
    resized.connect(_clamp_pan)

func set_snapshot(snapshot: Dictionary) -> void:
    provinces = snapshot.get("provinces", {}).duplicate(true)
    countries = snapshot.get("countries", {}).duplicate(true)
    armies = snapshot.get("armies", {}).duplicate(true)
    relations = snapshot.get("relations", {}).duplicate(true)
    wars = snapshot.get("wars", []).duplicate(true)
    player_country_id = String(snapshot.get("player_country_id", ""))
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
    var zx := size.x / maxf(_world_rect.size.x + 120.0, 1.0)
    var zy := size.y / maxf(_world_rect.size.y + 120.0, 1.0)
    zoom = clampf(minf(zx, zy), min_zoom, 1.8)
    pan = size * 0.5 - (_world_rect.position + _world_rect.size * 0.5) * zoom
    _clamp_pan()
    queue_redraw()

func focus_province(province_id: int) -> void:
    var province: Dictionary = provinces.get(province_id, {})
    if province.is_empty():
        return
    var center := _province_center(province)
    pan = size * 0.5 - center * zoom
    _clamp_pan()
    queue_redraw()

func nudge_camera(delta:Vector2) -> void:
    pan+=delta; _clamp_pan(); queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if input_state == InputState.MODAL_OPEN:
        accept_event(); return
    if event is InputEventMouseButton:
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
    _selection_current = position; _selection_dragging = false
    var next: Array[int] = []
    if _selection_additive: next.assign(selected_province_ids)
    if _selection_origin.distance_to(position) < 7.0:
        var id := _province_at(position)
        if id != -1:
            if _selection_additive and id in next: next.erase(id)
            elif id not in next: next.append(id)
    else:
        var rect := Rect2(_selection_origin, position - _selection_origin).abs()
        for id_value in provinces.keys():
            var id := int(id_value)
            var screen_center := _province_center(provinces[id]) * zoom + pan
            if rect.has_point(screen_center) and id not in next: next.append(id)
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
    var before := (screen_point - pan) / zoom
    zoom = clampf(zoom * factor, min_zoom, max_zoom)
    pan = screen_point - before * zoom
    _clamp_pan()
    camera_changed.emit(zoom)
    queue_redraw()

func _clamp_pan() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var margin := 90.0
    var scaled_min := _world_rect.position * zoom
    var scaled_max := _world_rect.end * zoom
    pan.x = clampf(pan.x, size.x - scaled_max.x - margin, -scaled_min.x + margin)
    pan.y = clampf(pan.y, size.y - scaled_max.y - margin, -scaled_min.y + margin)

func _screen_to_world(point: Vector2) -> Vector2:
    return (point - pan) / zoom

func _province_at(screen_point: Vector2) -> int:
    var world := _screen_to_world(screen_point)
    var cell := Vector2i(floori(world.x / PICK_BUCKET_SIZE), floori(world.y / PICK_BUCKET_SIZE))
    var candidates: Array = _spatial_buckets.get(cell, provinces.keys())
    for id_value in candidates:
        var id := int(id_value)
        var polygon := _polygon_for(provinces[id])
        if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world, polygon):
            return id
    return -1

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#111a22"))
    draw_set_transform(pan, 0.0, Vector2(zoom, zoom))
    _draw_grid()
    var numeric_range := _robust_range(_numeric_values(map_mode))
    for id_value in provinces.keys():
        var id := int(id_value)
        var province: Dictionary = provinces[id]
        var polygon := _polygon_for(province)
        if polygon.size() < 3:
            continue
        var fill := _province_color(province, numeric_range)
        draw_colored_polygon(polygon, fill)
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
    _draw_command_paths()
    _draw_icons_and_labels()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if _selection_dragging:
        var selection_rect := Rect2(_selection_origin, _selection_current - _selection_origin).abs()
        draw_rect(selection_rect, Color(0.35, 0.78, 0.88, 0.16), true)
        draw_rect(selection_rect, Color("#6ec7d8"), false, 2.0)
    if _command_drag:
        draw_dashed_line(_selection_origin, _selection_current, Color("#f0c66b"), 3.0, 10.0, true)

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
    for id_value in provinces.keys():
        var id := int(id_value)
        var province: Dictionary = provinces[id]
        var center := _province_center(province)
        var owner := String(province.get("owner", ""))
        var country: Dictionary = countries.get(owner, {})
        if int(country.get("capital_province", -1)) == id:
            _draw_star(center + Vector2(0, -18), 7.0, Color("#f0c66b"))
        if int(province.get("fort", 0)) > 0 and zoom >= 0.78:
            draw_rect(Rect2(center + Vector2(24, -12), Vector2(12, 12)), Color("#c5b28a"), true)
            draw_rect(Rect2(center + Vector2(24, -12), Vector2(12, 12)), Color("#3a3028"), false, 1.5 / zoom)
        if zoom >= 0.72:
            var label := String(province.get("name", "Province"))
            var font := ThemeDB.fallback_font
            var font_size := 14 if zoom >= 1.35 else 11
            var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
            draw_string(font, center - Vector2(text_size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f2ead8"))
        if zoom >= 0.58:
            var amount := int(armies.get(id, province.get("army", 0)))
            var badge := Rect2(center + Vector2(-17, 8), Vector2(34, 20))
            draw_style_box(_badge_style(), badge)
            draw_string(ThemeDB.fallback_font, badge.position + Vector2(7, 15), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

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

func _province_center(province: Dictionary) -> Vector2:
    var polygon := _polygon_for(province)
    if polygon.is_empty(): return Vector2.ZERO
    var total := Vector2.ZERO
    for point in polygon: total += point
    return total / float(polygon.size())

func _rebuild_spatial_index() -> void:
    _spatial_buckets.clear()
    for id_value in provinces.keys():
        var id := int(id_value)
        var polygon := _polygon_for(provinces[id])
        if polygon.is_empty():
            continue
        var bounds := Rect2(polygon[0], Vector2.ZERO)
        for point in polygon:
            bounds = bounds.expand(point)
        var min_cell := Vector2i(floori(bounds.position.x / PICK_BUCKET_SIZE), floori(bounds.position.y / PICK_BUCKET_SIZE))
        var max_cell := Vector2i(floori(bounds.end.x / PICK_BUCKET_SIZE), floori(bounds.end.y / PICK_BUCKET_SIZE))
        for x in range(min_cell.x, max_cell.x + 1):
            for y in range(min_cell.y, max_cell.y + 1):
                var cell := Vector2i(x, y)
                if not _spatial_buckets.has(cell):
                    _spatial_buckets[cell] = []
                _spatial_buckets[cell].append(id)
func _recalculate_world_rect() -> void:
    var first := true
    for province in provinces.values():
        for point in _polygon_for(province):
            if first:
                _world_rect = Rect2(point, Vector2.ZERO)
                first = false
            else:
                _world_rect = _world_rect.expand(point)
    if first: _world_rect = Rect2(0, 0, 800, 560)

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
