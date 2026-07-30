extends Control

const GAME_SCREEN_STATE := 3
const CATALOG_PATH := "res://data/dialogue/rulers.json"
const IDLE_FRAME_START := 0
const IDLE_FRAME_COUNT := 8
const BLINK_FRAME_START := 8
const BLINK_FRAME_COUNT := 4
const SPEECH_FRAME_START := 12
const SPEECH_FRAME_COUNT := 12
const SETTLE_FRAME_START := 24
const SETTLE_FRAME_COUNT := 6
const TYPEWRITER_CHARACTERS_PER_SECOND := 34.0

var base_ui: Control
var ruler_catalog: Dictionary = {}
var current_ruler: Dictionary = {}
var dialogue_lines: Array[String] = []
var dialogue_index := 0
var current_frame := -1
var typing := false
var typed_character_progress := 0.0
var animation_elapsed := 0.0

var launcher: Button
var shade: ColorRect
var dialogue_panel: PanelContainer
var portrait: TextureRect
var portrait_atlas: AtlasTexture
var ruler_name: Label
var ruler_title: Label
var dialogue_text: RichTextLabel
var progress_label: Label
var next_button: Button


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 300
    base_ui = get_parent() as Control
    _load_catalog()
    _build_overlay()
    set_process(true)


func _process(delta: float) -> void:
    if base_ui == null:
        return

    var country_id := _current_country_id()
    var in_game := int(base_ui.get("state")) == GAME_SCREEN_STATE
    launcher.visible = in_game and ruler_catalog.has(country_id)

    if not shade.visible:
        return

    _update_typewriter(delta)
    _update_portrait_animation(delta)


func _input(event: InputEvent) -> void:
    if not shade.visible:
        return
    if event is not InputEventKey or not event.pressed or event.echo:
        return

    if event.keycode == KEY_ESCAPE:
        close_dialogue()
        get_viewport().set_input_as_handled()
    elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
        _advance_dialogue()
        get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
    if event is not InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode != KEY_D:
        return
    if base_ui == null or int(base_ui.get("state")) != GAME_SCREEN_STATE:
        return

    open_current_ruler_dialogue()
    get_viewport().set_input_as_handled()


func open_current_ruler_dialogue() -> bool:
    return open_dialogue(_current_country_id())


func open_dialogue(country_id: String) -> bool:
    if not ruler_catalog.has(country_id):
        return false

    var definition: Dictionary = ruler_catalog.get(country_id, {})
    var texture := _load_portrait_texture(definition)
    if texture == null:
        return false

    current_ruler = definition.duplicate(true)
    dialogue_lines.clear()
    for value in definition.get("dialogue", []):
        dialogue_lines.append(String(value))
    if dialogue_lines.is_empty():
        dialogue_lines.append("국정에 관해 보고할 일이 있는가.")

    portrait_atlas.atlas = texture
    ruler_name.text = String(definition.get("name", "군주"))
    ruler_title.text = String(definition.get("title", ""))
    dialogue_index = 0
    animation_elapsed = 0.0
    shade.show()
    _start_dialogue_line()
    _set_frame(IDLE_FRAME_START)
    return true


func close_dialogue() -> void:
    shade.hide()
    current_ruler.clear()
    dialogue_lines.clear()
    dialogue_index = 0
    typing = false
    current_frame = -1


func is_dialogue_open() -> bool:
    return shade.visible


func _load_catalog() -> void:
    var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
    if file == null:
        push_error("RulerDialogueOverlay: 군주 대화 목록을 열 수 없습니다.")
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        ruler_catalog = parsed
    else:
        push_error("RulerDialogueOverlay: 군주 대화 목록 형식이 올바르지 않습니다.")


