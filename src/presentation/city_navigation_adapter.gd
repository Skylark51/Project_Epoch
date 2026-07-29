class_name CityNavigationAdapter
extends RefCounted

signal city_selected(city_id: String)
signal city_selection_requested(city_id: String)

var provider: Object
var strategic_map: StrategicMap
var selected_city_id := ""
var fallback_city_ids: Array[String] = []


func bind(map: StrategicMap, city_provider: Object = null) -> void:
    strategic_map = map
    provider = city_provider
    _refresh_fallback_ids()


func set_provider(city_provider: Object) -> void:
    provider = city_provider


func get_ordered_city_ids() -> Array[String]:
    if provider != null and provider.has_method("get_ordered_city_ids"):
        return _string_array(provider.call("get_ordered_city_ids"))
    if provider != null and provider.has_method("getOrderedCityIds"):
        return _string_array(provider.call("getOrderedCityIds"))
    _refresh_fallback_ids()
    return fallback_city_ids.duplicate()


func get_selected_city_id() -> String:
    if provider != null and provider.has_method("get_selected_city_id"):
        return String(provider.call("get_selected_city_id"))
    if provider != null and provider.has_method("getSelectedCityId"):
        return String(provider.call("getSelectedCityId"))
    return selected_city_id


func select_city_by_id(city_id: String) -> bool:
    if city_id.is_empty():
        return false
    var handled := false
    if provider != null and provider.has_method("select_city_by_id"):
        provider.call("select_city_by_id", city_id)
        handled = true
    elif provider != null and provider.has_method("selectCityById"):
        provider.call("selectCityById", city_id)
        handled = true
    selected_city_id = city_id
    city_selection_requested.emit(city_id)
    city_selected.emit(city_id)
    return handled or city_id in get_ordered_city_ids()


func focus_camera_on_city(city_id: String) -> bool:
    if provider != null and provider.has_method("focus_camera_on_city"):
        provider.call("focus_camera_on_city", city_id)
        return true
    if provider != null and provider.has_method("focusCameraOnCity"):
        provider.call("focusCameraOnCity", city_id)
        return true
    return strategic_map != null and strategic_map.focus_city(city_id)


func cycle(direction: int) -> String:
    var ids := get_ordered_city_ids()
    if ids.is_empty():
        return ""
    var current := get_selected_city_id()
    var index := ids.find(current)
    if index < 0:
        index = 0 if direction >= 0 else ids.size() - 1
    else:
        index = posmod(index + (1 if direction >= 0 else -1), ids.size())
    var next_id := ids[index]
    select_city_by_id(next_id)
    focus_camera_on_city(next_id)
    return next_id


func accept_map_selection(city_id: String) -> void:
    select_city_by_id(city_id)
    focus_camera_on_city(city_id)


func clear_selection() -> void:
    if provider != null and provider.has_method("clear_city_selection"):
        provider.call("clear_city_selection")
    elif provider != null and provider.has_method("clearCitySelection"):
        provider.call("clearCitySelection")
    selected_city_id = ""


func _refresh_fallback_ids() -> void:
    if strategic_map == null or strategic_map.world_map == null:
        return
    var entries: Array = strategic_map.world_map.cities.duplicate(true)
    entries.sort_custom(func(a, b):
        var ax := float(a.get("longitude", a.get("mapX", 0.0)))
        var bx := float(b.get("longitude", b.get("mapX", 0.0)))
        if not is_equal_approx(ax, bx):
            return ax < bx
        return float(a.get("latitude", a.get("mapY", 0.0))) > float(b.get("latitude", b.get("mapY", 0.0)))
    )
    fallback_city_ids.clear()
    for value in entries:
        if value is Dictionary and bool(value.get("enabled", true)):
            var id := String(value.get("id", ""))
            if not id.is_empty():
                fallback_city_ids.append(id)


func _string_array(values) -> Array[String]:
    var result: Array[String] = []
    if values is Array:
        for value in values:
            var id := String(value)
            if not id.is_empty():
                result.append(id)
    return result
