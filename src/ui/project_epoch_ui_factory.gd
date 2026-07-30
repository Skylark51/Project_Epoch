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
    node.custom_minimum_size.y = minimum_height
    node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    node.pressed.connect(action)

    match variant:
        "primary":
            node.add_theme_stylebox_override(
                "normal",
                style("#7a6139", "#d0b06a", 1, 6)
            )
        "danger":
            node.add_theme_stylebox_override(
                "normal",
                style("#593337", "#b96864", 1, 6)
            )
        "list":
            node.alignment = HORIZONTAL_ALIGNMENT_LEFT

    return node


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
    box.set_corner_radius_all(corner_radius)
    box.content_margin_left = 12
    box.content_margin_right = 12
    box.content_margin_top = 10
    box.content_margin_bottom = 10
    return box
