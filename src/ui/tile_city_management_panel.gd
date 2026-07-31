class_name TileCityManagementPanel
extends VBoxContainer

signal state_changed(message: String)

const FACILITIES := [
	{"id": "farmland", "name": "농경지"},
	{"id": "pasture", "name": "목축지"},
	{"id": "fishing", "name": "어장"},
	{"id": "lumber_camp", "name": "벌목장"},
	{"id": "mine", "name": "광산"},
	{"id": "workshop", "name": "작업장"},
	{"id": "market", "name": "시장"},
	{"id": "fort", "name": "방어 시설"},
]
const YIELD_LABELS := {
	"food": "식량",
	"production": "생산",
	"commerce": "상업",
	"security": "치안",
}

var manager
var world_map
var settlement_id := ""
var selected_tile := Vector2i(-1, -1)

var summary_label: Label
var detail_label: RichTextLabel
var action_message: Label
var tile_grid: GridContainer
var household_button: Button
var facility_picker: OptionButton
var queue_button: Button
var progress_button: Button
var tile_buttons: Dictionary = {}
var _managed_button_count := 0


func _ready() -> void:
	name = "타일 관리"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_interface()
	if manager != null:
		refresh()


func setup(manager_value, world_map_value, settlement_id_value: String) -> void:
	manager = manager_value
	world_map = world_map_value
	settlement_id = settlement_id_value
	var city := _city()
	if not city.is_empty():
		selected_tile = Vector2i(
			int(city.get("column", -1)),
			int(city.get("row", -1))
		)
	if is_node_ready():
		refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var city := _city()
	if city.is_empty() or manager == null or world_map == null:
		summary_label.text = "타일 관리 정보를 불러올 수 없습니다."
		detail_label.text = "[color=#d98a72]도시와 타일 상태의 연결이 끊어졌습니다.[/color]"
		household_button.disabled = true
		queue_button.disabled = true
		progress_button.disabled = true
		_clear_tile_grid()
		return
	var center := Vector2i(int(city.column), int(city.row))
	if selected_tile.x < 0:
		selected_tile = center
	var managed_tiles: Array = manager.managed_tiles(settlement_id)
	var households: Array = manager.households(settlement_id)
	var worked_count := 0
	var assigned_count := 0
	for tile_record in managed_tiles:
		if bool(tile_record.get("worked", false)):
			worked_count += 1
	for household in households:
		if not String(household.get("assigned_tile_key", "")).is_empty():
			assigned_count += 1
	var yield_status: Dictionary = manager.settlement_yields(world_map, settlement_id)
	var construction: Dictionary = manager.city_construction_status(settlement_id)
	var stockpile: Dictionary = construction.get("resource_stockpile", {})
	var queue: Array = construction.get("queue", [])
	summary_label.text = (
		"%s · 관리 타일 %d · 작업 %d · 가구 %d(배치 %d)\n"
		+ "도시 총생산  %s   ·   건설력 %.1f/턴   ·   대기 %d건   ·   목재 %d / 석재 %d / 철 %d"
	) % [
		String(city.get("name", "도시")),
		managed_tiles.size(),
		worked_count,
		households.size(),
		assigned_count,
		_yield_text(yield_status.get("yields", {})),
		float(construction.get("construction_power_per_turn", 0.0)),
		queue.size(),
		int(float(stockpile.get("wood", 0.0))),
		int(float(stockpile.get("stone", 0.0))),
		int(float(stockpile.get("iron", 0.0))),
	]
	_rebuild_tile_grid(center)
	_refresh_selected_detail(center)
	progress_button.disabled = queue.is_empty()


func managed_tile_button_count() -> int:
	return _managed_button_count


func select_tile(tile: Vector2i) -> void:
	selected_tile = tile
	refresh()


func assign_or_release_selected_household() -> void:
	var tile_record := _selected_tile_record()
	if tile_record.is_empty():
		_show_action("도시가 관리하는 타일을 먼저 선택하십시오.", false)
		return
	var assigned_id := String(tile_record.get("assigned_household_id", ""))
	var result: Dictionary
	if not assigned_id.is_empty():
		result = manager.unassign_household(settlement_id, assigned_id)
	else:
		var idle_household := _first_idle_household()
		if idle_household.is_empty():
			_show_action("배치할 유휴 가구가 없습니다.", false)
			return
		result = manager.assign_household_to_tile(
			world_map,
			settlement_id,
			String(idle_household.get("id", "")),
			selected_tile
		)
	if bool(result.get("ok", false)):
		var message := "가구 배치를 해제했습니다." if not assigned_id.is_empty() else "선택 타일에 가구를 배치했습니다."
		_show_action(message, true)
		state_changed.emit(message)
	else:
		_show_action(String(result.get("reason", "가구 배치를 변경하지 못했습니다.")), false)
	refresh()


