class_name ProjectEpochUiFactory
extends RefCounted


## Creates the small, repeated UI building blocks used by Project Epoch.
##
## Screen scripts should describe information hierarchy and user flow. They
## should not repeatedly explain how margins, labels, buttons, and panels are
## manufactured. Keeping these primitives here makes the screen code read like
## a layout document rather than a sequence of low-level node mutations.


static func margin_container(amount: int) -> MarginContainer:
    var container := MarginContainer.new()
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.add_theme_constant_override("margin_left", amount)
    container.add_theme_constant_override("margin_right", amount)
    container.add_theme_constant_override("margin_top", amount)
    container.add_theme_constant_override("margin_bottom", amount)
    return container


static func header(
    title: String,
    subtitle: String,
    back_action: Callable
) -> Control:
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 62

    row.add_child(button("← 이전", back_action))

    var text_box := VBoxContainer.new()
    text_box.add_child(label(title, 25, Color("#ddc47e")))
    text_box.add_child(label(subtitle, 12, Color("#8f9ca2")))
    row.add_child(text_box)

    row.add_spacer(true)
    row.add_child(label("PROJECT EPOCH", 16, Color("#72664c")))
    return row


static func section(title: String, minimum_width: int = 0) -> VBoxContainer:
    var container := VBoxContainer.new()
    container.custom_minimum_size.x = minimum_width
    container.add_theme_constant_override("separation", 10)
    container.mouse_filter = Control.MOUSE_FILTER_STOP
    container.add_child(label(title, 17, Color("#d8bf7c")))
    return container


static func window_box(window: Window) -> VBoxContainer:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
    window.add_child(margin)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    margin.add_child(box)
    return box


static func label(
    text: String,
    font_size: int = 14,
    color: Color = Color.WHITE,
    alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
    var node := Label.new()
    node.text = text
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", color)
    node.horizontal_alignment = alignment
    return node


static func button(
    text: String,
    action: Callable,
    variant: String = "default",
    minimum_height: int = 40
) -> Button:
    var node := Button.new()
    node.text = text
    node.tooltip_text = text
    node.custom_minimum_size.y = minimum_height
    node.focus_mode = Control.FOCUS_ALL
    node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    node.add_theme_constant_override("outline_size", 1)
    if action.is_valid():
        node.pressed.connect(action)

    if variant == "list":
        node.alignment = HORIZONTAL_ALIGNMENT_LEFT
    if variant == "disabled":
        node.disabled = true
    _apply_button_variant(node, variant)

    return node
static func _apply_button_variant(node: Button, variant: String) -> void:
    var palette: Dictionary = _button_palette(variant)
    node.add_theme_stylebox_override("normal", _button_box(String(palette["normal"]), String(palette["border"])))
    node.add_theme_stylebox_override("hover", _button_box(String(palette["hover"]), String(palette["accent"])))
    node.add_theme_stylebox_override("pressed", _button_box(String(palette["pressed"]), String(palette["accent"])))
    node.add_theme_stylebox_override("disabled", _button_box("#182126", "#354148"))
    node.add_theme_stylebox_override("focus", _button_box(String(palette["normal"]), String(palette["accent"]), 2))
    node.add_theme_color_override("font_color", Color("#d8d8ce"))
    node.add_theme_color_override("font_hover_color", Color("#f0e3bd"))
    node.add_theme_color_override("font_disabled_color", Color("#738087"))
static func _button_palette(variant: String) -> Dictionary:
    var palettes: Dictionary = {
        "default": {"normal": "#162229", "hover": "#20333b", "pressed": "#10191e", "border": "#40515a", "accent": "#7a8e94"},
        "primary": {"normal": "#594a2c", "hover": "#6b5934", "pressed": "#44391f", "border": "#a88b52", "accent": "#d2b66f"},
        "warning": {"normal": "#57462d", "hover": "#6a5635", "pressed": "#41351f", "border": "#a98045", "accent": "#d1a65a"},
        "danger": {"normal": "#4b2d31", "hover": "#633a3c", "pressed": "#351f23", "border": "#94565a", "accent": "#ca7772"},
        "positive": {"normal": "#253f36", "hover": "#315348", "pressed": "#1b3029", "border": "#538775", "accent": "#82be9b"},
        "selected": {"normal": "#28424a", "hover": "#34545d", "pressed": "#1b3339", "border": "#779ea3", "accent": "#c3b06f"},
        "quiet": {"normal": "#10181d", "hover": "#1b2a30", "pressed": "#0b1216", "border": "#2f3d43", "accent": "#647b82"},
    }
    return Dictionary(palettes.get(variant, palettes["default"])).duplicate(true)
static func _button_box(background: String, border: String, border_width: int = 1) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(background)
    box.border_color = Color(border)
    box.set_border_width_all(border_width)
    box.set_corner_radius_all(2)
    box.content_margin_left = 10
    box.content_margin_right = 10
    box.content_margin_top = 6
    box.content_margin_bottom = 6
    return box
static func panel_style(role: String = "default") -> StyleBoxFlat:
    var palettes: Dictionary = {"default": ["#111a20", "#35434a"], "inset": ["#0b1216", "#2d3940"], "emphasis": ["#18242b", "#7b6841"]}
    var selected: Array = palettes.get(role, palettes["default"])
    return style(String(selected[0]), String(selected[1]), 1, 2)


static func stat(caption: String, value: String) -> Label:
    var box := VBoxContainer.new()
    box.custom_minimum_size.x = 74
    box.add_child(
        label(
            caption,
            10,
            Color("#87959b"),
            HORIZONTAL_ALIGNMENT_CENTER
        )
    )

    var result := label(
        value,
        14,
        Color("#e2dcc9"),
        HORIZONTAL_ALIGNMENT_CENTER
    )
    box.add_child(result)
    return result


static func style(
    background: String,
    border: String,
    border_width: int,
    corner_radius: int
) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(background)
    box.border_color = Color(border)
    box.set_border_width_all(border_width)
    box.set_corner_radius_all(mini(corner_radius, 3))
    box.content_margin_left = 12
    box.content_margin_right = 12
    box.content_margin_top = 10
    box.content_margin_bottom = 10
    return box
