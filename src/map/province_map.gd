class_name ProvinceMap
extends Node2D

signal province_selected(province_id: int)

var game_state: GameState
var hovered_id: int = -1
var selected_id: int = -1

func setup(state: GameState) -> void:
    game_state = state
    queue_redraw()

func _draw() -> void:
    if game_state == null:
        return
    for province_id in game_state.provinces.keys():
        var province: Dictionary = game_state.provinces[province_id]
        var points := PackedVector2Array()
        for point in province.polygon:
            points.append(Vector2(point[0], point[1]))
        var country: Dictionary = game_state.countries[province.owner]
        var fill := Color(country.color)
        if province_id == hovered_id:
            fill = fill.lightened(0.16)
        if province_id == selected_id:
            fill = fill.lightened(0.28)
        draw_colored_polygon(points, fill)
        draw_polyline(points + PackedVector2Array([points[0]]), Color("#d8ccb4"), 2.0, true)
        var center := _polygon_center(points)
        draw_string(ThemeDB.fallback_font, center - Vector2(36,-4), str(province.name), HORIZONTAL_ALIGNMENT_CENTER, 72, 14, Color("#17191d"))

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
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var id := _province_at(get_local_mouse_position())
        if id != -1:
            selected_id = id
            province_selected.emit(id)
            queue_redraw()

func _province_at(point: Vector2) -> int:
    if game_state == null:
        return -1
    for province_id in game_state.provinces.keys():
        var polygon := PackedVector2Array()
        for p in game_state.provinces[province_id].polygon:
            polygon.append(Vector2(p[0], p[1]))
        if Geometry2D.is_point_in_polygon(point, polygon):
            return int(province_id)
    return -1