func queue_selected_facility_upgrade() -> void:
	if facility_picker.item_count <= 0:
		return
	var facility_id := String(
		facility_picker.get_item_metadata(facility_picker.selected)
	)
	var result: Dictionary = manager.queue_tile_facility_upgrade(
		world_map,
		settlement_id,
		selected_tile,
		facility_id
	)
	if bool(result.get("ok", false)):
		var order: Dictionary = result.get("order", {})
		var message := "%s %d단계 건설을 도시 작업열에 등록했습니다." % [
			_facility_name(facility_id),
			int(order.get("target_level", 1)),
		]
		_show_action(message, true)
		state_changed.emit(message)
	else:
		_show_action(String(result.get("reason", "시설 건설을 등록하지 못했습니다.")), false)
	refresh()


func advance_construction_turn() -> void:
	var result: Dictionary = manager.advance_city_construction(
		world_map,
		settlement_id,
		1
	)
	if not bool(result.get("ok", false)):
		_show_action(String(result.get("reason", "건설을 진행하지 못했습니다.")), false)
		return
	var completed: Array = result.get("completed", [])
	var message := (
		"%d개 시설이 완공되었습니다." % completed.size()
		if not completed.is_empty()
		else "도시 건설력을 1턴 투입했습니다."
	)
	_show_action(message, true)
	state_changed.emit(message)
	refresh()


func _build_interface() -> void:
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _panel_style(Color("#18262a"), Color("#59684f"), 1))
	add_child(header_panel)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 13)
	summary_label.add_theme_color_override("font_color", Color("#d9d3bd"))
	summary_label.custom_minimum_size.y = 48
	header_panel.add_child(summary_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", _panel_style(Color("#101a1d"), Color("#38474a"), 1))
	body.add_child(map_panel)
	var map_box := VBoxContainer.new()
	map_box.add_theme_constant_override("separation", 6)
	map_panel.add_child(map_box)
	var map_caption := Label.new()
	map_caption.text = "도시 영향권 · 중심에서 최대 2타일"
	map_caption.add_theme_font_size_override("font_size", 13)
	map_caption.add_theme_color_override("font_color", Color("#c6b785"))
	map_box.add_child(map_caption)
	tile_grid = GridContainer.new()
	tile_grid.columns = 5
	tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile_grid.add_theme_constant_override("h_separation", 4)
	tile_grid.add_theme_constant_override("v_separation", 4)
	map_box.add_child(tile_grid)
	var legend := Label.new()
	legend.text = "도시: 중심 자동 작업   ·   가구: 배치됨   ·   유휴: 배치 가능   ·   어두운 칸: 영향권 밖"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 10)
	legend.add_theme_color_override("font_color", Color("#859497"))
	map_box.add_child(legend)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 275
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("#151d20"), Color("#4a5558"), 1))
	body.add_child(detail_panel)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 7)
	detail_panel.add_child(detail_box)
	var detail_title := Label.new()
	detail_title.text = "선택 타일"
	detail_title.add_theme_font_size_override("font_size", 16)
	detail_title.add_theme_color_override("font_color", Color("#dec783"))
	detail_box.add_child(detail_title)
	detail_label = RichTextLabel.new()
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_label.custom_minimum_size.y = 170
	detail_box.add_child(detail_label)
	household_button = Button.new()
	household_button.text = "유휴 가구 배치"
	household_button.custom_minimum_size.y = 36
	household_button.pressed.connect(assign_or_release_selected_household)
	detail_box.add_child(household_button)
	facility_picker = OptionButton.new()
	for facility in FACILITIES:
		facility_picker.add_item(String(facility.name))
		facility_picker.set_item_metadata(
			facility_picker.item_count - 1,
			String(facility.id)
		)
	facility_picker.item_selected.connect(_on_facility_selected)
	detail_box.add_child(facility_picker)
	queue_button = Button.new()
	queue_button.text = "시설 업그레이드 예약"
	queue_button.custom_minimum_size.y = 38
	queue_button.pressed.connect(queue_selected_facility_upgrade)
	detail_box.add_child(queue_button)
	progress_button = Button.new()
	progress_button.text = "건설 1턴 진행"
	progress_button.custom_minimum_size.y = 34
	progress_button.pressed.connect(advance_construction_turn)
	detail_box.add_child(progress_button)
	action_message = Label.new()
	action_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_message.add_theme_font_size_override("font_size", 11)
	action_message.custom_minimum_size.y = 30
	detail_box.add_child(action_message)


