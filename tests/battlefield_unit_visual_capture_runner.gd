extends SceneTree

const GatewayScript = preload("res://src/presentation/strategy_gateway.gd")
const StrategicMapScript = preload("res://src/map/strategic_map.gd")
const CAPTURE_PATH := "user://battlefield_unit_visual.png"

var finished := false


func _initialize() -> void:
	var watchdog := create_timer(18.0)
	watchdog.timeout.connect(func():
		if not finished:
			push_error("Battlefield visual capture timed out")
			quit(1)
	)
	call_deferred("_run")


func _run() -> void:
	var gateway = GatewayScript.new()
	if not gateway.load_local_catalog():
		push_error("Could not load scenario for battlefield capture")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var map = StrategicMapScript.new()
	map.show_battlefield_units = true
	map.size = Vector2(1280, 720)
	viewport.add_child(map)
	var capture_snapshot: Dictionary = gateway.snapshot()
	capture_snapshot["army_groups"] = []
	map.set_snapshot(capture_snapshot)
	await process_frame
	map.frame_world()
	map.go_to_lonlat(123.8, 39.0, 0.95)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Battlefield visual capture image was unavailable")
		quit(1)
		return
	var output_path := ProjectSettings.globalize_path(CAPTURE_PATH)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Battlefield visual capture failed: %s" % error_string(error))
		quit(1)
		return
	print("BATTLEFIELD_UNIT_CAPTURE=%s" % output_path)
	print("BATTLEFIELD_UNIT_STATS=%s" % map.battlefield_render_stats())
	finished = true
	map.queue_free()
	viewport.queue_free()
	quit(0)
