extends SceneTree


var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var gateway := StrategyGateway.new()
    _expect(gateway.load_local_catalog(), "East Asia scenario loads for map UX tests")
    if not failures.is_empty():
        _finish()
        return

    var map := StrategicMap.new()
    map.size = Vector2(1280, 720)
    get_root().add_child(map)
    map.set_snapshot(gateway.snapshot())
    await process_frame
    await process_frame

    _expect(map.world_map != null, "geographic WorldMapData is available")
    if map.world_map == null:
        map.queue_free()
        _finish()
        return

    _test_projection_orientation(map.world_map)
    _test_projection_round_trip(map.world_map)
    await _test_selection_and_drag(map)
    await _test_cache_revisions(map, gateway)
    _test_public_navigation_api(map)
    _test_command_feedback(map)

    map.queue_free()
    await process_frame
    _finish()


func _test_projection_orientation(world_map: WorldMapData) -> void:
    var beijing := world_map.city_position_for("beijing")
    var pyongyang := world_map.city_position_for("pyongyang")
    var seoul := world_map.city_position_for("seoul")
    var busan := world_map.city_position_for("busan")
    var jeju := world_map.city_position_for("jeju")
    var tokyo := world_map.city_position_for("tokyo")

    _expect(beijing.x < seoul.x, "Beijing is west of Seoul")
    _expect(pyongyang.x < seoul.x and pyongyang.y < seoul.y, "Pyongyang is northwest of Seoul")
    _expect(busan.x > seoul.x and busan.y > seoul.y, "Busan is southeast of Seoul")
    _expect(jeju.y > seoul.y, "Jeju is south of Seoul")
    _expect(tokyo.x > seoul.x, "Tokyo is east of Seoul")

    var peninsula_axis := pyongyang - busan
    var angle_from_up := rad_to_deg(
        atan2(absf(peninsula_axis.x), absf(peninsula_axis.y))
    )
    _expect(
        angle_from_up <= 28.0,
        "Korean peninsula axis is not over-rotated (%.2f degrees)" % angle_from_up
    )


func _test_projection_round_trip(world_map: WorldMapData) -> void:
    var anchors := [
        Vector2(116.4074, 39.9042), # Beijing
        Vector2(125.7625, 39.0392), # Pyongyang
        Vector2(126.9780, 37.5665), # Seoul
        Vector2(129.0756, 35.1796), # Busan
        Vector2(126.5312, 33.4996), # Jeju
        Vector2(139.6917, 35.6895) # Tokyo
    ]
    for anchor in anchors:
        var recovered := world_map.lonlat_from_world(
            world_map.world_from_lonlat(anchor.x, anchor.y)
        )
        _expect(
            recovered.distance_to(anchor) < 0.001,
            "lon/lat round trip is stable for %.3f, %.3f" % [anchor.x, anchor.y]
        )


