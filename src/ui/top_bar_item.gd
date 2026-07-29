class_name TopBarItem
extends VBoxContainer

signal item_dropped(source_id: String, target_id: String)

var item_id := ""
var caption := ""
var icon := ""
var value := "—"
var compact := false
var risk := false
var caption_label: Label
var value_label: Label


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    add_theme_constant_override("separation", 0)
    caption_label = Label.new()
    caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption_label.add_theme_font_size_override("font_size", 10)
    caption_label.add_theme_color_override("font_color", Color("#8fa0a8"))
    add_child(caption_label)
    value_label = Label.new()
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value_label.add_theme_font_size_override("font_size", 14)
    add_child(value_label)
    _refresh()


func configure(data: Dictionary, compact_mode: bool) -> void:
    item_id = String(data.get("id", ""))
    caption = String(data.get("label", item_id))
    icon = String(data.get("icon", "•"))
    value = String(data.get("value", "—"))
    risk = bool(data.get("risk", false))
    compact = compact_mode
    if is_node_ready():
        _refresh()


func _refresh() -> void:
    if caption_label == null:
        return
    caption_label.visible = not compact
    caption_label.text = caption
    value_label.text = "%s %s" % [icon, value]
    value_label.add_theme_color_override("font_color", Color("#ef8b70") if risk else Color("#e6dcc0"))
    custom_minimum_size.x = 56.0 if compact else 92.0
    tooltip_text = "%s: %s\n드래그해 순서를 변경합니다." % [caption, value]


func _get_drag_data(_position: Vector2):
    var preview := Label.new()
    preview.text = "%s %s" % [icon, caption]
    preview.add_theme_color_override("font_color", Color("#e6c77f"))
    set_drag_preview(preview)
    return {"top_bar_item": item_id}


func _can_drop_data(_position: Vector2, drag_data) -> bool:
    return drag_data is Dictionary and drag_data.has("top_bar_item") and String(drag_data.top_bar_item) != item_id


func _drop_data(_position: Vector2, drag_data) -> void:
    item_dropped.emit(String(drag_data.top_bar_item), item_id)
