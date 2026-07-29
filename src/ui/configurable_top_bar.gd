class_name ConfigurableTopBar
extends PanelContainer

signal turn_end_requested
signal main_menu_requested
signal notifications_requested
signal edge_pan_changed(enabled: bool)
signal notification_rules_changed(rules: Dictionary)

const PreferencesScript = preload("res://src/ui/ui_shell_preferences.gd")
const AdapterScript = preload("res://src/ui/top_bar_data_adapter.gd")
const ItemScript = preload("res://src/ui/top_bar_item.gd")

var preferences: UIShellPreferences
var adapter := TopBarDataAdapter.new()
var item_row: HBoxContainer
var urgent_button: Button
var turn_button: Button
var overflow_label: Label
var settings_dialog: Window
var settings_list: VBoxContainer
var mode_option: OptionButton
var edge_pan_check: CheckBox
var current_values: Dictionary = {}
var current_snapshot: Dictionary = {}
var current_country_id := ""
var current_urgent_count := 0
var forced_compact := false


func _ready() -> void:
    custom_minimum_size.y = 58
    add_theme_stylebox_override("panel", _style("#18232c", "#8d764b"))
    if preferences == null:
        preferences = PreferencesScript.new()
        preferences.load_preferences()
    _build()
    resized.connect(_refresh_layout)
    _refresh_layout()


func set_preferences(store: UIShellPreferences) -> void:
    preferences = store
    if is_node_ready():
        _refresh_items()


func set_snapshot(snapshot: Dictionary, country_id: String, urgent_count := 0) -> void:
    current_snapshot = snapshot.duplicate(true)
    current_country_id = country_id
    current_urgent_count = urgent_count
    current_values = adapter.build(snapshot, country_id, urgent_count)
    if is_node_ready():
        _refresh_items()


func set_urgent_count(count: int) -> void:
    current_urgent_count = max(0, count)
    if urgent_button != null:
        urgent_button.text = "긴급 %d" % current_urgent_count
        urgent_button.add_theme_color_override("font_color", Color("#ff9a7a") if current_urgent_count > 0 else Color("#c5ced0"))


func set_turn_blocked(blocked: bool, reason := "") -> void:
    if turn_button == null:
        return
    turn_button.disabled = blocked
    turn_button.tooltip_text = reason if blocked else "턴 종료 검증 후 다음 턴을 실행합니다."


func visible_item_ids() -> Array:
    return preferences.top_bar().get("visible", []).duplicate()


func item_order() -> Array:
    return preferences.top_bar().get("order", []).duplicate()


func display_mode() -> String:
    return String(preferences.top_bar().get("display_mode", "detail"))


func set_item_visible(item_id: String, visible: bool) -> void:
    if item_id not in PreferencesScript.ITEM_IDS:
        return
    var config := preferences.top_bar()
    var ids: Array = config.visible.duplicate()
    if visible and item_id not in ids:
        ids.append(item_id)
    elif not visible and item_id not in PreferencesScript.REQUIRED_IDS:
        ids.erase(item_id)
    preferences.set_top_bar(config.order, ids, String(config.display_mode))
    _refresh_items()


func set_display_mode(mode: String) -> void:
    var config := preferences.top_bar()
    preferences.set_top_bar(config.order, config.visible, mode)
    _refresh_items()


func reorder_item(source_id: String, target_id: String) -> void:
    var config := preferences.top_bar()
    var order: Array = config.order.duplicate()
    var source_index := order.find(source_id)
    var target_index := order.find(target_id)
    if source_index < 0 or target_index < 0 or source_index == target_index:
        return
    order.remove_at(source_index)
    target_index = order.find(target_id)
    order.insert(target_index, source_id)
    preferences.set_top_bar(order, config.visible, String(config.display_mode))
    _refresh_items()


