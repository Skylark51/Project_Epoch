class_name StrategicMapGeometry
extends RefCounted


## Pure geometry and camera calculations for StrategicMap.
##
## Rendering and input remain in the Control node. This module owns calculations
## that can be understood and tested without a scene tree or drawing context.


static func screen_to_world(
    screen_point: Vector2,
    pan: Vector2,
    zoom: float
) -> Vector2:
    return (screen_point - pan) / zoom


static func zoom_at(
    screen_point: Vector2,
    factor: float,
    pan: Vector2,
    zoom: float,
    minimum_zoom: float,
    maximum_zoom: float
) -> Dictionary:
    var world_point_before_zoom := screen_to_world(screen_point, pan, zoom)
    var next_zoom := clampf(
        zoom * factor,
        minimum_zoom,
        maximum_zoom
    )
    var next_pan := screen_point - world_point_before_zoom * next_zoom
    return {
        "zoom": next_zoom,
        "pan": next_pan
    }


static func clamp_pan(
    pan: Vector2,
    viewport_size: Vector2,
    world_rect: Rect2,
    zoom: float,
    margin: float = 90.0
) -> Vector2:
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        return pan

    var scaled_minimum := world_rect.position * zoom
    var scaled_maximum := world_rect.end * zoom
    return Vector2(
        clampf(
            pan.x,
            viewport_size.x - scaled_maximum.x - margin,
            -scaled_minimum.x + margin
        ),
        clampf(
            pan.y,
            viewport_size.y - scaled_maximum.y - margin,
            -scaled_minimum.y + margin
        )
    )


static func frame_world(
    viewport_size: Vector2,
    world_rect: Rect2,
    minimum_zoom: float,
    maximum_frame_zoom: float = 1.8
) -> Dictionary:
    if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
        return {}

    var horizontal_zoom := viewport_size.x / maxf(
        world_rect.size.x + 120.0,
        1.0
    )
    var vertical_zoom := viewport_size.y / maxf(
        world_rect.size.y + 120.0,
        1.0
    )
    var next_zoom := clampf(
        minf(horizontal_zoom, vertical_zoom),
        minimum_zoom,
        maximum_frame_zoom
    )
    var world_center := world_rect.position + world_rect.size * 0.5
    var next_pan := viewport_size * 0.5 - world_center * next_zoom
    return {
        "zoom": next_zoom,
        "pan": next_pan
    }


static func focus_pan(
    viewport_size: Vector2,
    world_position: Vector2,
    zoom: float
) -> Vector2:
    return viewport_size * 0.5 - world_position * zoom


static func polygon_from(value: Variant) -> PackedVector2Array:
    var result := PackedVector2Array()
    if value is not Array:
        return result

    for point_value in value:
        if point_value is Vector2:
            result.append(point_value)
        elif point_value is Array and point_value.size() >= 2:
            result.append(
                Vector2(
                    float(point_value[0]),
                    float(point_value[1])
                )
            )
    return result


static func province_center(province: Dictionary) -> Vector2:
    var center_value = province.get("map_center", [])
    if center_value is Vector2:
        return center_value
    if center_value is Array and center_value.size() >= 2:
        return Vector2(
            float(center_value[0]),
            float(center_value[1])
        )

    var polygon := polygon_from(province.get("polygon", []))
    if polygon.is_empty():
        return Vector2.ZERO

    var total := Vector2.ZERO
    for point in polygon:
        total += point
    return total / float(polygon.size())


static func robust_range(values: Array[float]) -> Vector2:
    if values.is_empty():
        return Vector2(0.0, 1.0)

    var sorted_values := values.duplicate()
    sorted_values.sort()

    var low_index := int(floor((sorted_values.size() - 1) * 0.08))
    var high_index := int(ceil((sorted_values.size() - 1) * 0.92))
    var low := float(sorted_values[low_index])
    var high := float(sorted_values[high_index])

    if is_equal_approx(low, high):
        high = low + 1.0
    return Vector2(low, high)


static func add_polygon_to_buckets(
    buckets: Dictionary,
    value: int,
    polygon: PackedVector2Array,
    bucket_size: float
) -> void:
    if polygon.is_empty():
        return

    var bounds := Rect2(polygon[0], Vector2.ZERO)
    for point in polygon:
        bounds = bounds.expand(point)

    var minimum_cell := Vector2i(
        floori(bounds.position.x / bucket_size),
        floori(bounds.position.y / bucket_size)
    )
    var maximum_cell := Vector2i(
        floori(bounds.end.x / bucket_size),
        floori(bounds.end.y / bucket_size)
    )

    for column in range(minimum_cell.x, maximum_cell.x + 1):
        for row in range(minimum_cell.y, maximum_cell.y + 1):
            var cell := Vector2i(column, row)
            if not buckets.has(cell):
                buckets[cell] = []
            buckets[cell].append(value)


static func calculate_world_rect(
    provinces: Dictionary,
    map_tiles: Array,
    world_map
) -> Rect2:
    if world_map != null:
        return world_map.world_rect()

    var points := PackedVector2Array()
    if not map_tiles.is_empty():
        for tile_value in map_tiles:
            if tile_value is Dictionary:
                points.append_array(
                    polygon_from(tile_value.get("polygon", []))
                )
    else:
        for province_value in provinces.values():
            if province_value is Dictionary:
                points.append_array(
                    polygon_from(province_value.get("polygon", []))
                )

    if points.is_empty():
        return Rect2(0.0, 0.0, 800.0, 560.0)

    var bounds := Rect2(points[0], Vector2.ZERO)
    for point in points:
        bounds = bounds.expand(point)
    return bounds
