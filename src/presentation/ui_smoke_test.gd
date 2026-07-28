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
    check(app.selected_province==1,"left click selects a Province")
    var old_zoom:=map.zoom; var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.position=map.size*0.5; map._gui_input(wheel)
    check(map.zoom>old_zoom,"wheel zooms toward mouse position")
    check(not map._spatial_buckets.is_empty(),"Province spatial picking index is built")
    map.set_interaction_state(StrategicMap.InputState.CHOOSING_MOVE_TARGET,1)
    var drag_press:=InputEventMouseButton.new(); drag_press.button_index=MOUSE_BUTTON_RIGHT; drag_press.pressed=true; drag_press.position=map.size*0.5; map._gui_input(drag_press)
    var drag_motion:=InputEventMouseMotion.new(); drag_motion.position=map.size*0.5+Vector2(24,16); map._gui_input(drag_motion)
    var drag_release:=InputEventMouseButton.new(); drag_release.button_index=MOUSE_BUTTON_RIGHT; drag_release.pressed=false; drag_release.position=drag_motion.position; map._gui_input(drag_release)
    check(map.input_state==StrategicMap.InputState.CHOOSING_MOVE_TARGET,"panning restores pending command input state")
    map.clear_interaction()
    for mode in StrategicMap.MODE_LABELS.keys(): map.set_mode(String(mode)); check(map.map_mode==String(mode),"map mode switches: "+String(mode))
    app.selected_province=1; app._queue_recruit(); check(app.gateway.commands().size()==1,"recruit command enters queue")
    app.pending_source=1; app.pending_kind="move"; app.pending_amount=5
    app._map_target(4)
    var queued: Array = app.gateway.commands()
    check(queued.size()==2,"move command enters queue")
    if queued.size()>1:
        var move_command:Dictionary=queued[1]
        check(move_command.payload.to_id==4,"move destination is preserved")
        app._cancel_queued(int(move_command.id))
        check(app.gateway.commands().size()==1,"command cancellation updates queue")
    app.selected_province=2; app._open_diplomacy(); check(app.diplomacy_dialog.visible,"diplomacy panel opens for foreign country"); app.diplomacy_dialog.hide()
    app._queue_diplomacy("declare_war","BOR",50,15); check(app.gateway.commands().size()==2,"diplomacy command enters queue")
    app._open_peace(); check(app.peace_dialog.visible,"peace negotiation panel opens"); app._close_peace()
    app.gateway.submit_turn(); await process_frame
    check(app.logs.size()>0,"turn request and notifications produce bounded log entries")
    check(app.logs.size()<=app.LOG_LIMIT,"event log respects recent-entry limit")
    app.queue_free(); await process_frame
    if failures.is_empty():
        print("UI_SMOKE_OK")
        quit(0)
    else:
        print("UI_SMOKE_FAILED: ", failures)
        quit(1)