func _build() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    add_child(row)
    var menu := Button.new()
    menu.text = "☰"
    menu.tooltip_text = "메인 메뉴"
    menu.pressed.connect(func(): main_menu_requested.emit())
    row.add_child(menu)
    var settings_button := Button.new()
    settings_button.text = "⚙"
    settings_button.tooltip_text = "상단 정보 바·입력·알림 설정"
    settings_button.pressed.connect(_open_settings)
    row.add_child(settings_button)
    var title := Label.new()
    title.text = "PROJECT EPOCH"
    title.custom_minimum_size.x = 132
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 16)
    title.add_theme_color_override("font_color", Color("#d8bd7a"))
    row.add_child(title)
    item_row = HBoxContainer.new()
    item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    item_row.add_theme_constant_override("separation", 3)
    row.add_child(item_row)
    overflow_label = Label.new()
    overflow_label.visible = false
    overflow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    overflow_label.add_theme_color_override("font_color", Color("#a9b6ba"))
    row.add_child(overflow_label)
    urgent_button = Button.new()
    urgent_button.text = "긴급 0"
    urgent_button.pressed.connect(func(): notifications_requested.emit())
    row.add_child(urgent_button)
    turn_button = Button.new()
    turn_button.text = "턴 종료  Space"
    turn_button.custom_minimum_size.x = 136
    turn_button.pressed.connect(func(): turn_end_requested.emit())
    row.add_child(turn_button)
    _build_settings_dialog()
    _refresh_items()


func _refresh_items() -> void:
    if item_row == null:
        return
    for child in item_row.get_children():
        item_row.remove_child(child)
        child.free()
    var config := preferences.top_bar()
    var compact := String(config.display_mode) == "compact" or forced_compact
    var visible: Array = config.visible
    var order: Array = config.order
    var hidden_risks: Array[String] = []
    for id_value in order:
        var id := String(id_value)
        var value: Dictionary = current_values.get(id, adapter._unavailable(id))
        if id not in visible:
            if bool(value.get("risk", false)):
                hidden_risks.append(String(value.get("label", id)))
            continue
        var item = ItemScript.new()
        item.configure(value, compact)
        item.item_dropped.connect(reorder_item)
        item_row.add_child(item)
    if not hidden_risks.is_empty():
        var warning := Label.new()
        warning.text = "⚠ %s" % ", ".join(hidden_risks)
        warning.tooltip_text = "숨긴 항목에서 위험 상태가 감지되었습니다."
        warning.add_theme_color_override("font_color", Color("#ef8b70"))
        warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        item_row.add_child(warning)
    set_urgent_count(current_urgent_count)
    call_deferred("_refresh_layout")


func _refresh_layout() -> void:
    if item_row == null or size.x <= 1:
        return
    var config := preferences.top_bar()
    var visible_count := int(config.visible.size())
    var reserved := 132.0 + 84.0 + 104.0 + 136.0 + 42.0
    var detailed_required := reserved + visible_count * 95.0
    var should_force := size.x < detailed_required
    if forced_compact != should_force:
        forced_compact = should_force
        _refresh_items()
        return
    var per_item := 59.0 if forced_compact or String(config.display_mode) == "compact" else 95.0
    var capacity := maxi(4, floori((size.x - reserved) / per_item))
    var shown := 0
    for child in item_row.get_children():
        if child is TopBarItem:
            child.visible = shown < capacity
            shown += 1
    var overflow := maxi(0, shown - capacity)
    overflow_label.visible = overflow > 0
    overflow_label.text = "+%d" % overflow
    overflow_label.tooltip_text = "폭이 부족해 자동 축약된 항목입니다."


func _build_settings_dialog() -> void:
    settings_dialog = Window.new()
    settings_dialog.title = "상단 정보 바 · 입력 설정"
    settings_dialog.size = Vector2i(520, 650)
    settings_dialog.visible = false
    settings_dialog.close_requested.connect(settings_dialog.hide)
    add_child(settings_dialog)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
    settings_dialog.add_child(margin)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 10)
    margin.add_child(outer)
    var guide := Label.new()
    guide.text = "표시 항목을 고르고, 상단 바의 항목을 직접 드래그해 순서를 바꿉니다."
    guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    outer.add_child(guide)
    var mode_row := HBoxContainer.new()
    outer.add_child(mode_row)
    var mode_label := Label.new()
    mode_label.text = "표시 방식"
    mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mode_row.add_child(mode_label)
    mode_option = OptionButton.new()
    mode_option.add_item("아이콘 + 숫자 상세", 0)
    mode_option.add_item("간략 아이콘형", 1)
    mode_option.item_selected.connect(func(index): set_display_mode("detail" if index == 0 else "compact"))
    mode_row.add_child(mode_option)
    edge_pan_check = CheckBox.new()
    edge_pan_check.text = "화면 가장자리 이동 사용"
    edge_pan_check.toggled.connect(_set_edge_pan)
    outer.add_child(edge_pan_check)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    outer.add_child(scroll)
    settings_list = VBoxContainer.new()
    settings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(settings_list)
    var close := Button.new()
    close.text = "닫기"
    close.pressed.connect(settings_dialog.hide)
    outer.add_child(close)