func _test_selection_and_drag(map: StrategicMap) -> void:
    map.frame_play_area()
    var seoul_position := map.world_map.city_position_for("seoul")
    var seoul_screen := seoul_position * map.zoom + map.pan
    var seoul_province_id := int(map.call("_province_at", seoul_screen))
    _expect(seoul_province_id != -1, "Seoul has a pickable province")
    _expect(String(map.call("_city_at", seoul_screen)) == "seoul", "Seoul city has priority hit area")

    var click_log: Array[String] = []
    map.city_selected.connect(
        func(city_id: String) -> void:
            click_log.append("city:" + city_id)
    )
    map.province_selected.connect(
        func(province_id: int) -> void:
            click_log.append("province:%d" % province_id)
    )

    map._gui_input(_left_button(seoul_screen, true))
    map._gui_input(_left_button(seoul_screen, false))
    _expect(
        not click_log.is_empty() and click_log[0] == "city:seoul",
        "city signal is emitted before province selection"
    )
    _expect(map.selected_city_id == "seoul", "clicked city becomes selected")
    _expect(seoul_province_id in map.selected_province_ids, "city click retains underlying province selection")

    for tested_zoom in [0.08, 0.72, 4.0, 8.0]:
        var screen_radius := map.city_pick_radius_for_zoom(float(tested_zoom)) * float(tested_zoom)
        _expect(
            is_equal_approx(screen_radius, 10.0),
            "city click radius remains a constant screen-space target at zoom %.2f" % tested_zoom
        )

    var before_pan := map.pan
    var before_selection := map.selected_province_ids.duplicate()
    map._gui_input(_left_button(seoul_screen, true))
    map._gui_input(_mouse_motion(seoul_screen + Vector2(28.0, 12.0)))
    map._gui_input(_left_button(seoul_screen + Vector2(28.0, 12.0), false))
    _expect(map.pan.distance_to(before_pan) > 0.1, "left drag pans the map")
    _expect(
        map.selected_province_ids == before_selection,
        "left drag does not emit an accidental province selection"
    )

    var shift_origin := seoul_screen - Vector2(22.0, 22.0)
    map._gui_input(_left_button(shift_origin, true, true))
    map._gui_input(_mouse_motion(seoul_screen + Vector2(22.0, 22.0)))
    map._gui_input(_left_button(seoul_screen + Vector2(22.0, 22.0), false, true))
    _expect(
        seoul_province_id in map.selected_province_ids,
        "Shift drag rectangle adds the enclosed province"
    )


func _test_cache_revisions(map: StrategicMap, gateway: StrategyGateway) -> void:
    map.go_to_lonlat(126.9780, 37.5665, 1.2)
    map.set_mode("political")
    var unchanged_snapshot := gateway.snapshot()
    var index_rebuilds_before := map.spatial_index_rebuild_count
    var map_metrics_before: Dictionary = map.world_map.performance_metrics()
    var binding_rebuilds_before := int(map_metrics_before.get("runtime_binding_rebuilds", 0))

    map.set_snapshot(unchanged_snapshot)
    _expect(
        map.spatial_index_rebuild_count == index_rebuilds_before,
        "identical geometry does not rebuild the spatial index"
    )
    _expect(
        int(map.world_map.performance_metrics().get("runtime_binding_rebuilds", 0))
        == binding_rebuilds_before,
        "identical province mapping does not rebind runtime IDs"
    )

    var seoul_world := map.world_map.world_from_lonlat(126.9780, 37.5665)
    var tile := map.world_map.tile_at_world(seoul_world)
    var chunk_x := int(tile.x / map.world_map.chunk_size)
    var chunk_y := int(tile.y / map.world_map.chunk_size)
    var local_x := posmod(tile.x, map.world_map.chunk_size)
    var local_y := posmod(tile.y, map.world_map.chunk_size)
    var visual_revision_before := int(map.performance_metrics().get("visual_revision", 0))
    var before_texture := map.world_map.chunk_texture(
        chunk_x,
        chunk_y,
        map.map_mode,
        map.countries,
        map.provinces,
        map.player_country_id,
        map.relations,
        map.wars,
        visual_revision_before
    )
    var before_color := before_texture.get_image().get_pixel(local_x, local_y)
    var texture_generations_before := int(
        map.world_map.performance_metrics().get("texture_generations", 0)
    )

    map.set_snapshot(unchanged_snapshot)
    var same_texture := map.world_map.chunk_texture(
        chunk_x,
        chunk_y,
        map.map_mode,
        map.countries,
        map.provinces,
        map.player_country_id,
        map.relations,
        map.wars,
        int(map.performance_metrics().get("visual_revision", 0))
    )
    _expect(
        int(map.world_map.performance_metrics().get("texture_generations", 0))
        == texture_generations_before,
        "unchanged state reuses chunk texture revision"
    )
    _expect(
        same_texture == before_texture,
        "unchanged chunk request returns cached texture"
    )

    var changed_snapshot := gateway.snapshot()
    var seoul_screen := seoul_world * map.zoom + map.pan
    var seoul_province_id := int(map.call("_province_at", seoul_screen))
    var changed_province: Dictionary = changed_snapshot.get("provinces", {}).get(seoul_province_id, {})
    var previous_owner := String(changed_province.get("owner", ""))
    changed_province["owner"] = "goguryeo" if previous_owner != "goguryeo" else "baekje"
    changed_snapshot["turn"] = int(changed_snapshot.get("turn", 1)) + 1
    map.set_snapshot(changed_snapshot)

    var visual_revision_after := int(map.performance_metrics().get("visual_revision", 0))
    var after_texture := map.world_map.chunk_texture(
        chunk_x,
        chunk_y,
        map.map_mode,
        map.countries,
        map.provinces,
        map.player_country_id,
        map.relations,
        map.wars,
        visual_revision_after
    )
    var after_color := after_texture.get_image().get_pixel(local_x, local_y)
    _expect(
        visual_revision_after > visual_revision_before,
        "changed state creates a later visual revision"
    )
    _expect(
        after_color != before_color,
        "turn update does not reuse a stale political texture"
    )
    _expect(
        map.turn_update_time_us >= 0,
        "turn update timing is recorded"
    )

    var texture_count_before_modes := int(
        map.world_map.performance_metrics().get("texture_generations", 0)
    )
    for mode in ["terrain", "economy", "war", "political"]:
        map.set_mode(mode)
        map.world_map.chunk_texture(
            chunk_x,
            chunk_y,
            map.map_mode,
            map.countries,
            map.provinces,
            map.player_country_id,
            map.relations,
            map.wars,
            int(map.performance_metrics().get("visual_revision", 0))
        )
    _expect(
        int(map.world_map.performance_metrics().get("texture_generations", 0))
        > texture_count_before_modes,
        "mode changes receive distinct texture cache entries"
    )