func _rebuild_tile_grid(center: Vector2i) -> void:
	_clear_tile_grid()
	for row_offset in range(-2, 3):
		for column_offset in range(-2, 3):
			var tile := center + Vector2i(column_offset, row_offset)
			var button := Button.new()
			button.custom_minimum_size = Vector2(70, 54)
			button.focus_mode = Control.FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			var tile_record: Dictionary = (
				manager.tile_state(world_map, tile)
				if world_map.contains(tile.x, tile.y)
				else {}
			)
			var managed := (
				not tile_record.is_empty()
				and String(tile_record.get("managing_settlement_id", "")) == settlement_id
			)
			button.disabled = not managed
			if managed:
				_managed_button_count += 1
				var terrain_name: String = world_map.terrain_name(
					int(tile_record.get("terrain_id", 0))
				)
				var state_name := "유휴"
				if String(tile_record.get("settlement_id", "")) == settlement_id:
					state_name = "도시"
				elif bool(tile_record.get("worked", false)):
					state_name = "가구"
				button.text = "%s\n%s" % [state_name, terrain_name]
				button.tooltip_text = _tile_tooltip(tile, tile_record)
				button.pressed.connect(select_tile.bind(tile))
			else:
				button.text = "·"
				button.tooltip_text = "현재 도시의 영향권 밖"
			_style_tile_button(button, managed, tile == selected_tile, tile == center)
			tile_grid.add_child(button)
			tile_buttons[_button_key(tile)] = button


func _clear_tile_grid() -> void:
	tile_buttons.clear()
	_managed_button_count = 0
	for child in tile_grid.get_children():
		tile_grid.remove_child(child)
		child.queue_free()


func _refresh_selected_detail(center: Vector2i) -> void:
	var tile_record := _selected_tile_record()
	if tile_record.is_empty():
		detail_label.text = "[color=#7d898c]현재 도시가 관리하지 않는 타일입니다.[/color]"
		household_button.disabled = true
		queue_button.disabled = true
		return
	var yield_detail: Dictionary = manager.tile_yield(world_map, selected_tile)
	var facilities: Dictionary = tile_record.get("facility_levels", {})
	var facility_lines: Array[String] = []
	for facility_id_value in facilities.keys():
		var facility_id := String(facility_id_value)
		facility_lines.append(
			"%s Lv.%d" % [_facility_name(facility_id), int(facilities[facility_id_value])]
		)
	facility_lines.sort()
	var assigned_id := String(tile_record.get("assigned_household_id", ""))
	var work_text := "도시 중심 자동 작업" if selected_tile == center else (
		"가구 배치됨" if not assigned_id.is_empty() else "유휴 타일"
	)
	detail_label.text = (
		"[color=#dec783][font_size=15](%d, %d) · %s[/font_size][/color]\n"
		+ "[color=#9eaaad]%s[/color]\n\n"
		+ "잠재 생산  %s\n"
		+ "현재 생산  %s\n\n"
		+ "시설  %s"
	) % [
		selected_tile.x,
		selected_tile.y,
		world_map.terrain_name(int(tile_record.get("terrain_id", 0))),
		work_text,
		_yield_text(yield_detail.get("potential_yields", {})),
		_yield_text(yield_detail.get("active_yields", {})),
		", ".join(facility_lines) if not facility_lines.is_empty() else "없음",
	]
	household_button.disabled = selected_tile == center or (
		assigned_id.is_empty() and _first_idle_household().is_empty()
	)
	household_button.text = "배치 가구 회수" if not assigned_id.is_empty() else "유휴 가구 배치"
	queue_button.disabled = false
	_refresh_upgrade_quote()


