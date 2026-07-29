class_name NotificationPresenter
extends Control

signal notification_clicked(target: Dictionary)

var center: NotificationCenter
var list_panel: PanelContainer
var list_box: VBoxContainer
var banner: PanelContainer
var banner_label: Label
var banner_timer: Timer
var active_modals: Dictionary = {}


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    process_mode = Node.PROCESS_MODE_ALWAYS
    _build()


func bind(notification_center: NotificationCenter) -> void:
    center = notification_center
    if not center.notification_added.is_connected(_on_added):
        center.notification_added.connect(_on_added)
    if not center.notification_updated.is_connected(_on_updated):
        center.notification_updated.connect(_on_updated)
    if not center.navigation_requested.is_connected(_on_navigation):
        center.navigation_requested.connect(_on_navigation)
    _refresh_list()


func toggle_list() -> void:
    list_panel.visible = not list_panel.visible
    if list_panel.visible:
        _refresh_list()


func _build() -> void:
    list_panel = PanelContainer.new()
    list_panel.name = "NotificationList"
    list_panel.visible = false
    list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    list_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    list_panel.position = Vector2(-390, 66)
    list_panel.size = Vector2(380, 540)
    list_panel.add_theme_stylebox_override("panel", _style("#142029ee", "#8e7750"))
    add_child(list_panel)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 8)
    list_panel.add_child(outer)
    var header := HBoxContainer.new()
    outer.add_child(header)
    var title := Label.new()
    title.text = "알림"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    header.add_child(title)
    var mark_all := Button.new()
    mark_all.text = "모두 읽음"
    mark_all.pressed.connect(func(): center.mark_all_read(); _refresh_list())
    header.add_child(mark_all)
    var close := Button.new()
    close.text = "×"
    close.pressed.connect(list_panel.hide)
    header.add_child(close)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    outer.add_child(scroll)
    list_box = VBoxContainer.new()
    list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list_box)

    banner = PanelContainer.new()
    banner.name = "NotificationBanner"
    banner.visible = false
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
    banner.position = Vector2(-280, 70)
    banner.size = Vector2(560, 62)
    banner.add_theme_stylebox_override("panel", _style("#38251eee", "#e19a68"))
    add_child(banner)
    banner_label = Label.new()
    banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    banner.add_child(banner_label)
    banner_timer = Timer.new()
    banner_timer.one_shot = true
    banner_timer.timeout.connect(banner.hide)
    add_child(banner_timer)


func _on_added(item: Dictionary, channels: Dictionary) -> void:
    if bool(channels.get("list", false)):
        _refresh_list()
    if bool(channels.get("banner", false)):
        banner_label.text = "%s · %s" % [String(item.title), String(item.message)]
        banner.show()
        banner_timer.start(5.0)
    if bool(channels.get("modal", false)):
        _show_modal(item)


func _on_updated(_item: Dictionary) -> void:
    _refresh_list()


func _refresh_list() -> void:
    if list_box == null:
        return
    for child in list_box.get_children():
        child.queue_free()
    if center == null or center.all_notifications().is_empty():
        var empty := Label.new()
        empty.text = "알림이 없습니다."
        empty.add_theme_color_override("font_color", Color("#8fa0a8"))
        list_box.add_child(empty)
        return
    for item in center.grouped_notifications():
        if bool(item.get("resolved", false)):
            continue
        var button := Button.new()
        var repeat := " ×%d" % int(item.get("repeat_count", 1)) if int(item.get("repeat_count", 1)) > 1 else ""
        button.text = "%s  %s%s\n%s" % [_severity_icon(String(item.severity)), String(item.title), repeat, String(item.message)]
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.tooltip_text = "클릭하면 관련 위치나 화면으로 이동합니다."
        if not bool(item.get("read", false)):
            button.add_theme_color_override("font_color", Color("#f1d08a"))
        button.pressed.connect(func(id = int(item.id)): center.navigate(id))
        list_box.add_child(button)
    for card in center.crisis_cards():
        var crisis := Label.new()
        crisis.text = "도시 위기 · %s · %d건" % [String(card.title), int(card.notifications.size())]
        crisis.add_theme_color_override("font_color", Color("#ef8b70"))
        list_box.add_child(crisis)


func _show_modal(item: Dictionary) -> void:
    var id := int(item.id)
    if active_modals.has(id):
        return
    var dialog := AcceptDialog.new()
    dialog.process_mode = Node.PROCESS_MODE_ALWAYS
    dialog.title = "%s · %s" % [_severity_name(String(item.severity)), String(item.title)]
    dialog.dialog_text = String(item.message)
    dialog.ok_button_text = "확인"
    dialog.confirmed.connect(func(): center.acknowledge(id); active_modals.erase(id); dialog.queue_free())
    dialog.canceled.connect(func(): center.acknowledge(id); active_modals.erase(id); dialog.queue_free())
    active_modals[id] = dialog
    add_child(dialog)
    dialog.popup_centered(Vector2i(620, 300))


func _on_navigation(target: Dictionary) -> void:
    notification_clicked.emit(target)


func _severity_icon(severity: String) -> String:
    return {"info": "ℹ", "caution": "△", "warning": "⚠", "urgent": "‼", "decision_required": "?"}.get(severity, "•")


func _severity_name(severity: String) -> String:
    return {"info": "정보", "caution": "주의", "warning": "경고", "urgent": "긴급", "decision_required": "결정 필요"}.get(severity, severity)


func _style(background: String, border: String) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(background)
    style.border_color = Color(border)
    style.set_border_width_all(1)
    style.set_corner_radius_all(8)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 10
    style.content_margin_bottom = 10
    return style
