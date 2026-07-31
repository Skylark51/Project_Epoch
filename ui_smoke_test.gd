extends SceneTree

var failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func check(condition: bool, message: String) -> void:
    if condition:
        print("PASS: ", message)
    else:
        failures.append(message)
        push_error("FAIL: " + message)

func _run() -> void:
    var packed := load("res://src/main.tscn") as PackedScene
    check(packed != null, "main scene loads")
    if packed == null:
        quit(1); return
    var app := packed.instantiate()
    root.add_child(app)
    await process_frame
    await process_frame
    check(app.screens[app.ScreenState.START].visible, "start screen is visible immediately")
    check(not app.screens[app.ScreenState.GAME].visible, "game screen does not flash before selection")
    var start_screen: Control = app.screens[app.ScreenState.START]
    var classic_frame := start_screen.find_child("ClassicMenuFrame", true, false) as Control
    var start_actions := start_screen.find_child("StartMenuActions", true, false) as VBoxContainer
    check(classic_frame != null and classic_frame.size.x >= 600.0, "classic start screen frame has a strong visual hierarchy")
    check(start_actions != null and start_actions.get_child_count() == 4, "classic start screen keeps all four menu actions")
    check(start_screen.find_child("StartTitle", true, false) != null, "classic start screen exposes its title landmark")
    for country_resolution in [Vector2i(1024,576),Vector2i(1280,720),Vector2i(1920,1080)]:
        root.size=country_resolution
        app._show(app.ScreenState.COUNTRY)
        await process_frame
        await process_frame
        var responsive_map := app.maps[app.ScreenState.COUNTRY] as StrategicMap
        var start_button_bottom: float = app.ui.country_start_button.global_position.y + app.ui.country_start_button.size.y
        var dossier_bottom: float = app.ui.country_dossier.global_position.y + app.ui.country_dossier.size.y
        check(responsive_map.size.x >= 450.0 and responsive_map.size.y >= 300.0, "country map stays usable at %s" % country_resolution)
        check(start_button_bottom <= app.size.y+0.5, "country start button is fully visible at %s" % country_resolution)
        check(dossier_bottom <= app.size.y+0.5, "ruler dossier does not clip at %s" % country_resolution)
    var country_map := app.maps[app.ScreenState.COUNTRY] as StrategicMap
    check(country_map.name == "CountrySelectionMap", "country selection map has a stable UI landmark")
    app._select_country("goguryeo")
    await process_frame
    check(app.ui.ruler_portrait.texture != null, "selecting a country reveals its ruler portrait")
    check(country_map.zoom >= 1.34, "selecting a country zooms the central map into its starting region")
    check("해무진" in app.ui.ruler_name.text, "selected ruler identity matches the country")
    app.ui.ruler_name_input.text="무휼"; app._on_ruler_name_changed("무휼")
    check(String(app._ruler_profile("goguryeo").name)=="무휼", "player can directly replace the selected country's ruler name")
    check(app.ui.country_start_button.text == "이 세력으로 개척 연대기 시작", "country screen presents a founding start rather than an established capital")
    check(app.ui.has("ruler_tween"), "ruler portrait entrance animation starts on selection")
    check(app._annal_entry("백제가 한성 권역에 들다.").begins_with("[서기 300년]"), "historical notifications use annal-style dating")
    root.size=Vector2i(1024,576)
    await process_frame
    app._start_game()
    await process_frame
    await process_frame
    check(app.ui.game_center.get_child(0) is PanelContainer, "redundant macro buttons are removed from above the map tiles")
    var governance_component=app.get_node_or_null("GovernanceDashboard")
    check(governance_component!=null and governance_component.launcher.get_parent()==app.ui.governance_slot, "governance and rebellion launcher lives in the management tab instead of covering the top bar")
    check(app.ui.first_decree_overlay.visible, "the ruler's first founding decree opens immediately after game start")
    check("아직 이 땅에 우리의 도시는 없다" in app.ui.first_decree_text.text and "첫 도시" in app.ui.first_decree_text.text, "opening explicitly begins before the first city is founded")
    check("무휼의 첫 개척령" in app.ui.first_decree_title.text, "opening decree uses the player-defined ruler name")
    check("첫 도시의 개척" in String(app.logs.back().message) and "도읍지를" not in String(app.logs.back().message), "opening annal does not assume an existing capital")
    var decree_bottom: float = app.ui.first_decree_panel.global_position.y + app.ui.first_decree_panel.size.y
    check(decree_bottom <= app.size.y+0.5, "first founding decree remains fully visible on a compact 16:9 screen")
    app._close_first_decree()
    check(not app.ui.first_decree_overlay.visible, "reviewing the founding decree returns control to the map")
    check("첫 도시의 터" in String(app.logs.back().message), "founding-site search creates an annal-style event")
    check("첫 과업" in app.ui.action_status.text, "map UI carries the first-city founding objective")
    var founding_map := app._game_map() as StrategicMap
    check(founding_map.zoom >= 1.44, "game starts zoomed into the selected founding region")
    check(app.founding_sites.is_empty() and founding_map.founding_tile_selection_enabled, "the opening task enables direct tile selection instead of fixed border candidates")
    check(founding_map.map_mode == "resources", "opening placement switches to the tile-resource view")
    founding_map.queue_redraw()
    await process_frame
    check(founding_map._last_drawn_texts.size() >= 3, "strong regional zoom reveals multiple real place names")
    var label_collision_free := true
    for left_index in range(founding_map._last_drawn_text_rects.size()):
        for right_index in range(left_index+1,founding_map._last_drawn_text_rects.size()):
            if founding_map._last_drawn_text_rects[left_index].intersects(founding_map._last_drawn_text_rects[right_index]): label_collision_free=false
    check(label_collision_free, "visible map place names do not overlap")
    var chosen_tile:=Vector2i(-1,-1)
    for index_value in founding_map.world_map.assigned_indices:
        var tile_index:=int(index_value); var tile:=Vector2i(tile_index%founding_map.world_map.width,tile_index/founding_map.world_map.width)
        if founding_map.world_map.province_id(tile.x,tile.y)!=app.founding_region_id: continue
        if not bool(app.tile_territory.can_found_initial_city(founding_map.world_map,tile,app.selected_country).get("ok",false)): continue
        var interior:=true
        for offset in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
            if founding_map.world_map.province_id(tile.x+offset.x,tile.y+offset.y)!=app.founding_region_id: interior=false
        if interior: chosen_tile=tile; break
    check(chosen_tile.x>=0, "an interior settleable tile exists inside the starting region")
    var chosen_resource:Dictionary=founding_map.world_map.resource_at(chosen_tile.x,chosen_tile.y)
    check(String(chosen_resource.get("id","")) in ["grain","wood","iron","gold"], "every selected land tile exposes a Civilization-style resource")
    app._founding_tile_pick(chosen_tile)
    check(app.founding_sites.size()==1 and Vector2i(app.founding_sites[0].tile)==chosen_tile, "clicking any valid interior tile creates the selected founding site")
    var first_site: Dictionary = app.founding_sites[0]
    check(app.founding_dialog != null and app.founding_dialog.visible, "clicking a chosen tile opens its terrain and resource confirmation")
    app._confirm_founding_site(first_site)
    if app.founding_dialog != null: app.founding_dialog.hide()
    await process_frame
    check(app.founding_site_confirmed and app.selected_founding_site_id == String(first_site.id), "the directly clicked tile can be confirmed")
    check(app.city_name_dialog != null and app.city_name_dialog.visible, "confirming a site immediately opens direct city naming")
    check(app.city_name_input.text == "졸본", "city naming starts with a historical recommendation")
    app.city_name_input.text="새국내"
    app._confirm_city_name()
    await process_frame
    check(app.founded_city_name == "새국내", "player can freely replace the recommended city name")
    check(app.tile_city_id != "" and app.tile_territory.has_capital("goguryeo"), "city naming founds one real capital on the selected map tile")
    check(app.tile_territory.managed_tiles(app.tile_city_id).size() >= 4, "new capital immediately owns its local tile management area")
    check(app.first_construction_dialog != null and app.first_construction_dialog.visible, "city naming proceeds directly to the first construction choice")
    check(String(app.FIRST_CONSTRUCTIONS[app._recommended_first_construction()].name) in app.ui.construction_recommendation.text, "founding resource produces a highlighted construction recommendation")
    check(app.ui.first_construction_buttons.size() == 3, "all three first constructions remain directly selectable")
    check(app.settlement_preview.variant == app._recommended_first_construction(), "recommended construction is previewed visually")
    check(app._game_map().settlement_markers.size() == 1 and String(app._game_map().settlement_markers[0].appearance) == "camp", "named city first appears as a temporary pioneer camp")
    var appearances: Dictionary = {}
    for construction in app.FIRST_CONSTRUCTIONS.values(): appearances[String(construction.appearance)] = true
    check(appearances.size() == 3, "each first construction owns a distinct settlement appearance")
    app._preview_first_construction("palisade")
    check(app.settlement_preview.variant == "palisade", "hover preview can compare a non-recommended city appearance")
    check(app.settlement_preview.view_mode == "three_quarter", "settlement preview uses a three-quarter overhead view")
    check(app.settlement_preview._city_textures.size() == 6 and app.settlement_preview.visual_asset_key() == "palisade", "settlement preview resolves the replaceable three-quarter SVG asset pack")
    check(app._game_map()._city_visual_textures.size() == 6, "central map loads the same replaceable city SVG asset pack")
    check(FileAccess.file_exists("res://docs/CODEX2_CITY_VISUAL_HANDOFF_KO.txt"), "Codex2 visual redesign handoff is included")
    app._choose_first_construction("palisade")
    check(app.first_construction_id == "palisade", "player can directly choose a non-recommended first construction")
    check(app.first_construction_stage == 1 and int(app._game_map().settlement_markers[0].stage) == 1, "first construction begins with surveying and material staging")
    app._advance_first_construction_stage()
    check(app.first_construction_stage == 2 and int(app._game_map().settlement_markers[0].stage) == 2, "construction advances to visible foundations and framing")
    app._advance_first_construction_stage()
    check(app.first_construction_stage == 3 and int(app._game_map().settlement_markers[0].stage) == 3, "construction reaches the completed visual stage")
    var tile_center:Vector2i=app._tile_city_center()
    check(int(app.tile_territory.tile_state(app._game_map().world_map,tile_center).get("facility_levels",{}).get("fort",0))==1, "completed founding project upgrades the matching center-tile facility")
    await process_frame
    check(app.settler_dialog != null and app.settler_dialog.visible, "the thirty-household settler situation follows the first completed construction")
    check(app.ui.settler_choice_buttons.size() == 3, "settler situation offers full acceptance, selective acceptance, and refusal")
    app._choose_settler_response("selective")
    check(app.settler_outcome == "selective" and app.city_households == 18, "selective acceptance settles eighteen households")
    check(app.tile_territory.households(app.tile_city_id).size()==18, "accepted households enter the real tile-assignment pool")
    check(int(app.city_population_profile.artisans) == 7 and app.city_food_reserve == 90 and app.city_reputation == 52, "settler choice applies population, food, and reputation consequences")
    check(int(app._game_map().settlement_markers[0].households) == 18, "settler population feeds the central-map city scale")
    check(app._game_map().settlement_visual_key(app._game_map().settlement_markers[0]) == "palisade", "central map keeps the completed three-quarter city type after population growth")
    check("18" in String(app.logs.back().message), "settler decision enters the annal log")
    await process_frame
    check(app.priority_project_dialog != null and app.priority_project_dialog.visible, "settler decision proceeds to the first operating-project council")
    check(app.ui.priority_project_recommendation == "workshop", "city population and reserves produce a contextual project recommendation")
    check(app.ui.priority_project_buttons.size() == 3, "irrigation, workshop, and outpost all remain directly selectable")
    check(not app.ui.priority_project_buttons.irrigation.disabled and not app.ui.priority_project_buttons.outpost.disabled, "non-recommended projects are not locked")
    app._choose_priority_project("irrigation")
    check(app.first_priority_project_id == "irrigation", "player can choose a non-recommended operating project")
    check(app.city_food_capacity == 120 and app.city_food_reserve == 98, "irrigation applies immediate reserves and expanded food capacity")
    check(app.city_production == 2 and app.city_security == 0 and app.city_reputation == 55, "chosen operating project applies its distinct city consequences")
    check(app.founded_city_name in String(app.logs.back().message) and app._priority_project_name() in String(app.logs.back().message), "operating-project choice enters the annal log")
    check(String(app._game_map().settlement_markers[0].appearance) == "palisade", "completed construction keeps the chosen city silhouette")
    var city_marker: Dictionary = app._game_map().settlement_markers[0]
    var city_screen: Vector2 = Vector2(city_marker.position) * app._game_map().zoom + app._game_map().pan
    var city_double_click:=InputEventMouseButton.new(); city_double_click.button_index=MOUSE_BUTTON_LEFT; city_double_click.pressed=true; city_double_click.double_click=true; city_double_click.position=city_screen
    app._game_map()._gui_input(city_double_click)
    await process_frame
    check(app.city_detail_dialog != null and app.city_detail_dialog.visible, "double-clicking the city opens its detailed adjustment screen")
    var compact_city_size:Vector2i=app._city_detail_window_size(Vector2(1024,576))
    check(compact_city_size.x<1024 and compact_city_size.y<576, "city administration window scales inside a compact viewport")
    check(app.ui.city_detail_tabs.get_tab_count() == 3, "city administration separates overview, allocation, and tile management into stable tabs")
    check(app.tile_city_panel != null and app.tile_city_panel.managed_tile_button_count()>=4, "tile tab renders every managed city tile as an individual control")
    check("관리 타일" in app.tile_city_panel.summary_label.text and "건설력" in app.tile_city_panel.summary_label.text, "tile tab summarizes yields, households, resources, and construction capacity")
    var work_tile:=Vector2i(-1,-1)
    for tile_record in app.tile_territory.managed_tiles(app.tile_city_id):
        if String(tile_record.get("settlement_id","")).is_empty():
            work_tile=Vector2i(int(tile_record.get("column",-1)),int(tile_record.get("row",-1)))
            break
    app.tile_city_panel.select_tile(work_tile)
    app.tile_city_panel.assign_or_release_selected_household()
    check(bool(app.tile_territory.tile_state(app._game_map().world_map,work_tile).get("worked",false)), "tile tab assigns one idle household to a selected non-center tile")
    app.tile_city_panel.queue_selected_facility_upgrade()
    check(app.tile_territory.city_construction_status(app.tile_city_id).get("queue",[]).size()==1, "tile tab routes facility upgrades through the owning city's queue")
    check(FileAccess.file_exists("res://assets/ui/city_admin/population.svg") and FileAccess.file_exists("res://assets/ui/city_admin/security.svg"), "city administration indicators use replaceable UI assets")
    check(app.city_detail_preview.view_mode == "three_quarter" and app.city_detail_preview.construction_stage == 3, "city detail preserves the completed three-quarter visual")
    check(app.city_detail_preview.visual_asset_key() == "palisade", "city detail and central map share the same completed three-quarter asset")
    check(app.ui.city_allocation_preset_recommendation == "defense", "city conditions generate a contextual administration preset recommendation")
    check(app.ui.city_allocation_preset_buttons.size() == 3, "all administration presets remain directly selectable")
    app.ui.city_allocation_spins.labor.value=60; app.ui.city_allocation_spins.food.value=30; app.ui.city_allocation_spins.guard.value=20
    check(app.ui.city_allocation_apply.disabled and "110" in app.ui.city_allocation_total.text, "invalid allocation disables apply and exposes the current total")
    app._apply_city_allocation_preset("growth")
    check(int(app.ui.city_allocation_spins.labor.value)==55 and int(app.ui.city_allocation_spins.guard.value)==10, "a non-recommended administration preset remains selectable")
    check(not app.ui.city_allocation_apply.disabled and "100" in app.ui.city_allocation_total.text, "valid preset restores an applicable total")
    app.ui.city_allocation_spins.labor.value=50; app.ui.city_allocation_spins.food.value=30; app.ui.city_allocation_spins.guard.value=20
    app._apply_city_details()
    check(int(app.city_management.labor)==50 and int(app.city_management.guard)==20, "city detail applies direct labor, storage, and guard adjustments")
    check("건설 50, 비축 30, 경계 20" in String(app.logs.back().message), "city detail adjustment enters the annal log")
    var saved_campaign:Dictionary=app.gateway.campaign_save_data()
    check(String(saved_campaign.get("founded_city_name",""))=="새국내" and int(saved_campaign.get("first_construction_stage",0))==3, "autosave metadata contains the founded city and completed construction")
    check(String(saved_campaign.get("custom_ruler_names",{}).get("goguryeo",""))=="무휼", "autosave metadata preserves the player-defined ruler name")
    check(String(saved_campaign.get("settler_outcome",""))=="selective" and String(saved_campaign.get("first_priority_project_id",""))=="irrigation", "autosave metadata contains settler and operating-project decisions")
    check(int(saved_campaign.get("city_management",{}).get("labor",0))==50 and saved_campaign.get("logs",[]).size()>0, "autosave metadata contains administration allocation and annal history")
    check(String(saved_campaign.get("tile_city_id",""))!="" and saved_campaign.get("tile_territory",{}).get("settlements",{}).size()==1, "autosave persists the authoritative city and tile-management snapshot")
    var saved_log_count:int=app.logs.size()
    app.founded_city_name=""; app.first_construction_id=""; app.first_construction_stage=0; app.settler_outcome=""; app.first_priority_project_id=""; app.city_households=0; app.custom_ruler_names.clear()
    app.city_food_reserve=0; app.city_food_capacity=1; app.city_management={"labor":100,"food":0,"guard":0}; app.logs.clear(); app._game_map().set_settlement_markers([])
    app.tile_territory.reset(); app.tile_city_id=""
    app._load_game()
    await process_frame
    await process_frame
    check(app.founded_city_name=="새국내" and app.first_construction_id=="palisade" and app.first_construction_stage==3, "load-game restores the founded city and construction state")
    check(String(app._ruler_profile("goguryeo").name)=="무휼", "load-game restores the player-defined ruler name")
    check(app.settler_outcome=="selective" and app.first_priority_project_id=="irrigation" and app.city_households==18, "load-game restores settler and operating-project state")
    check(int(app.city_management.labor)==50 and app.city_food_capacity==120 and app.city_food_reserve==98, "load-game restores city administration resources and allocation")
    check(app.tile_city_id!="" and app.tile_territory.households(app.tile_city_id).size()==18, "load-game restores the city core and its household pool")
    check(app.tile_territory.city_construction_status(app.tile_city_id).get("queue",[]).size()==1 and app.tile_territory.worked_tiles(app.tile_city_id).size()==2, "load-game restores queued upgrades and individual worked tiles")
    check(app.logs.size()==saved_log_count and app._game_map().settlement_markers.size()==1, "load-game restores annal history and the central-map city marker")
    if app._game_map().settlement_markers.size()>0:
        check(String(app._game_map().settlement_markers[0].name)=="새국내" and int(app._game_map().settlement_markers[0].households)==18, "restored map marker preserves city identity and population")
    else:
        check(false, "restored map marker preserves city identity and population")
    check(not app.ui.first_decree_overlay.visible, "completed campaign load does not replay the opening decree")
    app._queue_settler_production()
    check(app.settler_orders.size()==1 and int(app.settler_orders[0].remaining_turns)==3, "capital can queue a settler with explicit food, wood, and turn costs")
    app._advance_settler_production(); app._advance_settler_production(); app._advance_settler_production()
    check(app.settler_units==1 and app.settler_orders.is_empty(), "settler production completes after three turns")
    app._begin_settler_founding()
    check(app.settler_founding_active and app._game_map().founding_tile_selection_enabled, "completed settler enters direct map-tile destination mode")
    var second_city_tile:=Vector2i(-1,-1)
    for index_value in app._game_map().world_map.assigned_indices:
        var tile_index:=int(index_value); var tile:=Vector2i(tile_index%app._game_map().world_map.width,tile_index/app._game_map().world_map.width)
        if bool(app.tile_territory.can_found_city(app._game_map().world_map,tile,app.selected_country).get("ok",false)):
            second_city_tile=tile; break
    check(second_city_tile.x>=0, "a valid destination exists outside the first city's exclusion radius")
    app._pick_settler_destination(second_city_tile)
    check(app.additional_city_dialog!=null and app.additional_city_dialog.visible, "settler destination click opens editable city naming")
    app.additional_city_name_input.text="두번째도시"; app._confirm_additional_city(); await process_frame
    check(app.settler_units==0 and app.tile_territory.snapshot().get("settlements",{}).size()==2, "founding a second city consumes exactly one produced settler")
    check(app._game_map().settlement_markers.size()==2, "additional city receives its own central-map settlement marker")
    for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
        root.size=resolution
        await process_frame
        app._show(app.ScreenState.GAME)
        await process_frame
        await process_frame
        var map:=app._game_map() as StrategicMap
        check(map.size.x>300 and map.size.y>240,"map has usable area at %s" % resolution)
        check(app.ui.bottom_tabs.size.y>=170,"bottom command panel remains visible at %s" % resolution)
        check(app.ui.province_detail.size.x>200,"province panel remains readable at %s" % resolution)
    var map:=app._game_map() as StrategicMap
    map.frame_world(); await process_frame
    var province:Dictionary=app.gateway.province(1); var center:=Vector2.ZERO
    for point in province.polygon: center+=Vector2(float(point[0]),float(point[1]))
    center/=float(province.polygon.size())
    var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=center*map.zoom+map.pan
    map._gui_input(click); await process_frame
    var click_release:=InputEventMouseButton.new(); click_release.button_index=MOUSE_BUTTON_LEFT; click_release.pressed=false; click_release.position=click.position; map._gui_input(click_release); await process_frame
    check(app.selected_province==1,"left click selects a Province")
    var old_zoom:=map.zoom; var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.position=map.size*0.5; map._gui_input(wheel)
    check(map.zoom>old_zoom,"wheel zooms toward mouse position")
    map.zoom=maxf(map.zoom,0.5); map.focus_province(1)
    var pan_before_left_drag:=map.pan
    var selected_before_left_drag: int = app.selected_province
    var left_drag_press:=InputEventMouseButton.new(); left_drag_press.button_index=MOUSE_BUTTON_LEFT; left_drag_press.pressed=true; left_drag_press.position=map.size*0.5; map._gui_input(left_drag_press)
    var left_drag_motion:=InputEventMouseMotion.new(); left_drag_motion.position=left_drag_press.position+Vector2(40,24); map._gui_input(left_drag_motion)
    var left_drag_release:=InputEventMouseButton.new(); left_drag_release.button_index=MOUSE_BUTTON_LEFT; left_drag_release.pressed=false; left_drag_release.position=left_drag_motion.position; map._gui_input(left_drag_release)
    check(map.pan.distance_to(pan_before_left_drag)>5.0,"holding and dragging the left mouse button pans the map")
    check(app.selected_province==selected_before_left_drag,"left-button panning does not change Province selection")
    var zoom_before_text_quality:=map.zoom
    map.zoom=4.0; map.queue_redraw(); await process_frame
    var screen_text_sizes_are_stable:=not map._screen_text_commands.is_empty()
    for text_command in map._screen_text_commands:
        var queued_font_size:=int(text_command.get("font_size",0))
        if queued_font_size<10 or queued_font_size>19: screen_text_sizes_are_stable=false
    check(screen_text_sizes_are_stable,"map labels render at stable screen-space font sizes when zoomed in")
    map.zoom=zoom_before_text_quality; map.queue_redraw(); await process_frame
    check(not map._spatial_buckets.is_empty(),"Province spatial picking index is built")
    var sea_pick_checked:=false
    if map.world_map != null:
        check(map.world_map.width==640 and map.world_map.height==480,"geographic world map is loaded for interaction")
        for row in range(map.world_map.height):
            for column in range(map.world_map.width):
                if map.world_map.terrain_id(column,row)<=2 and map.world_map.province_id(column,row)==-1:
                    var sea_center:=(Vector2(column,row)+Vector2(0.5,0.5))*map.world_map.tile_size
                    check(map._province_at(sea_center*map.zoom+map.pan)==-1,"sea tiles are visible but not selectable as Provinces")
                    sea_pick_checked=true
                    break
            if sea_pick_checked: break
    else:
        check(map.map_tiles.size()==28*18 and not map._tile_spatial_buckets.is_empty(),"continuous hex tile picking index is built")
        for tile_value in map.map_tiles:
            if tile_value is Dictionary and bool(tile_value.get("water",false)):
                var sea_center:=Vector2.ZERO
                for point in tile_value.get("polygon",[]): sea_center+=Vector2(float(point[0]),float(point[1]))
                sea_center/=6.0
                check(map._province_at(sea_center*map.zoom+map.pan)==-1,"sea tiles are visible but not selectable as Provinces")
                sea_pick_checked=true
                break
    check(sea_pick_checked,"at least one sea tile is available for interaction validation")
    map.set_interaction_state(StrategicMap.InputState.CHOOSING_MOVE_TARGET,1)
    var drag_press:=InputEventMouseButton.new(); drag_press.button_index=MOUSE_BUTTON_RIGHT; drag_press.pressed=true; drag_press.position=map.size*0.5; map._gui_input(drag_press)
    var drag_motion:=InputEventMouseMotion.new(); drag_motion.position=map.size*0.5+Vector2(24,16); map._gui_input(drag_motion)
    var drag_release:=InputEventMouseButton.new(); drag_release.button_index=MOUSE_BUTTON_RIGHT; drag_release.pressed=false; drag_release.position=drag_motion.position; map._gui_input(drag_release)
    check(map.input_state==StrategicMap.InputState.CHOOSING_MOVE_TARGET,"panning restores pending command input state")
    map.clear_interaction()
    for mode in StrategicMap.MODE_LABELS.keys(): map.set_mode(String(mode)); check(map.map_mode==String(mode),"map mode switches: "+String(mode))
    map.set_selected_provinces([1,2]); await process_frame
    check(app.selected_provinces.size()==2,"multi-selection propagates to Province management UI")
    app._simple_command("develop"); check(app.gateway.commands().size()==2,"one-click Province management queues a batch task")
    app.gateway.clear_commands()
    app._quick_drag_move(1,2); check(app.gateway.commands().size()==1,"drag-and-drop creates a movement task")
    app.gateway.clear_commands()
    app._toggle_governor(); check(app.governor_enabled,"Governor automation can be enabled")
    app._toggle_governor(); map.set_selected_provinces([1]); await process_frame
    app.selected_province=1; app._queue_recruit(); check(app.gateway.commands().size()==1,"recruit command enters queue")
    app.pending_source=1; app.pending_kind="move"; app.pending_amount=5
    app._map_target(2)
    var queued: Array = app.gateway.commands()
    check(queued.size()==2,"move command enters queue")
    if queued.size()>1:
        var move_command:Dictionary=queued[1]
        check(move_command.payload.to_id==2,"move destination is preserved")
        app._cancel_queued(int(move_command.id))
        check(app.gateway.commands().size()==1,"command cancellation updates queue")
    app.selected_province=4; app._open_diplomacy(); check(app.diplomacy_dialog.visible,"diplomacy panel opens for foreign country"); app.diplomacy_dialog.hide()
    app._queue_diplomacy("declare_war","baekje",50,15); check(app.gateway.commands().size()==2,"diplomacy command enters queue")
    app._open_peace(); check(app.peace_dialog.visible,"peace negotiation panel opens"); app._close_peace()
    app.gateway.submit_turn(); await process_frame
    check(int(app.gateway.snapshot().get("turn",1))==2,"core advances the turn and refreshes the UI snapshot")
    check(app.gateway.at_war("goguryeo","baekje"),"queued war declaration changes core diplomacy state")
    var saved_turn:=int(app.gateway.snapshot().get("turn",0))
    check(app.gateway.load_autosave(),"core autosave can be loaded from the start-screen flow")
    check(int(app.gateway.snapshot().get("turn",0))==saved_turn,"loaded snapshot preserves the processed turn")
    check(app.logs.size()>0,"turn request and notifications produce bounded log entries")
    check(app.logs.size()<=app.LOG_LIMIT,"event log respects recent-entry limit")
    app.queue_free(); await process_frame
    if failures.is_empty():
        print("UI_SMOKE_OK")
        quit(0)
    else:
        print("UI_SMOKE_FAILED: ", failures)
        quit(1)
