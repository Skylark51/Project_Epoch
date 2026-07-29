class_name TurnEndDialog
extends Window

signal continue_requested
signal navigate_requested(target: Dictionary)

var guard: TurnEndGuard
var list_box: VBoxContainer
var continue_button: Button
var summary_label: Label


func _ready() -> void:
    title = "턴 종료 검증"
    size = Vector2i(680, 600)
    visible = false
    exclusive = true
    close_requested.connect(hide)
    _build()


func bind(turn_guard: TurnEndGuard) -> void:
    guard = turn_guard
    if not guard.validation_changed.is_connected(_on_validation_changed):
        guard.validation_changed.connect(_on_validation_changed)


func present() -> Dictionary:
    var report := guard.validate()
    _render(report)
    if bool(report.can_end_turn) and int(report.warning_count) == 0:
        continue_requested.emit()
    else:
        popup_centered()
    return report


func _build() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
    add_child(margin)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 10)
    margin.add_child(outer)
    summary_label = Label.new()
    summary_label.add_theme_font_size_override("font_size", 18)
    summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    outer.add_child(summary_label)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    outer.add_child(scroll)
    list_box = VBoxContainer.new()
    list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list_box)
    var footer := HBoxContainer.new()
    outer.add_child(footer)
    var ignore_all := Button.new()
    ignore_all.text = "경고 모두 이번 턴만 무시"
    ignore_all.pressed.connect(_ignore_all_warnings)
    footer.add_child(ignore_all)
    footer.add_spacer(true)
    var cancel := Button.new()
    cancel.text = "돌아가기"
    cancel.pressed.connect(hide)
    footer.add_child(cancel)
    continue_button = Button.new()
    continue_button.text = "그대로 턴 종료"
    continue_button.pressed.connect(_continue)
    footer.add_child(continue_button)


func _render(report: Dictionary) -> void:
    for child in list_box.get_children():
        child.queue_free()
    summary_label.text = "종료 차단 %d건 · 확인 경고 %d건" % [int(report.blocker_count), int(report.warning_count)]
    summary_label.add_theme_color_override("font_color", Color("#ef8b70") if int(report.blocker_count) > 0 else Color("#e5ca86"))
    _render_group("종료 차단", report.blockers, true)
    _render_group("경고 후 종료 가능", report.warnings, false)
    continue_button.disabled = not bool(report.can_end_turn)
    continue_button.tooltip_text = "차단 항목을 해결해야 합니다." if continue_button.disabled else "경고를 확인하고 턴을 종료합니다."


func _render_group(title_text: String, groups: Array, blocking: bool) -> void:
    if groups.is_empty():
        return
    var title_label := Label.new()
    title_label.text = title_text
    title_label.add_theme_font_size_override("font_size", 16)
    title_label.add_theme_color_override("font_color", Color("#ef8b70") if blocking else Color("#e5ca86"))
    list_box.add_child(title_label)
    for item in groups:
        var panel := PanelContainer.new()
        list_box.add_child(panel)
        var row := HBoxContainer.new()
        panel.add_child(row)
        var label := Label.new()
        label.text = "%s%s\n%s" % [String(item.title), " ×%d" % int(item.count) if int(item.count) > 1 else "", String(item.message)]
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        if not item.get("target", {}).is_empty():
            var go := Button.new()
            go.text = "위치로 이동"
            go.pressed.connect(func(target = item.target): navigate_requested.emit(target); hide())
            row.add_child(go)
        if not blocking:
            var ignore := Button.new()
            ignore.text = "이번 턴만 무시"
            ignore.pressed.connect(func(ids = item.ids): _ignore_ids(ids))
            row.add_child(ignore)


func _ignore_ids(ids: Array) -> void:
    for id in ids:
        guard.ignore_for_turn(String(id))
    _render(guard.validate())


func _ignore_all_warnings() -> void:
    var report := guard.validate()
    for item in report.warnings:
        _ignore_ids(item.ids)
    _render(guard.validate())


func _continue() -> void:
    if guard.has_blockers():
        _render(guard.validate())
        return
    hide()
    continue_requested.emit()


func _on_validation_changed(report: Dictionary) -> void:
    if visible:
        _render(report)