func _load_portrait_texture(definition: Dictionary) -> Texture2D:
    var direct_path := String(definition.get("portrait", ""))
    if not direct_path.is_empty():
        var direct_texture = load(direct_path)
        if direct_texture is Texture2D:
            return direct_texture

    var encoded_parts := PackedStringArray()
    for part_path_value in definition.get("portrait_parts", []):
        var part_path := String(part_path_value)
        var part_file := FileAccess.open(part_path, FileAccess.READ)
        if part_file == null:
            push_error("RulerDialogueOverlay: 초상 데이터 조각을 열 수 없습니다: %s" % part_path)
            return null
        encoded_parts.append(part_file.get_as_text().strip_edges())

    if encoded_parts.is_empty():
        push_error("RulerDialogueOverlay: 초상 데이터가 정의되지 않았습니다.")
        return null

    var raw_png := Marshalls.base64_to_raw("".join(encoded_parts))
    var image := Image.new()
    var load_error := image.load_png_from_buffer(raw_png)
    if load_error != OK:
        push_error("RulerDialogueOverlay: 초상 PNG 복원에 실패했습니다: %s" % error_string(load_error))
        return null
    return ImageTexture.create_from_image(image)


func _build_overlay() -> void:
    launcher = Button.new()
    launcher.name = "RulerDialogueLauncher"
    launcher.text = "♛ 군주 접견  D"
    launcher.anchor_left = 1.0
    launcher.anchor_right = 1.0
    launcher.offset_left = -575.0
    launcher.offset_right = -430.0
    launcher.offset_top = 10.0
    launcher.offset_bottom = 50.0
    launcher.z_index = 252
    launcher.visible = false
    launcher.pressed.connect(open_current_ruler_dialogue)
    add_child(launcher)

    shade = ColorRect.new()
    shade.name = "RulerDialogueShade"
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.color = Color(0.02, 0.025, 0.03, 0.78)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    shade.z_index = 300
    shade.visible = false
    add_child(shade)

    dialogue_panel = PanelContainer.new()
    dialogue_panel.name = "RulerDialoguePanel"
    dialogue_panel.anchor_left = 0.5
    dialogue_panel.anchor_right = 0.5
    dialogue_panel.anchor_top = 1.0
    dialogue_panel.anchor_bottom = 1.0
    dialogue_panel.offset_left = -510.0
    dialogue_panel.offset_right = 510.0
    dialogue_panel.offset_top = -390.0
    dialogue_panel.offset_bottom = -24.0
    dialogue_panel.add_theme_stylebox_override("panel", _panel_style())
    shade.add_child(dialogue_panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 16)
    dialogue_panel.add_child(margin)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 18)
    margin.add_child(row)

    var portrait_frame := PanelContainer.new()
    portrait_frame.custom_minimum_size = Vector2(320, 320)
    portrait_frame.add_theme_stylebox_override("panel", _portrait_style())
    row.add_child(portrait_frame)

    portrait = TextureRect.new()
    portrait.name = "AnimatedRulerPortrait"
    portrait.custom_minimum_size = Vector2(320, 320)
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    portrait_atlas = AtlasTexture.new()
    portrait.texture = portrait_atlas
    portrait_frame.add_child(portrait)

    var text_column := VBoxContainer.new()
    text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text_column.add_theme_constant_override("separation", 8)
    row.add_child(text_column)

    ruler_name = Label.new()
    ruler_name.name = "RulerName"
    ruler_name.add_theme_font_size_override("font_size", 28)
    ruler_name.add_theme_color_override("font_color", Color("#e2ca82"))
    text_column.add_child(ruler_name)

    ruler_title = Label.new()
    ruler_title.name = "RulerTitle"
    ruler_title.add_theme_font_size_override("font_size", 13)
    ruler_title.add_theme_color_override("font_color", Color("#9da9ad"))
    text_column.add_child(ruler_title)

    text_column.add_child(HSeparator.new())

    dialogue_text = RichTextLabel.new()
    dialogue_text.name = "DialogueText"
    dialogue_text.bbcode_enabled = false
    dialogue_text.fit_content = false
    dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dialogue_text.add_theme_font_size_override("normal_font_size", 18)
    dialogue_text.add_theme_color_override("default_color", Color("#e7e1d2"))
    text_column.add_child(dialogue_text)

    progress_label = Label.new()
    progress_label.name = "DialogueProgress"
    progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    progress_label.add_theme_font_size_override("font_size", 12)
    progress_label.add_theme_color_override("font_color", Color("#849197"))
    text_column.add_child(progress_label)

    var buttons := HBoxContainer.new()
    buttons.add_spacer(true)
    text_column.add_child(buttons)

    var close_button := Button.new()
    close_button.text = "접견 종료"
    close_button.pressed.connect(close_dialogue)
    buttons.add_child(close_button)

    next_button = Button.new()
    next_button.name = "DialogueNextButton"
    next_button.text = "계속  Enter"
    next_button.pressed.connect(_advance_dialogue)
    buttons.add_child(next_button)


