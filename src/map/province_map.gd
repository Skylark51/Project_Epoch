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
    for province_id_value in game_state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = game_state.provinces[province_id]
        var points := _points_for(province)
        var fill := _province_color(province)
        if province_id == hovered_id:
            fill = fill.lightened(0.14)
        if province_id == selected_id:
            fill = fill.lightened(0.25)
        draw_colored_polygon(points, fill)

        var owner_id := String(province.owner)
        var at_war := game_state.diplomacy.at_war(game_state.player_country_id, owner_id)
        var border_color := Color("#b64d48") if at_war else Color("#817968")
        if province_id == selected_id:
            border_color = Color("#f0dfb8")
        draw_polyline(points + PackedVector2Array([points[0]]), border_color, 2.4 if province_id == selected_id else 1.3, true)

        var center := _polygon_center(points)
        draw_string(ThemeDB.fallback_font, center - Vector2(44, -4), str(province.name), HORIZONTAL_ALIGNMENT_CENTER, 88, 14, Color("#101318"))
        var army := int(game_state.armies.get(province_id, 0))
        if army > 0:
            draw_circle(center + Vector2(0, 25), 16, Color("#1a202a"))
            draw_circle(center + Vector2(0, 25), 16, Color("#d9c9a4"), false, 1.5)
            draw_string(ThemeDB.fallback_font, center + Vector2(-16, 30), str(army), HORIZONTAL_ALIGNMENT_CENTER, 32, 13, Color.WHITE)

        var owner: Dictionary = game_state.countries[owner_id]
        if int(owner.get("capital_province", -1)) == province_id:
            draw_string(ThemeDB.fallback_font, center + Vector2(-7, -22), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f5e3a7"))

    _draw_queued_commands()

func _draw_queued_commands() -> void:
    for command in game_state.command_queue.commands:
        if String(command.country_id) != game_state.player_country_id:
            continue
        var payload: Dictionary = command.payload
        match String(command.type):
            "move":
                var from_id := int(payload.from_id)
                var to_id := int(payload.to_id)
                if not game_state.provinces.has(from_id) or not game_state.provinces.has(to_id):
                    continue
                var start := _center_for_province(from_id)
                var finish := _center_for_province(to_id)
                draw_line(start, finish, Color("#f1d36b"), 4.0, true)
                var direction := (finish - start).normalized()
                var side := Vector2(-direction.y, direction.x)
                var arrow := PackedVector2Array([
                    finish,
                    finish - direction * 16.0 + side * 8.0,
                    finish - direction * 16.0 - side * 8.0
                ])
                draw_colored_polygon(arrow, Color("#f1d36b"))
            "recruit":
                var province_id := int(payload.province_id)
                if game_state.provinces.has(province_id):
                    var center := _center_for_province(province_id) + Vector2(0, 25)
                    draw_arc(center, 21, 0, TAU, 28, Color("#78d69a"), 3.0, true)

func _province_color(province: Dictionary) -> Color:
    match game_state.map_mode:
        "economy":
            var economy_value := clamp(float(province.economy) / 65.0, 0.12, 1.0)
            return Color(0.16, 0.28 + economy_value * 0.52, 0.22, 1.0)
        "population":
            var population_value := clamp(float(province.population) / 85.0, 0.12, 1.0)
            return Color(0.26 + population_value * 0.52, 0.22, 0.18, 1.0)
        "relations":
            var owner_id := String(province.owner)
            if owner_id == game_state.player_country_id:
                return Color(game_state.countries[owner_id].color).lightened(0.18)
            if game_state.diplomacy.at_war(game_state.player_country_id, owner_id):
                return Color("#8c3434")
            var relation := game_state.diplomacy.relation(game_state.player_country_id, owner_id)
            if relation >= 40:
                return Color("#4f8a78")
            if relation >= 0:
                return Color("#6e7d8d")
            if relation > -40:
                return Color("#9a754a")
            return Color("#8b4744")
        _:
            var country: Dictionary = game_state.countries[province.owner]
            return Color(country.color)

func _points_for(province: Dictionary) -> PackedVector2Array:
    var points := PackedVector2Array()
    for point in province.polygon:
        points.append(Vector2(point[0], point[1]))
    return points

func _center_for_province(province_id: int) -> Vector2:
    return _polygon_center(_points_for(game_state.provinces[province_id]))

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
    var applied_factor := next_scale / old_scale
    var local_anchor := to_local(screen_position)
    scale = Vector2.ONE * next_scale
    position += screen_position - to_global(local_anchor)
    zoom_level = next_scale
    if applied_factor == 1.0:
        return

func _province_at(point: Vector2) -> int:
    if game_state == null:
        return -1
    for province_id in game_state.provinces.keys():
        var polygon := _points_for(game_state.provinces[province_id])
        if Geometry2D.is_point_in_polygon(point, polygon):
            return int(province_id)
    return -1
