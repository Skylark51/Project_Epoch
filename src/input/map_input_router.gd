class_name MapInputRouter
extends Node

signal zoom_tier_requested(tier: String)

var strategic_map: StrategicMap
var city_navigation: CityNavigationAdapter
var enabled := false
var edge_pan_enabled := false
var edge_pan_margin := 12.0
var keyboard_pan_speed := 34.0
var edge_pan_speed := 520.0


func bind(map: StrategicMap, city_adapter: CityNavigationAdapter) -> void:
    strategic_map = map
    city_navigation = city_adapter


func configure(settings: Dictionary) -> void:
    edge_pan_enabled = bool(settings.get("edge_pan_enabled", false))
    edge_pan_margin = float(settings.get("edge_pan_margin", 12))
    keyboard_pan_speed = float(settings.get("keyboard_pan_speed", 34.0))
    set_process(edge_pan_enabled)


func set_active(value: bool) -> void:
    enabled = value
    set_process(enabled and edge_pan_enabled)


func should_ignore_shortcuts(focus_owner: Control) -> bool:
    return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox


func handle_key(event: InputEventKey, focus_owner: Control = null) -> bool:
    if not enabled or not event.pressed or event.echo or strategic_map == null:
        return false
    if should_ignore_shortcuts(focus_owner):
        return false
    var key := event.keycode
    if key in [KEY_1, KEY_2, KEY_3] and event.alt_pressed:
        var tier: String = ["strategy", "region", "close"][int(key - KEY_1)]
        strategic_map.set_zoom_tier(tier)
        zoom_tier_requested.emit(tier)
        return true
    if event.alt_pressed or event.ctrl_pressed or event.shift_pressed or event.meta_pressed:
        return false
    var selected_city := city_navigation.get_selected_city_id() if city_navigation != null else ""
    if key == KEY_LEFT and not selected_city.is_empty():
        city_navigation.cycle(-1)
        return true
    if key == KEY_RIGHT and not selected_city.is_empty():
        city_navigation.cycle(1)
        return true
    var movement := Vector2.ZERO
    if key in [KEY_LEFT, KEY_A]:
        movement.x += keyboard_pan_speed
    elif key in [KEY_RIGHT, KEY_D]:
        movement.x -= keyboard_pan_speed
    elif key in [KEY_UP, KEY_W]:
        movement.y += keyboard_pan_speed
    elif key in [KEY_DOWN, KEY_S]:
        movement.y -= keyboard_pan_speed
    if movement != Vector2.ZERO:
        strategic_map.nudge_camera(movement)
        return true
    return false


func _unhandled_key_input(event: InputEvent) -> void:
    if event is not InputEventKey:
        return
    var focused := get_viewport().gui_get_focus_owner()
    if handle_key(event as InputEventKey, focused):
        get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
    if not enabled or not edge_pan_enabled or strategic_map == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    var mouse := get_viewport().get_mouse_position()
    var movement := Vector2.ZERO
    if mouse.x <= edge_pan_margin:
        movement.x += edge_pan_speed * delta
    elif mouse.x >= viewport_size.x - edge_pan_margin:
        movement.x -= edge_pan_speed * delta
    if mouse.y <= edge_pan_margin:
        movement.y += edge_pan_speed * delta
    elif mouse.y >= viewport_size.y - edge_pan_margin:
        movement.y -= edge_pan_speed * delta
    if movement != Vector2.ZERO:
        strategic_map.nudge_camera(movement)