func _start_dialogue_line() -> void:
    dialogue_text.text = dialogue_lines[dialogue_index]
    dialogue_text.visible_characters = 0
    typed_character_progress = 0.0
    typing = true
    progress_label.text = "%d / %d" % [dialogue_index + 1, dialogue_lines.size()]
    next_button.text = "문장 표시  Enter"


func _advance_dialogue() -> void:
    if typing:
        dialogue_text.visible_characters = -1
        typing = false
        next_button.text = "계속  Enter"
        return

    dialogue_index += 1
    if dialogue_index >= dialogue_lines.size():
        close_dialogue()
        return
    _start_dialogue_line()


func _update_typewriter(delta: float) -> void:
    if not typing:
        return

    typed_character_progress += TYPEWRITER_CHARACTERS_PER_SECOND * delta
    dialogue_text.visible_characters = int(typed_character_progress)
    if dialogue_text.visible_characters >= dialogue_text.get_total_character_count():
        dialogue_text.visible_characters = -1
        typing = false
        next_button.text = "계속  Enter"


func _update_portrait_animation(delta: float) -> void:
    animation_elapsed += delta
    var fps := float(current_ruler.get("fps", 12.0))
    var next_frame := IDLE_FRAME_START

    if typing:
        next_frame = SPEECH_FRAME_START + int(animation_elapsed * fps) % SPEECH_FRAME_COUNT
    else:
        var idle_cycle := fmod(animation_elapsed, 4.0)
        if idle_cycle < 2.8:
            next_frame = IDLE_FRAME_START + int(idle_cycle * 2.0) % IDLE_FRAME_COUNT
        elif idle_cycle < 3.2:
            next_frame = BLINK_FRAME_START + int((idle_cycle - 2.8) * 10.0) % BLINK_FRAME_COUNT
        else:
            next_frame = SETTLE_FRAME_START + int((idle_cycle - 3.2) * 5.0) % SETTLE_FRAME_COUNT

    _set_frame(next_frame)


func _set_frame(frame_index: int) -> void:
    var frame_count := int(current_ruler.get("frame_count", 30))
    if frame_index < 0 or frame_index >= frame_count:
        return
    if current_frame == frame_index:
        return

    var columns := int(current_ruler.get("columns", 5))
    var frame_width := int(current_ruler.get("frame_width", 64))
    var frame_height := int(current_ruler.get("frame_height", 64))
    var column := frame_index % columns
    var row := int(frame_index / columns)
    portrait_atlas.region = Rect2(
        column * frame_width,
        row * frame_height,
        frame_width,
        frame_height
    )
    current_frame = frame_index


func _current_country_id() -> String:
    if base_ui == null:
        return ""

    var selected_value = base_ui.get("selected_country")
    if selected_value != null and not String(selected_value).is_empty():
        return String(selected_value)

    var gateway = base_ui.get("gateway")
    if gateway != null and gateway.has_method("snapshot"):
        return String(gateway.snapshot().get("player_country_id", ""))
    return ""


func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#111a21")
    style.border_color = Color("#a88b55")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    return style


func _portrait_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#38271f")
    style.border_color = Color("#6f5939")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    return style