func _refresh_upgrade_quote() -> void:
	if facility_picker.item_count <= 0 or _selected_tile_record().is_empty():
		queue_button.disabled = true
		queue_button.text = "시설 업그레이드 예약"
		return
	var facility_id := String(
		facility_picker.get_item_metadata(facility_picker.selected)
	)
	var quote: Dictionary = manager.tile_facility_upgrade_quote(
		world_map,
		settlement_id,
		selected_tile,
		facility_id
	)
	if not bool(quote.get("ok", false)):
		queue_button.disabled = true
		queue_button.text = String(quote.get("reason", "건설 불가"))
		return
	var costs: Dictionary = quote.get("costs", {})
	queue_button.text = "%s Lv.%d 예약 · 건설 %d / 목재 %d / 석재 %d" % [
		_facility_name(facility_id),
		int(quote.get("target_level", 1)),
		int(costs.get("construction", 0)),
		int(costs.get("wood", 0)),
		int(costs.get("stone", 0)),
	]


func _selected_tile_record() -> Dictionary:
	if manager == null or world_map == null:
		return {}
	var tile_record: Dictionary = manager.tile_state(world_map, selected_tile)
	if String(tile_record.get("managing_settlement_id", "")) != settlement_id:
		return {}
	return tile_record


func _first_idle_household() -> Dictionary:
	if manager == null:
		return {}
	for household in manager.households(settlement_id):
		if String(household.get("assigned_tile_key", "")).is_empty():
			return household
	return {}


func _city() -> Dictionary:
	if manager == null or settlement_id.is_empty():
		return {}
	return manager.settlement(settlement_id)


func _tile_tooltip(tile: Vector2i, tile_record: Dictionary) -> String:
	var facilities: Dictionary = tile_record.get("facility_levels", {})
	var facility_names: Array[String] = []
	for facility_id_value in facilities.keys():
		facility_names.append(
			"%s Lv.%d" % [
				_facility_name(String(facility_id_value)),
				int(facilities[facility_id_value]),
			]
		)
	return "(%d, %d) %s\n%s\n시설: %s" % [
		tile.x,
		tile.y,
		world_map.terrain_name(int(tile_record.get("terrain_id", 0))),
		"작업 중" if bool(tile_record.get("worked", false)) else "유휴",
		", ".join(facility_names) if not facility_names.is_empty() else "없음",
	]


func _yield_text(yields: Dictionary) -> String:
	var parts: Array[String] = []
	for yield_id in ["food", "production", "commerce", "security"]:
		var amount := float(yields.get(yield_id, 0.0))
		if amount > 0.001:
			parts.append("%s %.1f" % [String(YIELD_LABELS[yield_id]), amount])
	return " · ".join(parts) if not parts.is_empty() else "없음"


func _facility_name(facility_id: String) -> String:
	for facility in FACILITIES:
		if String(facility.id) == facility_id:
			return String(facility.name)
	return facility_id


func _button_key(tile: Vector2i) -> String:
	return "%d:%d" % [tile.x, tile.y]


func _style_tile_button(
	button: Button,
	managed: bool,
	selected: bool,
	center: bool
) -> void:
	var fill := Color("#192428")
	var border := Color("#344347")
	var border_width := 1
	if managed:
		fill = Color("#344238") if center else Color("#263833")
		border = Color("#a98e51") if center else Color("#65745c")
	if selected:
		fill = Color("#48513c")
		border = Color("#e1c36f")
		border_width = 2
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(fill, border, border_width)
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(fill.lightened(0.08), Color("#d0b66b"), 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(fill.darkened(0.08), Color("#ead58e"), 2)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_panel_style(Color("#101719"), Color("#273134"), 1)
	)
	button.add_theme_color_override(
		"font_color",
		Color("#ece2c6") if managed else Color("#667275")
	)
	button.add_theme_color_override("font_disabled_color", Color("#4e5a5d"))
	button.add_theme_font_size_override("font_size", 11)


func _panel_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _show_action(message: String, success: bool) -> void:
	action_message.text = message
	action_message.add_theme_color_override(
		"font_color",
		Color("#7ec59f") if success else Color("#d98a72")
	)


func _on_facility_selected(_index: int) -> void:
	_refresh_upgrade_quote()