func _open_settings() -> void:
    for child in settings_list.get_children():
        child.queue_free()
    var config := preferences.top_bar()
    mode_option.select(0 if String(config.display_mode) == "detail" else 1)
    edge_pan_check.set_pressed_no_signal(bool(preferences.input_settings().edge_pan_enabled))
    for id_value in config.order:
        var id := String(id_value)
        var check := CheckBox.new()
        check.text = String(AdapterScript.CATALOG[id].label)
        check.button_pressed = id in config.visible
        check.disabled = id in PreferencesScript.REQUIRED_IDS
        check.toggled.connect(func(enabled, item_id = id): set_item_visible(item_id, enabled))
        settings_list.add_child(check)
    var separator := HSeparator.new()
    settings_list.add_child(separator)
    var heading := Label.new()
    heading.text = "알림 중요도별 표시 방식"
    heading.add_theme_font_size_override("font_size", 16)
    settings_list.add_child(heading)
    var hint := Label.new()
    hint.text = "긴급·결정 필요 알림은 목록 표시를 끌 수 없습니다."
    hint.add_theme_color_override("font_color", Color("#d7aa72"))
    settings_list.add_child(hint)
    var channel_names := {
        "list": "목록", "banner": "배너", "map_icon": "지도 아이콘",
        "sound": "소리", "auto_pause": "자동 일시정지", "modal": "중앙 확인창"
    }
    var severity_names := {
        "info": "정보", "caution": "주의", "warning": "경고",
        "urgent": "긴급", "decision_required": "결정 필요"
    }
    var rules := preferences.notification_rules()
    for severity in PreferencesScript.SEVERITIES:
        var severity_label := Label.new()
        severity_label.text = String(severity_names[severity])
        severity_label.add_theme_color_override("font_color", Color("#e3c987"))
        settings_list.add_child(severity_label)
        var channel_row := HFlowContainer.new()
        settings_list.add_child(channel_row)
        var rule: Dictionary = rules.get(severity, {})
        for channel in PreferencesScript.CHANNELS:
            var channel_check := CheckBox.new()
            channel_check.text = String(channel_names[channel])
            channel_check.button_pressed = bool(rule.get(channel, false))
            if severity in ["urgent", "decision_required"] and channel == "list":
                channel_check.button_pressed = true
                channel_check.disabled = true
            channel_check.toggled.connect(_on_notification_channel_toggled.bind(severity, channel))
            channel_row.add_child(channel_check)
    var kind_separator := HSeparator.new()
    settings_list.add_child(kind_separator)
    var kind_heading := Label.new()
    kind_heading.text = "사건 종류별 재정의"
    kind_heading.add_theme_font_size_override("font_size", 16)
    settings_list.add_child(kind_heading)
    for kind in PreferencesScript.EVENT_KINDS:
        var meta: Dictionary = PreferencesScript.EVENT_KINDS[kind]
        var kind_severity := String(meta.severity)
        var kind_label := Label.new()
        kind_label.text = String(meta.label)
        kind_label.add_theme_color_override("font_color", Color("#b9c8ca"))
        settings_list.add_child(kind_label)
        var kind_channel_row := HFlowContainer.new()
        settings_list.add_child(kind_channel_row)
        var kind_rule: Dictionary = rules.get(kind, rules.get(kind_severity, {}))
        for channel in PreferencesScript.CHANNELS:
            var kind_check := CheckBox.new()
            kind_check.text = String(channel_names[channel])
            kind_check.button_pressed = bool(kind_rule.get(channel, false))
            if kind_severity in ["urgent", "decision_required"] and channel == "list":
                kind_check.button_pressed = true
                kind_check.disabled = true
            kind_check.toggled.connect(_on_notification_channel_toggled.bind(kind, channel))
            kind_channel_row.add_child(kind_check)
    settings_dialog.popup_centered()


func _set_edge_pan(enabled: bool) -> void:
    preferences.set_edge_pan_enabled(enabled)
    edge_pan_changed.emit(enabled)


func _on_notification_channel_toggled(enabled: bool, severity: String, channel: String) -> void:
    var rule: Dictionary = preferences.notification_rules().get(severity, {}).duplicate(true)
    if enabled:
        rule[channel] = true
    else:
        rule.erase(channel)
    preferences.set_notification_rule(severity, rule)
    notification_rules_changed.emit(preferences.notification_rules())


func _style(background: String, border: String) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(background)
    style.border_color = Color(border)
    style.set_border_width_all(1)
    style.set_corner_radius_all(8)
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 5
    style.content_margin_bottom = 5
    return style