func _test_public_navigation_api(map: StrategicMap) -> void:
    map.set_city_highlights(["seoul"], ["busan"])
    map.set_city_navigation_order(["seoul", "busan", "tokyo"])
    _expect(map.select_city("seoul", false), "select_city accepts a known city")
    var next_city := map.select_next_city(1)
    _expect(next_city == "busan", "select_next_city follows supplied navigation order")
    var centered := map.world_map.city_position_for(next_city) * map.zoom + map.pan
    _expect(
        centered.distance_to(map.size * 0.5) < 0.01,
        "focus_city centers the exact city coordinate"
    )

    map.frame_play_area()
    var seoul_centered := (
        map.world_map.city_position_for("seoul") * map.zoom + map.pan
    )
    _expect(
        seoul_centered.distance_to(map.size * 0.5) < 0.01,
        "frame_play_area starts at a Korea-useful center"
    )


func _test_command_feedback(map: StrategicMap) -> void:
    var rejected_reasons: Array[String] = []
    map.command_target_rejected.connect(
        func(reason: String, _source_id: int, _target_id: int) -> void:
            rejected_reasons.append(reason)
    )
    map.set_interaction_state(StrategicMap.InputState.CHOOSING_MOVE_TARGET, 1)
    map.set_command_target_validation([2], {1: "source province is not a target"})
    map.call("_handle_target_click", 1)
    _expect(
        not rejected_reasons.is_empty(),
        "invalid command target emits a reason through the public signal"
    )
    map.clear_interaction()


func _left_button(
    position: Vector2,
    pressed: bool,
    shift_pressed := false
) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = position
    event.global_position = position
    event.pressed = pressed
    event.shift_pressed = shift_pressed
    return event


func _mouse_motion(position: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = position
    event.global_position = position
    return event


func _expect(condition: bool, label: String) -> void:
    if condition:
        print("[PASS] %s" % label)
    else:
        failures.append(label)
        push_error("[FAIL] %s" % label)


func _finish() -> void:
    if failures.is_empty():
        print("Map performance and UX test: PASS")
        quit(0)
    else:
        push_error("Map performance and UX test: %d failure(s)" % failures.size())
        quit(1)
