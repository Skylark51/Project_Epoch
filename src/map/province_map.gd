class_name ProvinceMap
extends Node2D

signal province_selected(province_id: int)
signal province_commanded(province_id: int)

var game_state: GameState
var hovered_id: int = -1
var selected_id: int = -1
var zoom_level: float = 1.0
var dragging: bool = false
var last_mouse_position := Vector2.ZERO

func setup(state: GameState) -> void:
    game_state = state
    queue_redraw()

func refresh() -> void:
    queue_redraw()

func _draw() -> void:
    if game_state == null:
        return
    for province_id in game_state.provinces.keys():
        var province: Dictionary = game_state.provinces[province_id]
        var points := _points_for(province)
        var fill := _province_color(province)
        if province_id == hovered_id:
            fill = fill.lightened(0.14)
        if province_id == selected_id:
            fill = fill.lightened(0.25)
        draw_colored_polygon(points, fill)
        var border_color := Color("#e5d7bc") if province_id == selected_id else Color("#817968")
        draw_polyline(points + PackedVector2Array([points[0]]), border_color, 2.0 if province_id == selected_id else 1.2, true)

        var center := _polygon_center(points)
        draw_string(ThemeDB.fallback_font, center - Vector2(40, -4), str(province.name), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color("#101318"))
        var army := int(game_state.armies.get(province_id, 0))
        if army > 0:
            draw_circle(center + Vector2(0, 24), 16, Color("#1d2430"))
            draw_string(ThemeDB.fallback_font, center + Vector2(-16, 29), str(army), HORIZONTAL_ALIGNMENT_CENTER, 32, 13, Color.WHITE)

func _province_color(province: Dictionary) -> Color:
    match game_state.map_mode:
        "economy":
            var value := clamp(float(province.economy) / 60.0, 0.12, 1.0)
            return Color(0.18, 0.32 + value * 0.45, 0.24, 1.0)
        "population":
            var value := clamp(float(province.population) / 80.0, 0.12, 1.0)
            return Color(0.30 + value * 0.48, 0.24, 0.20, 1.0)
        _:
            var country: Dictionary = game_state.countries[province.owner]
            return Color(country.color)

func _points_for(province: Dictionary) -> PackedVector2Array:
    var points := PackedVector2Array()
    for point in province.polygon:
        points.append(Vector2(point[0], point[1]))
    return points

func _polygon_center(points: PackedVector2Array) -> Vector2:
    var sum := Vector2.ZERO
    for point in points:
        sum += point
    return sum / max(points.size(), 1)

func _process(_delta: float) -> void:
    var mouse := get_local_mouse_position()
    var next_hover := _province_at(mouse)
    if next_hover != hovered_id:
        hovered_id = next_hover
        queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom_at(event.position, 1.12)
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom_at(event.position, 0.89)
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            dragging = event.pressed
            last_mouse_position = event.position
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var id := _province_at(get_local_mouse_position())
            if id != -1:
                selected_id = id
                province_selected.emit(id)
                queue_redraw()
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            var id := _province_at(get_local_mouse_position())
            if id != -1:
                province_commanded.emit(id)
    elif event is InputEventMouseMotion and dragging:
        position += event.position - last_mouse_position
        last_mouse_position = event.position
        get_viewport().set_input_as_handled()

func _zoom_at(screen_position: Vector2, factor: float) -> void:
    var old_scale := scale.x
    var next_scale := clamp(old_scale * factor, 0.55, 2.5)
    factor = next_scale / old_scale
    var local_anchor := to_local(screen_position)
    scale = Vector2.ONE * next_scale
    position += (screen_position - to_global(local_anchor))
    zoom_level = next_scale

func _province_at(point: Vector2) -> int:
    if game_state == null:
        return -1
    for province_id in game_state.provinces.keys():
        var polygon := _points_for(game_state.provinces[province_id])
        if Geometry2D.is_point_in_polygon(point, polygon):
            return int(province_id)
    return -1
