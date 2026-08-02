extends SceneTree


const SNAPSHOT_ITERATIONS := 48
const PICK_ITERATIONS := 960
const CAMERA_ITERATIONS := 240


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var gateway := StrategyGateway.new()
    if not gateway.load_local_catalog():
        push_error("Map benchmark could not load the East Asia scenario.")
        quit(1)
        return

    var snapshot := gateway.snapshot()
    var scenario_map := _create_map()
    var scenario_started := Time.get_ticks_usec()
    scenario_map.set_snapshot(snapshot)
    var scenario_elapsed := Time.get_ticks_usec() - scenario_started

    var country_map := _create_map()
    var country_started := Time.get_ticks_usec()
    country_map.set_snapshot(snapshot)
    var country_elapsed := Time.get_ticks_usec() - country_started

    var game_map := _create_map()
    var game_started := Time.get_ticks_usec()
    game_map.set_snapshot(snapshot)
    game_map.frame_play_area()
    var game_elapsed := Time.get_ticks_usec() - game_started
    await process_frame
    await process_frame

    var snapshot_started := Time.get_ticks_usec()
    for _iteration in SNAPSHOT_ITERATIONS:
        game_map.set_snapshot(snapshot)
    var snapshot_elapsed := Time.get_ticks_usec() - snapshot_started

    var turn_snapshot := gateway.snapshot()
    turn_snapshot["turn"] = int(turn_snapshot.get("turn", 1)) + 1
    var turn_provinces: Dictionary = turn_snapshot.get("provinces", {})
    if turn_provinces.has(1):
        var first_province: Dictionary = turn_provinces[1]
        first_province["economy"] = float(first_province.get("economy", 0.0)) + 1.0
    var turn_started := Time.get_ticks_usec()
    game_map.set_snapshot(turn_snapshot)
    var turn_elapsed := Time.get_ticks_usec() - turn_started

    var seoul_world := game_map.world_map.world_from_lonlat(126.9780, 37.5665)
    var seoul_screen := seoul_world * game_map.zoom + game_map.pan
    var zoom_started := Time.get_ticks_usec()
    for _iteration in CAMERA_ITERATIONS:
        game_map.call("_zoom_at", seoul_screen, 1.01)
        game_map.call("_zoom_at", seoul_screen, 1.0 / 1.01)
    var zoom_elapsed := Time.get_ticks_usec() - zoom_started

    var pan_started := Time.get_ticks_usec()
    for _iteration in CAMERA_ITERATIONS:
        game_map.nudge_camera(Vector2(3.0, -2.0))
        game_map.nudge_camera(Vector2(-3.0, 2.0))
    var pan_elapsed := Time.get_ticks_usec() - pan_started

    var province_pick_started := Time.get_ticks_usec()
    for _iteration in PICK_ITERATIONS:
        game_map.call("_province_at", seoul_screen)
    var province_pick_elapsed := Time.get_ticks_usec() - province_pick_started

    var city_pick_started := Time.get_ticks_usec()
    for _iteration in PICK_ITERATIONS:
        game_map.call("_city_at", seoul_screen)
    var city_pick_elapsed := Time.get_ticks_usec() - city_pick_started

    var tile := game_map.world_map.tile_at_world(seoul_world)
    var chunk_x := int(tile.x / game_map.world_map.chunk_size)
    var chunk_y := int(tile.y / game_map.world_map.chunk_size)
    var textures_before := int(
        game_map.world_map.performance_metrics().get("texture_generations", 0)
    )
    var mode_started := Time.get_ticks_usec()
    for mode in StrategicMap.MODE_LABELS.keys():
        game_map.set_mode(String(mode))
        game_map.world_map.chunk_texture(
            chunk_x,
            chunk_y,
            game_map.map_mode,
            game_map.countries,
            game_map.provinces,
            game_map.player_country_id,
            game_map.relations,
            game_map.wars,
            int(game_map.performance_metrics().get("visual_revision", 0))
        )
    var mode_elapsed := Time.get_ticks_usec() - mode_started
    var world_metrics: Dictionary = game_map.world_map.performance_metrics()
    var map_metrics: Dictionary = game_map.performance_metrics()

    _report("scenario_first_entry_us", scenario_elapsed)
    _report("country_screen_entry_us", country_elapsed)
    _report("game_screen_entry_us", game_elapsed)
    _report("snapshot_apply_total_us", snapshot_elapsed)
    _report("snapshot_apply_average_us", float(snapshot_elapsed) / SNAPSHOT_ITERATIONS)
    _report("turn_update_us", turn_elapsed)
    _report("zoom_pair_average_us", float(zoom_elapsed) / CAMERA_ITERATIONS)
    _report("pan_pair_average_us", float(pan_elapsed) / CAMERA_ITERATIONS)
    _report("province_hover_average_us", float(province_pick_elapsed) / PICK_ITERATIONS)
    _report("city_hover_average_us", float(city_pick_elapsed) / PICK_ITERATIONS)
    _report("mode_switch_total_us", mode_elapsed)
    _report("visible_chunks", game_map.visible_chunk_count)
    _report("rendered_tiles", game_map.last_rendered_tile_count)
    _report("spatial_index_rebuilds", map_metrics.get("spatial_index_rebuilds", 0))
    _report("runtime_binding_rebuilds", world_metrics.get("runtime_binding_rebuilds", 0))
    _report("texture_generations", world_metrics.get("texture_generations", 0))
    _report("mode_texture_generations", int(world_metrics.get("texture_generations", 0)) - textures_before)
    _report("cached_chunk_textures", world_metrics.get("cached_chunks", 0))
    _report("cached_overviews", world_metrics.get("cached_overviews", 0))
    _report("static_data_loads", world_metrics.get("static_data_loads", 0))
    _report("static_data_reuses", world_metrics.get("static_data_reuses", 0))

    scenario_map.queue_free()
    country_map.queue_free()
    game_map.queue_free()
    await process_frame
    quit(0)


func _create_map() -> StrategicMap:
    var map := StrategicMap.new()
    map.size = Vector2(1280, 720)
    get_root().add_child(map)
    return map


func _report(name: String, value: Variant) -> void:
    if value is float:
        print("MAP_BENCHMARK %s=%.2f" % [name, value])
    else:
        print("MAP_BENCHMARK %s=%s" % [name, str(value)])
