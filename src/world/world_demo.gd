extends Control

const WorldSession = preload("res://src/world/world_session.gd")
var world := WorldSession.new()
var selected_regions: Array[String] = []
var status_label: Label
var detail_label: RichTextLabel
var map_view: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	var result := world.startWorld("GOG")
	if not result.ok:
		status_label.text = "월드 로드 실패: %s" % result.get("errors", [])
		return
	world.world_changed.connect(_refresh)
	_refresh(world.snapshot())

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "PROJECT EPOCH · 서기 400년 동아시아 월드/내정 데모"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	header.add_spacer(true)
	for item in [["농경지 일괄 예약", _batch_farmland], ["자동 관리", _enable_auto], ["다음 도시", _next_city],
		["턴 진행", _advance], ["저장", _save], ["불러오기", _load]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		header.add_child(button)
	status_label = Label.new()
	status_label.text = "Ctrl+클릭으로 여러 도시 선택"
	root.add_child(status_label)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 950
	root.add_child(split)
	map_view = WorldMapView.new()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.region_clicked.connect(_region_clicked)
	split.add_child(map_view)
	detail_label = RichTextLabel.new()
	detail_label.bbcode_enabled = true
	detail_label.custom_minimum_size.x = 340
	split.add_child(detail_label)

func _refresh(snapshot: Dictionary) -> void:
	map_view.set_world(snapshot, selected_regions)
	status_label.text = "서기 %d년 %d월 · 턴 %d · 지역 %d · 세력 %d · 취락 %d" % [
		int(snapshot.date.year), int(snapshot.date.month), int(snapshot.turn),
		snapshot.regions.size(), snapshot.factions.size(), snapshot.settlements.size()]
	_refresh_detail()

func _region_clicked(region_id: String, additive: bool) -> void:
	if not additive:
		selected_regions.clear()
	if region_id in selected_regions:
		selected_regions.erase(region_id)
	else:
		selected_regions.append(region_id)
	var settlement_ids := []
	for region_value in selected_regions:
		var region: Dictionary = world.getRegion(region_value)
		if region.get("initial_settlement", null) != null:
			settlement_ids.append(String(region.initial_settlement))
	world.selectSettlements(settlement_ids)
	_refresh(world.snapshot())

func _refresh_detail() -> void:
	if selected_regions.is_empty():
		detail_label.text = "[font_size=20]지역을 선택하십시오[/font_size]\n\n색상은 세력 영향권, 점선 연결은 도로·수운·해로입니다."
		return
	var lines := ["[font_size=20][color=#e8cf8a]선택 지역 %d개[/color][/font_size]" % selected_regions.size()]
	for region_id in selected_regions:
		var region := world.getRegion(region_id)
		lines.append("\n[b]%s[/b] · %s · %s" % [region.display_name, region.terrain, region.border_state])
		lines.append("통제: %s / 확실성: %s" % [region.controller_id, region.historical_certainty])
		if region.get("initial_settlement", null) != null:
			var city := world.getSettlement(String(region.initial_settlement))
			lines.append("취락: %s · %s · 인구 %d" % [city.name, city.tier, int(city.resources.population)])
			lines.append("건설: %s" % [city.buildings])
	detail_label.text = "\n".join(lines)

func _batch_farmland() -> void:
	var result := world.queueBuildingForSelected("farmland")
	status_label.text = "일괄 예약: 성공 %d / 거부 %d" % [result.get("accepted", []).size(), result.get("rejected", []).size()]
	_refresh(world.snapshot())

func _enable_auto() -> void:
	for id in world.selected_settlement_ids:
		world.setCityAutomation(id, true, "balanced")
	status_label.text = "%d개 도시에 자동 관리를 설정했습니다." % world.selected_settlement_ids.size()

func _next_city() -> void:
	var city := world.getNextUnprocessedSettlement(world.state.selected_faction_id)
	if city.is_empty():
		status_label.text = "미처리 도시가 없습니다."
		return
	selected_regions = [String(city.region_id)]
	world.selectSettlements([String(city.id)])
	_refresh(world.snapshot())

func _advance() -> void:
	var result := world.advanceTurn()
	status_label.text = "턴 처리 완료 · 건설 완료 %d · 국경 변화 %d" % [
		result.get("construction_completed", []).size(), result.get("border_changes", []).size()]

func _save() -> void:
	var result := world.saveWorld()
	status_label.text = "저장 완료" if result.ok else "저장 실패: %s" % result.reason

func _load() -> void:
	var result := world.loadWorld()
	status_label.text = "불러오기 완료" if result.ok else "불러오기 실패: %s" % result.reason

class WorldMapView extends Control:
	signal region_clicked(region_id: String, additive: bool)
	var snapshot := {}
	var selected: Array[String] = []
	var scale_factor := 0.78
	var offset := Vector2(25, 15)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)

	func set_world(value: Dictionary, selected_regions: Array[String]) -> void:
		snapshot = value
		selected = selected_regions.duplicate()
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#101923"))
		if snapshot.is_empty():
			return
		for connection in snapshot.connections.values():
			var from_region: Dictionary = snapshot.regions.get(String(connection.from), {})
			var to_region: Dictionary = snapshot.regions.get(String(connection.to), {})
			if from_region.is_empty() or to_region.is_empty():
				continue
			var color := Color("#8c7a54")
			if String(connection.type) in ["waterway","sea_route"]:
				color = Color("#4d8ea8")
			draw_dashed_line(_point(from_region), _point(to_region), color, 2.0, 7.0)
		for region_id in snapshot.regions:
			var region: Dictionary = snapshot.regions[region_id]
			var point := _point(region)
			var faction: Dictionary = snapshot.factions.get(String(region.controller_id), {})
			var color := Color(String(faction.get("color", "#777777")))
			var radius := 10.0 if region.get("initial_settlement", null) != null else 6.0
			if String(region.border_state) == "contested":
				color = color.lerp(Color("#d89046"), 0.55)
			elif String(region.border_state) == "frontier":
				color = Color("#69695f")
			draw_circle(point, radius, color)
			draw_circle(point, radius, Color.WHITE if String(region_id) in selected else Color("#23272a"), false, 2.0)
			if region.get("initial_settlement", null) != null:
				draw_string(ThemeDB.fallback_font, point + Vector2(12, 4), String(region.display_name),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#eee5d2"))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var closest := ""
			var best := 18.0
			for region_id in snapshot.get("regions", {}):
				var distance := _point(snapshot.regions[region_id]).distance_to(event.position)
				if distance < best:
					best = distance
					closest = String(region_id)
			if not closest.is_empty():
				region_clicked.emit(closest, event.ctrl_pressed or event.shift_pressed)
			accept_event()

	func _point(region: Dictionary) -> Vector2:
		return Vector2(float(region.x), float(region.y)) * scale_factor + offset
