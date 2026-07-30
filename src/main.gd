extends Control

const SettlementPreviewControl = preload("res://src/ui/settlement_preview.gd")


enum ScreenState {
	START,
	SCENARIO,
	COUNTRY,
	GAME
}


const MAP_MODES := [
	["political", "정치"],
	["relations", "외교"],
	["war", "전쟁"],
	["economy", "경제"],
	["supply", "보급"],
	["population", "인구"],
	["development", "개발"],
	["manpower", "인력"],
	["stability", "안정"],
	["revolt", "반란"],
	["terrain", "지형"],
	["fort", "요새"]
]

const LOG_LIMIT := 120
const CAMPAIGN_SAVE_SCHEMA_VERSION := 1
const RULER_PORTRAIT_PATHS := {
	"goguryeo": "res://assets/portraits/ruler_goguryeo.png",
	"baekje": "res://assets/portraits/ruler_baekje.png",
	"silla": "res://assets/portraits/ruler_silla.png",
}
const RULER_PROFILES := {
	"goguryeo": {"name":"해무진", "title":"국내성 왕족 영주", "age":41, "administration":66, "military":78},
	"baekje": {"name":"부여엽진", "title":"한성 왕족 영주", "age":39, "administration":70, "military":64},
	"silla": {"name":"박해림", "title":"금성 왕족 영주", "age":36, "administration":62, "military":59},
}

const DEFAULT_CITY_NAMES := {
	"goguryeo":"졸본", "baekje":"위례", "silla":"서라벌",
	"geumgwan_gaya":"구야", "daegaya":"대가야", "ara_gaya":"안라",
	"liaodong_lordship":"양평", "northern_china_frontier":"임치",
	"yamato":"야마토", "tsukushi_confederacy":"쓰쿠시", "kibi_league":"기비",
}
const FIRST_CONSTRUCTIONS := {
	"well_storage":{"name":"우물과 저장고","summary":"식량과 물자를 오래 보존해 정착 안정성을 높입니다.","effect":"정착 안정 + · 식량 손실 감소","appearance":"well_storage"},
	"farmland":{"name":"농경지 개간","summary":"도시 주변을 논밭과 수로로 바꾸어 성장을 앞당깁니다.","effect":"식량 생산 + · 인구 성장 +","appearance":"farmland"},
	"palisade":{"name":"목책과 감시대","summary":"도시 둘레에 목책과 망루를 세워 개척민을 보호합니다.","effect":"방어 + · 치안 +","appearance":"palisade"},
}
const SETTLER_CHOICES := {
	"accept_all":{"name":"30가구 전원 수용","households":30,"farmers":18,"artisans":7,"guards":5,"food":-20,"reputation":8,"summary":"도시는 빠르게 커지지만 당장의 식량 부담이 큽니다."},
	"selective":{"name":"기술자와 농민 18가구 선별","households":18,"farmers":8,"artisans":7,"guards":3,"food":-10,"reputation":2,"summary":"성장은 느리지만 필요한 기술과 노동력을 확보합니다."},
	"refuse":{"name":"식량 부족을 이유로 거절","households":0,"farmers":0,"artisans":0,"guards":0,"food":0,"reputation":-8,"summary":"비축은 지키지만 인근 사람들의 신뢰를 잃습니다."},
}
const PRIORITY_PROJECTS := {
	"irrigation":{"name":"관개수로와 공동 우물","speaker":"농민 대표","summary":"물길을 안정시켜 다음 수확과 추가 정착에 대비합니다.","food":8,"capacity":20,"production":2,"security":0,"reputation":3},
	"workshop":{"name":"공동 작업장","speaker":"장인 대표","summary":"목공과 제련 도구를 한곳에 모아 도시의 생산 기반을 세웁니다.","food":-4,"capacity":0,"production":18,"security":2,"reputation":2},
	"outpost":{"name":"외곽 초소","speaker":"경계 인력 대표","summary":"도시로 드는 길을 감시해 약탈과 기습에 대비합니다.","food":-3,"capacity":0,"production":1,"security":18,"reputation":1},
}
const CITY_ADMIN_ICON_PATHS := {
	"population":"res://assets/ui/city_admin/population.svg",
	"food":"res://assets/ui/city_admin/food.svg",
	"production":"res://assets/ui/city_admin/production.svg",
	"security":"res://assets/ui/city_admin/security.svg",
}
const CITY_ALLOCATION_PRESETS := {
	"balanced":{"name":"균형","labor":40,"food":35,"guard":25,"summary":"세 분야를 고르게 유지합니다."},
	"growth":{"name":"성장","labor":55,"food":35,"guard":10,"summary":"건설과 정착을 우선합니다."},
	"defense":{"name":"방비","labor":30,"food":25,"guard":45,"summary":"경계와 치안을 우선합니다."},
}
const ProjectEpochUiFactoryScript = preload(
    "res://src/ui/project_epoch_ui_factory.gd"
)
const StrategyReadModelScript = preload(
    "res://src/presentation/strategy_read_model.gd"
)


# Application state ----------------------------------------------------------

var gateway := StrategyGateway.new()
var read_model
var state := ScreenState.START

var selected_country := "goguryeo"
var selected_province := -1
var selected_provinces: Array[int] = []

var pending_sources: Array[int] = []
var pending_source := -1
var pending_kind := ""
var pending_amount := 0
var peace_demands: Array[int] = []

var governor_enabled := false
var map_mode_index := 0
var logs: Array[Dictionary] = []

var founding_region_id := -1
var first_decree_reviewed := false
var founding_sites: Array[Dictionary] = []
var selected_founding_site_id := ""
var founding_site_confirmed := false
var founding_dialog: ConfirmationDialog
var city_name_dialog: Window
var city_name_input: LineEdit
var founded_city_name := ""
var first_construction_dialog: Window
var settlement_preview
var first_construction_id := ""
var first_construction_stage := 0
var construction_timer: Timer
var city_detail_dialog: Window
var city_detail_preview
var city_management := {"labor":40,"food":35,"guard":25}
var settler_dialog: Window
var settler_outcome := ""
var city_households := 0
var city_population_profile := {"farmers":0,"artisans":0,"guards":0}
var city_food_reserve := 100
var city_food_capacity := 100
var city_reputation := 50
var city_production := 0
var city_security := 0
var priority_project_dialog: Window
var first_priority_project_id := ""


# Constructed UI references --------------------------------------------------

var screens: Dictionary = {}
var maps: Dictionary = {}
var ui: Dictionary = {}

var move_dialog: Window
var diplomacy_dialog: Window
var peace_dialog: Window
var toast: PanelContainer
var toast_timer: Timer


# Lifecycle ------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_project_theme()

	read_model = StrategyReadModelScript.new(gateway)
	_build_screens()
	_connect_gateway_signals()
	_load_initial_catalog()

	_show(ScreenState.START)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _apply_project_theme() -> void:
	var epoch_theme = load("res://themes/project_epoch_theme.tres")
	if epoch_theme is Theme:
		theme = epoch_theme


func _connect_gateway_signals() -> void:
	gateway.snapshot_changed.connect(_sync_snapshot)
	gateway.command_queue_changed.connect(_rebuild_queue)
	gateway.integration_notice.connect(_on_integration_notice)
	gateway.turn_requested.connect(_on_turn_requested)
	gateway.turn_requested.connect(_before_turn)


func _load_initial_catalog() -> void:
	if not gateway.load_local_catalog():
		_notify("기본 JSON 데이터를 불러오지 못했습니다.", "error")
		return

	selected_country = String(
		gateway.snapshot().get("player_country_id", "goguryeo")
	)
	_sync_snapshot(gateway.snapshot())


func _on_integration_notice(message: String) -> void:
	_notify(message, "info")
	_add_log("일반", message, "normal")


func _on_turn_requested(commands: Array) -> void:
	_add_log(
		"중요",
		"코어 턴 처리 요청 · %d개 명령" % commands.size(),
        "important"
	)


# Keyboard and controller input ---------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not _accept_game_keyboard_event(event):
		return

	match event.keycode:
		KEY_ESCAPE:
			if ui.has("first_decree_overlay") and ui.first_decree_overlay.visible:
				_close_first_decree()
			elif pending_kind.is_empty():
				_show(ScreenState.START)
			else:
				_cancel_mode()
		KEY_SPACE:
			gateway.submit_turn()
		KEY_M:
			_prepare_move("move")
		KEY_A:
			_prepare_move("attack")
		KEY_R:
			_queue_recruit()
		KEY_F:
			if selected_province != -1:
				_game_map().focus_province(selected_province)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			var mode_index := int(event.keycode - KEY_1)
			if mode_index < MAP_MODES.size():
				_set_map_mode(String(MAP_MODES[mode_index][0]))


func _accept_game_keyboard_event(event: InputEvent) -> bool:
	if not event.pressed or event.echo:
		return false
	if state != ScreenState.GAME:
		return false

	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is SpinBox:
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if state != ScreenState.GAME:
		return

	if event is InputEventJoypadButton and event.pressed:
		_handle_joypad_button(event)
	elif (
		event is InputEventJoypadMotion
		and absf(event.axis_value) > 0.35
	):
		_handle_joypad_motion(event)


func _handle_joypad_button(event: InputEventJoypadButton) -> void:
	match event.button_index:
		JOY_BUTTON_START:
			gateway.submit_turn()
		JOY_BUTTON_BACK:
			_open_ai_assistant()
		JOY_BUTTON_X:
			_queue_recruit()
		JOY_BUTTON_Y:
			_cycle_map_mode()
		JOY_BUTTON_B:
			_cancel_mode()
		JOY_BUTTON_LEFT_SHOULDER:
			_bottom_tab(ui.bottom_tabs.current_tab - 1)
		JOY_BUTTON_RIGHT_SHOULDER:
			_bottom_tab(ui.bottom_tabs.current_tab + 1)


func _handle_joypad_motion(event: InputEventJoypadMotion) -> void:
	if event.axis == JOY_AXIS_RIGHT_X:
		_game_map().nudge_camera(
			Vector2(-event.axis_value * 24.0, 0.0)
		)
	elif event.axis == JOY_AXIS_RIGHT_Y:
		_game_map().nudge_camera(
			Vector2(0.0, -event.axis_value * 24.0)
		)


func _cycle_map_mode() -> void:
	map_mode_index = (map_mode_index + 1) % MAP_MODES.size()
	_set_map_mode(String(MAP_MODES[map_mode_index][0]))


# Screen composition ---------------------------------------------------------

func _build_screens() -> void:
	var background := ColorRect.new(); background.color=Color("#10161d"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	for entry in [[ScreenState.START,_build_start()],[ScreenState.SCENARIO,_build_scenario()],[ScreenState.COUNTRY,_build_country()],[ScreenState.GAME,_build_game()]]:
		screens[entry[0]]=entry[1]; add_child(entry[1])
	_build_dialogs()
	_build_first_decree()


func _build_first_decree() -> void:
	var overlay:=ColorRect.new(); overlay.name="FirstDecreeOverlay"; overlay.color=Color(0.015,0.02,0.024,0.88); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.mouse_filter=Control.MOUSE_FILTER_STOP; overlay.hide(); ui.first_decree_overlay=overlay; add_child(overlay)
	var center:=CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.add_child(center)
	var panel:=PanelContainer.new(); panel.name="FirstDecreePanel"; panel.add_theme_stylebox_override("panel",_style("#211c16","#c5a565",2,8)); ui.first_decree_panel=panel; center.add_child(panel)
	var margin:=MarginContainer.new(); margin.add_theme_constant_override("margin_left",24); margin.add_theme_constant_override("margin_right",24); margin.add_theme_constant_override("margin_top",18); margin.add_theme_constant_override("margin_bottom",18); panel.add_child(margin)
	var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",10); margin.add_child(outer)
	var chapter:=_label("개척 연대기의 첫 장",13,Color("#b79a63"),HORIZONTAL_ALIGNMENT_CENTER); outer.add_child(chapter)
	var title:=_label("첫 개척령",28,Color("#ead7a1"),HORIZONTAL_ALIGNMENT_CENTER); ui.first_decree_title=title; outer.add_child(title)
	var rule:=HSeparator.new(); outer.add_child(rule)
	var body:=HBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",20); outer.add_child(body)
	var portrait:=TextureRect.new(); portrait.name="FirstDecreePortrait"; portrait.custom_minimum_size=Vector2(176,240); portrait.size_flags_vertical=Control.SIZE_EXPAND_FILL; portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ui.first_decree_portrait=portrait; body.add_child(portrait)
	var text:=RichTextLabel.new(); text.name="FirstDecreeText"; text.bbcode_enabled=true; text.fit_content=false; text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; text.size_flags_vertical=Control.SIZE_EXPAND_FILL; ui.first_decree_text=text; body.add_child(text)
	var footer:=HBoxContainer.new(); outer.add_child(footer)
	var seal:=_label("御命",14,Color("#b96755")); footer.add_child(seal); footer.add_spacer(true)
	var proclaim:=_button("개척지를 살피다",_close_first_decree,"primary",44); proclaim.name="ProclaimDecreeButton"; proclaim.custom_minimum_size.x=180; ui.first_decree_button=proclaim; footer.add_child(proclaim)

func _build_start() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color("#090d10")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var upper_glow := ColorRect.new()
	upper_glow.color = Color("#12181b")
	upper_glow.anchor_right = 1.0
	upper_glow.anchor_bottom = 0.34
	upper_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(upper_glow)

	for side in [0.0, 1.0]:
		var frame_line := ColorRect.new()
		frame_line.color = Color("#54452d")
		frame_line.anchor_left = side
		frame_line.anchor_right = side
		frame_line.anchor_top = 0.08
		frame_line.anchor_bottom = 0.92
		frame_line.offset_left = 42.0 if side == 0.0 else -43.0
		frame_line.offset_right = 43.0 if side == 0.0 else -42.0
		frame_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(frame_line)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var outer_frame := PanelContainer.new()
	outer_frame.name = "ClassicMenuFrame"
	outer_frame.custom_minimum_size = Vector2(640, 636)
	outer_frame.add_theme_stylebox_override(
		"panel",
		_style("#0b0f11", "#5f4e31", 3, 5)
	)
	center.add_child(outer_frame)

	var inner_frame := PanelContainer.new()
	inner_frame.add_theme_stylebox_override(
		"panel",
		_style("#171b1d", "#b08e50", 1, 2)
	)
	outer_frame.add_child(inner_frame)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 38)
	content_margin.add_theme_constant_override("margin_right", 38)
	content_margin.add_theme_constant_override("margin_top", 25)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	inner_frame.add_child(content_margin)

	var composition := VBoxContainer.new()
	composition.add_theme_constant_override("separation", 10)
	content_margin.add_child(composition)

	composition.add_child(
		_label(
			"IMPERIUM · CHRONICA · ORIENTIS",
			11,
			Color("#8d7b5c"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	)
	composition.add_child(_classic_title_rule())

	var title := _label(
		"PROJECT EPOCH",
		42,
		Color("#dfc27a"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title.name = "StartTitle"
	composition.add_child(title)
	composition.add_child(
		_label(
			"동방의 연대기",
			20,
			Color("#c3b28d"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	)
	composition.add_child(
		_label(
			"천하는 기록되고, 국가는 선택으로 남는다",
			13,
			Color("#7f8a89"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	)
	composition.add_child(_classic_title_rule())

	var actions := VBoxContainer.new()
	actions.name = "StartMenuActions"
	actions.add_theme_constant_override("separation", 8)
	composition.add_child(actions)

	var new_game := _start_menu_button(
		"Ⅰ   새 연대기 시작",
		func(): _show(ScreenState.SCENARIO),
		true
	)
	new_game.name = "NewChronicleButton"
	actions.add_child(new_game)

	var continue_game := _start_menu_button(
		"Ⅱ   연대기 이어가기",
		_load_game
	)
	continue_game.name = "ContinueChronicleButton"
	actions.add_child(continue_game)

	var settings_button := _start_menu_button(
		"Ⅲ   궁정 설정",
		_settings
	)
	settings_button.name = "StartSettingsButton"
	actions.add_child(settings_button)

	var quit_button := _start_menu_button(
		"Ⅳ   기록을 덮고 나가기",
		func(): get_tree().quit()
	)
	quit_button.name = "StartQuitButton"
	actions.add_child(quit_button)

	composition.add_spacer(false)
	composition.add_child(
		_label(
			"고대 동아시아 대전략 시뮬레이션",
			12,
			Color("#81765f"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	)
	composition.add_child(
		_label(
			"CODEX EDITION  ·  BUILD 1000",
			10,
			Color("#555e5f"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	)
	return root


func _classic_title_rule() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var left_rule := HSeparator.new()
	left_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_rule)
	row.add_child(
		_label("◆", 11, Color("#9d7e46"), HORIZONTAL_ALIGNMENT_CENTER)
	)

	var right_rule := HSeparator.new()
	right_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_rule)
	return row


func _start_menu_button(
	text: String,
	action: Callable,
	primary := false
) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#d8cfb7"))
	button.add_theme_color_override("font_hover_color", Color("#f2dda1"))
	button.add_theme_color_override("font_pressed_color", Color("#ffe9ae"))
	button.add_theme_stylebox_override(
		"normal",
		_style(
			"#282318" if primary else "#14191b",
			"#a1834d" if primary else "#584b36",
			1,
			2
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_style("#30291c", "#d0aa60", 2, 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_style("#3b2f1d", "#e0bd70", 2, 2)
	)
	button.add_theme_stylebox_override(
		"focus",
		_style("#24221b", "#d0aa60", 1, 2)
	)
	button.pressed.connect(action)
	return button

func _build_scenario() -> Control:
	var root := _margin(18)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	root.add_child(outer)

	outer.add_child(
		_header(
			"시나리오 선택",
			"시대와 지역을 고른 뒤 지도를 확인하세요",
			func(): _show(ScreenState.START)
		)
	)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 270
	outer.add_child(split)

	var left := _section("시대 · 지역 · 시나리오", 250)
	split.add_child(left)

	var era := OptionButton.new()
	era.add_item("고대 동아시아 · 프로토타입")
	era.add_item("시대 확정 후 추가")
	left.add_child(era)

	var region := OptionButton.new()
	region.add_item("한반도 · 요동 · 중국 동부 · 일본")
	left.add_child(region)
	left.add_child(
		_button(
			"고대 동아시아 기반\n프로토타입 시작",
			_refresh_scenario,
			"list",
			72
		)
	)

	var middle := _section("지도 미리보기")
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(middle)

	var scenario_map := StrategicMap.new()
	scenario_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps[ScreenState.SCENARIO] = scenario_map
	middle.add_child(scenario_map)

	var right := _section("시나리오 정보", 310)
	split.add_child(right)

	var detail := RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.scenario_detail = detail
	right.add_child(detail)

	var footer := HBoxContainer.new()
	footer.add_spacer(true)
	footer.add_child(
		_button("이전", func(): _show(ScreenState.START))
	)
	footer.add_child(
		_button(
			"국가 선택",
			func(): _show(ScreenState.COUNTRY),
            "primary"
		)
	)
	outer.add_child(footer)
	return root


func _build_country() -> Control:
	var root:=_margin(12)
	var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",8); root.add_child(outer)
	outer.add_child(_header("세력과 출발 권역 선택","천하의 형세를 살피고 첫 도시를 개척할 세력과 권역을 정하십시오",func():_show(ScreenState.SCENARIO)))
	var body:=HBoxContainer.new(); body.name="CountrySelectionBody"; body.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",8); ui.country_body=body; outer.add_child(body)
	var left:=_section("나라 목록",204); ui.country_left=left; body.add_child(left)
	var search:=LineEdit.new(); search.placeholder_text="국가명 · 정부 형태 검색"; search.text_changed.connect(_rebuild_countries); left.add_child(search)
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; left.add_child(scroll)
	var list:=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; ui.country_list=list; scroll.add_child(list)
	var center:=VBoxContainer.new(); center.name="CountryMapColumn"; center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center.add_theme_constant_override("separation",6); body.add_child(center)
	var map_title:=_label("천하도  ·  영토를 클릭하여 세력의 출발 권역 확인",15,Color("#d8bd7a")); center.add_child(map_title)
	var map_panel:=PanelContainer.new(); map_panel.name="CountryMapPanel"; map_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL; map_panel.add_theme_stylebox_override("panel",_style("#0c141a","#89754d",1,8)); center.add_child(map_panel)
	var map:=StrategicMap.new(); map.name="CountrySelectionMap"; map.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map.size_flags_vertical=Control.SIZE_EXPAND_FILL; map.province_selected.connect(_country_map_pick); maps[ScreenState.COUNTRY]=map; map_panel.add_child(map)
	var map_hint:=_label("마우스 휠: 확대·축소   ·   좌클릭 유지: 지도 이동   ·   영토 클릭: 세력 선택",12,Color("#8fa0a5")); map_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; center.add_child(map_hint)
	var dossier:=PanelContainer.new(); dossier.name="RulerDossier"; dossier.custom_minimum_size.x=272; dossier.add_theme_stylebox_override("panel",_style("#172127","#74623f",1,8)); ui.ruler_panel=dossier; ui.country_dossier=dossier; body.add_child(dossier)
	var right:=VBoxContainer.new(); right.add_theme_constant_override("separation",6); dossier.add_child(right)
	right.add_child(_label("군주와 국정",15,Color("#d8bd7a")))
	var info_scroll:=ScrollContainer.new(); info_scroll.name="RulerInfoScroll"; info_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; info_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; ui.country_info_scroll=info_scroll; right.add_child(info_scroll)
	var info:=VBoxContainer.new(); info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation",5); info_scroll.add_child(info)
	var portrait:=TextureRect.new(); portrait.name="RulerPortrait"; portrait.custom_minimum_size=Vector2(0,194); portrait.size_flags_horizontal=Control.SIZE_EXPAND_FILL; portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ui.ruler_portrait=portrait; ui.country_portrait=portrait; info.add_child(portrait)
	var fallback:=_label("초상 기록 없음",18,Color("#879399")); fallback.custom_minimum_size.y=194; fallback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; fallback.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; fallback.hide(); ui.ruler_fallback=fallback; info.add_child(fallback)
	var ruler_name:=_label("",21,Color("#e3cd8d")); ruler_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; ui.ruler_name=ruler_name; info.add_child(ruler_name)
	var ruler_title:=_label("",11,Color("#a9b4b5")); ruler_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; ruler_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; ui.ruler_title=ruler_title; info.add_child(ruler_title)
	var detail:=RichTextLabel.new(); detail.bbcode_enabled=true; detail.fit_content=false; detail.custom_minimum_size.y=72; ui.country_detail=detail; info.add_child(detail)
	var spectate:=CheckBox.new(); spectate.text="관전 모드"; info.add_child(spectate)
	var start_button:=_button("이 세력으로 개척 연대기 시작",_start_game,"primary"); start_button.name="CountryStartButton"; ui.country_start_button=start_button; right.add_child(start_button)
	return root


func _build_game() -> Control:
	var root := _margin(8)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	root.add_child(outer)

	outer.add_child(_top_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 244
	outer.add_child(split)
	split.add_child(_left_panel())

	var center_right := HSplitContainer.new()
	center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right.split_offset = 760
	split.add_child(center_right)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	center_right.add_child(center)
	center.add_child(_macro_toolbar())

	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override(
		"panel",
		_style("#0d151c", "#46535a", 1, 8)
	)
	center.add_child(map_panel)

	var game_map := StrategicMap.new()
	maps[ScreenState.GAME] = game_map
	_connect_game_map_signals(game_map)
	map_panel.add_child(game_map)

	center.add_child(_bottom_panel())
	center_right.add_child(_right_panel())
	return root


func _macro_toolbar() -> Control:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	toolbar.add_child(_label("MACRO", 12, Color("#d8bd7a")))
	toolbar.add_child(
		_button(
			"경제 취약지",
			_smart_recommend.bind("economy"),
            "small"
		)
	)
	toolbar.add_child(
		_button(
			"보급 위험",
			_smart_recommend.bind("supply"),
            "small"
		)
	)
	toolbar.add_child(
		_button(
			"선택지 일괄 개발",
			_simple_command.bind("develop"),
            "small"
		)
	)
	toolbar.add_child(
		_button("Governor", _toggle_governor, "small")
	)
	toolbar.add_child(
		_button("AI 제안", _open_ai_assistant, "small")
	)
	return toolbar


func _connect_game_map_signals(game_map: StrategicMap) -> void:
	game_map.province_selected.connect(_province_pick)
	game_map.selection_changed.connect(_selection_changed)
	game_map.province_dropped.connect(_quick_drag_move)
	game_map.command_target_selected.connect(_map_target)
	game_map.founding_site_selected.connect(_founding_site_pick)
	game_map.settlement_double_clicked.connect(_open_city_detail)
	game_map.tooltip_changed.connect(_map_tooltip)


func _top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 62
	panel.add_theme_stylebox_override(
		"panel",
		_style("#18232c", "#8d764b", 1, 8)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	row.add_child(
		_button("☰", func(): _show(ScreenState.START))
	)

	var title := _label("PROJECT EPOCH", 18, Color("#d8bd7a"))
	title.custom_minimum_size.x = 160
	row.add_child(title)

	var statistics := [
		["날짜", "date", "1000. 1. 1"],
		["국고", "treasury", "0"],
		["수입", "income", "+0"],
		["인력", "manpower", "0"],
		["안정도", "stability", "0"],
		["전쟁 피로", "exhaustion", "0%"]
	]
	for statistic in statistics:
		var value := _stat(String(statistic[0]), String(statistic[2]))
		ui[statistic[1]] = value
		row.add_child(value.get_parent())

	row.add_spacer(true)

	var alerts_button := _button(
		"알림 0",
		func(): _bottom_tab(1)
	)
	ui.alert_button = alerts_button
	row.add_child(alerts_button)
	row.add_child(
		_button(
			"턴 실행  Space",
			gateway.submit_turn,
            "primary"
		)
	)
	return panel


func _left_panel() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 230
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP

	var map_box := _section("지도 모드")
	map_box.name = "지도"

	var search := LineEdit.new()
	search.placeholder_text = "Province 검색"
	search.text_submitted.connect(_search_province)
	map_box.add_child(search)

	var grid := GridContainer.new()
	grid.columns = 2
	map_box.add_child(grid)
	for mode in MAP_MODES:
		grid.add_child(
			_button(
				String(mode[1]),
				_set_map_mode.bind(String(mode[0])),
                "small"
			)
		)

	ui.mode_title = _label("정치 지도", 15, Color("#d7ba76"))
	map_box.add_child(ui.mode_title)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	ui.legend = legend
	map_box.add_child(legend)
	tabs.add_child(map_box)

	var nation := _section("국가 개요")
	nation.name = "국가"
	nation.add_child(
		_label(
			"국가 자원과 외교 상태를 빠르게 확인합니다.",
			13,
			Color("#aab5b9")
		)
	)
	nation.add_child(_button("외교 화면", _open_diplomacy))
	nation.add_child(_button("전쟁 · 평화", _open_peace))
	tabs.add_child(nation)

	var alerts := _section("중요 알림")
	alerts.name = "알림"
	alerts.add_child(
		_label(
			"전쟁, 반란, 외교 제안을 중요도 순으로 표시합니다.",
			13,
			Color("#aab5b9")
		)
	)
	tabs.add_child(alerts)

	var management := _section("자동 관리")
	management.name = "관리"
	management.add_child(
		_label(
			"Governor가 선택 기준에 따라 반복 투자를 Task Queue에 넣습니다.",
			12,
			Color("#aab5b9")
		)
	)
	management.add_child(
		_button(
			"Governor 켜기/끄기",
			_toggle_governor,
            "primary"
		)
	)
	management.add_child(
		_button("AI Assistant 추천", _open_ai_assistant)
	)
	management.add_child(
		_button(
			"전 영토 중 취약지 선택",
			_smart_recommend.bind("economy")
		)
	)
	tabs.add_child(management)
	return tabs


func _right_panel() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 330
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP

	var province := _section("Province 정보")
	province.name = "Province"
	ui.province_title = _label(
		"Province를 선택하세요",
		21,
		Color("#e4cf97")
	)
	province.add_child(ui.province_title)

	var detail := RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.province_detail = detail
	province.add_child(detail)

	ui.action_status = _label(
		"지도에서 Province를 선택하세요.",
		12,
		Color("#91a0a6")
	)
	ui.action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	province.add_child(ui.action_status)

	var actions := GridContainer.new()
	actions.columns = 2
	province.add_child(actions)

	var province_actions := [
		["병력 모집  R", _queue_recruit, "primary"],
		["군대 이동  M", _prepare_move.bind("move"), "default"],
		["공격  A", _prepare_move.bind("attack"), "danger"],
		["개발 투자", _simple_command.bind("develop"), "default"],
		["요새 건설", _simple_command.bind("fortify"), "default"],
		["수도 이전", _simple_command.bind("move_capital"), "default"],
		["점령지 관리", _simple_command.bind("occupation"), "default"],
		["외교", _open_diplomacy, "default"]
	]
	for action in province_actions:
		actions.add_child(
			_button(
				String(action[0]),
				action[1],
				String(action[2])
			)
		)
	tabs.add_child(province)

	var army := _section("군대")
	army.name = "군대"
	army.add_child(
		_label(
			"출발지 → 병력 수 → 목적지\n명령은 턴 실행 전까지 취소할 수 있습니다.",
			13,
			Color("#aab5b9")
		)
	)
	tabs.add_child(army)

	var diplomacy := _section("외교")
	diplomacy.name = "외교"
	diplomacy.add_child(
		_button("선택 국가 외교", _open_diplomacy, "primary")
	)
	diplomacy.add_child(_button("평화 협상", _open_peace))
	tabs.add_child(diplomacy)
	return tabs


func _bottom_panel() -> Control:
	var tabs := TabContainer.new()
	tabs.name = "BottomTabs"
	tabs.custom_minimum_size.y = 188
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.bottom_tabs = tabs

	var queue_scroll := ScrollContainer.new()
	queue_scroll.name = "Task Queue"
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var queue := VBoxContainer.new()
	queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.queue = queue
	queue_scroll.add_child(queue)
	tabs.add_child(queue_scroll)

	var log_box := VBoxContainer.new()
	log_box.name = "이벤트 로그"
	var filters := HBoxContainer.new()
	log_box.add_child(filters)
	for category in ["전체", "전쟁", "외교", "경제", "반란", "중요"]:
		filters.add_child(
			_button(
				category,
				_filter_logs.bind(category),
                "small"
			)
		)

	var log := RichTextLabel.new()
	log.bbcode_enabled = true
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.log = log
	log_box.add_child(log)
	tabs.add_child(log_box)

	var wars := RichTextLabel.new()
	wars.name = "전쟁 현황"
	wars.bbcode_enabled = true
	ui.wars = wars
	tabs.add_child(wars)
	return tabs


func _build_dialogs() -> void:
	_build_tooltip()
	_build_toast()
	_build_move_dialog()
	_build_diplomacy_dialog()
	_build_peace_dialog()


func _build_tooltip() -> void:
	var tooltip := PanelContainer.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 90
	tooltip.add_theme_stylebox_override(
		"panel",
		_style("#101820", "#b59b63", 1, 7)
	)
	ui.tooltip = tooltip
	add_child(tooltip)

	var tooltip_label := Label.new()
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.custom_minimum_size = Vector2(210, 0)
	ui.tooltip_label = tooltip_label
	tooltip.add_child(tooltip_label)


func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.visible = false
	toast.z_index = 100
	toast.custom_minimum_size = Vector2(440, 52)
	add_child(toast)

	var toast_label := Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.toast_label = toast_label
	toast.add_child(toast_label)

	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.timeout.connect(func(): toast.hide())
	add_child(toast_timer)


func _build_move_dialog() -> void:
	move_dialog = Window.new()
	move_dialog.visible = false
	move_dialog.exclusive = true
	move_dialog.title = "군대 명령"
	move_dialog.size = Vector2i(440, 300)
	move_dialog.close_requested.connect(_cancel_mode)
	add_child(move_dialog)

	var move_box := _window_box(move_dialog)
	ui.move_summary = _label(
		"출발 Province",
		16,
		Color("#dfc889")
	)
	move_box.add_child(ui.move_summary)

	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 999999
	amount.value_changed.connect(_on_move_amount_changed)
	ui.move_amount = amount
	move_box.add_child(amount)

	var presets := HBoxContainer.new()
	move_box.add_child(presets)
	presets.add_child(
		_button("전 병력", _move_fraction.bind(1.0), "small")
	)
	presets.add_child(
		_button("절반", _move_fraction.bind(0.5), "small")
	)
	presets.add_child(
		_button(
			"주둔군 1 남기기",
			_move_fraction.bind(0.0),
            "small"
		)
	)

	move_box.add_child(
		_label(
			"적국 목적지는 공격으로 표시됩니다. 전쟁 상태를 먼저 확인합니다.",
			12,
			Color("#c99572")
		)
	)

	var buttons := HBoxContainer.new()
	buttons.add_spacer(true)
	buttons.add_child(_button("취소", _cancel_mode))
	buttons.add_child(
		_button("목적지 선택", _begin_target, "primary")
	)
	move_box.add_child(buttons)


func _on_move_amount_changed(value: float) -> void:
	pending_amount = int(value)


func _build_diplomacy_dialog() -> void:
	diplomacy_dialog = Window.new()
	diplomacy_dialog.visible = false
	diplomacy_dialog.exclusive = true
	diplomacy_dialog.title = "외교"
	diplomacy_dialog.size = Vector2i(720, 620)
	diplomacy_dialog.close_requested.connect(
		func(): diplomacy_dialog.hide()
	)
	add_child(diplomacy_dialog)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diplomacy_dialog.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	ui.diplomacy_box = box
	scroll.add_child(box)


func _build_peace_dialog() -> void:
	peace_dialog = Window.new()
	peace_dialog.visible = false
	peace_dialog.exclusive = true
	peace_dialog.title = "평화 협상"
	peace_dialog.size = Vector2i(760, 650)
	peace_dialog.close_requested.connect(_close_peace)
	add_child(peace_dialog)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	peace_dialog.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	ui.peace_box = box
	scroll.add_child(box)


# Screen navigation and snapshot presentation --------------------------------

func _show(next_state: ScreenState) -> void:
	state = next_state
	for screen_state in screens:
		screens[screen_state].visible = screen_state == next_state

	if ui.has("tooltip"):
		ui.tooltip.hide()

	match next_state:
		ScreenState.SCENARIO:
			_refresh_scenario()
			call_deferred("_frame_map", maps.get(next_state))
		ScreenState.COUNTRY:
			_rebuild_countries("")
			_refresh_country()
			call_deferred("_frame_map", maps.get(next_state))
		ScreenState.GAME:
			_sync_snapshot(gateway.snapshot())
			call_deferred("_frame_map", maps.get(next_state))


func _load_game() -> void:
	if not gateway.load_autosave():
		return
	selected_country=String(gateway.snapshot().get("player_country_id","goguryeo"))
	selected_province=-1
	_sync_snapshot(gateway.snapshot())
	_show(ScreenState.GAME)
	var campaign_restored:=_restore_campaign_state(gateway.campaign_save_data())
	if campaign_restored: call_deferred("_resume_campaign_after_load")
	_notify("자동 저장 게임을 불러왔습니다." if campaign_restored else "전략 자동 저장을 불러왔습니다. 개척 내정 기록은 없는 이전 세이브입니다.","success")


func _sync_snapshot(snapshot: Dictionary) -> void:
	for strategy_map in maps.values():
		strategy_map.set_snapshot(snapshot)

	selected_country = String(
		snapshot.get("player_country_id", selected_country)
	)
	var country := gateway.country(selected_country)
	var date: Dictionary = snapshot.get("date", {})

	if ui.has("date"):
		ui.date.text = "%d. %d. %d" % [
			int(date.get("year", 1000)),
			int(date.get("month", 1)),
			int(date.get("day", 1))
		]
	if ui.has("treasury"):
		ui.treasury.text = _number(int(country.get("treasury", 0)))
	if ui.has("income"):
		ui.income.text = "+%s" % _number(_income(selected_country))
	if ui.has("manpower"):
		ui.manpower.text = _number(int(country.get("manpower", 0)))
	if ui.has("stability"):
		ui.stability.text = str(country.get("stability", 0))
	if ui.has("exhaustion"):
		ui.exhaustion.text = "%d%%" % int(
			country.get("war_exhaustion", 0)
		)

	_refresh_province()
	_refresh_wars()
	_legend()


# Scenario and country selection --------------------------------------------

func _refresh_scenario() -> void:
	if not ui.has("scenario_detail"):
		return

	var scenarios := gateway.scenarios()
	var scenario: Dictionary = {}
	if not scenarios.is_empty():
		scenario = scenarios[0]

	var recommendations := PackedStringArray()
	for country_value in gateway.countries().values():
		if recommendations.size() >= 5:
			break
		var country: Dictionary = country_value
		recommendations.append(
			"• %s" % String(country.get("name", country.get("id", "")))
		)

	ui.scenario_detail.text = (
        "[font_size=22][color=#ddc47e]%s[/color][/font_size]\n\n"
		+ "시작 연도  [b]%s년(프로토타입)[/b]\n"
		+ "국가 수  [b]%d[/b]\n"
		+ "턴 방식  [b]동시 명령[/b]\n\n"
		+ "%s\n\n"
		+ "[color=#9fb0b5]플레이 가능 국가[/color]\n%s"
	) % [
		String(scenario.get("name", "고대 동아시아 기반 시나리오")),
		str(scenario.get("start_date", {}).get("year", 300)),
		gateway.countries().size(),
		String(scenario.get("description", "")),
		"\n".join(recommendations)
	]


func _rebuild_countries(filter_text:String) -> void:
	if not ui.has("country_list"): return
	for child in ui.country_list.get_children(): child.queue_free()
	var needle:=filter_text.strip_edges().to_lower()
	for id_value in gateway.countries().keys():
		var id:=String(id_value); var country:=gateway.country(id); var haystack:=(String(country.get("name",""))+" "+String(country.get("government",""))).to_lower()
		if needle!="" and needle not in haystack: continue
		ui.country_list.add_child(_button("%s\n%s · 난이도 %s" % [country.get("name",id),country.get("government","정부"),_difficulty(country)],_select_country.bind(id),"list",64))

func _select_country(country_id:String) -> void:
	selected_country=country_id
	_refresh_country(true)
	var capital:=int(gateway.country(country_id).get("capital_province",-1))
	if capital!=-1: maps[ScreenState.COUNTRY].selected_province_id=capital; maps[ScreenState.COUNTRY].focus_province(capital,1.35)

func _country_map_pick(province_id:int) -> void:
	var owner:=String(gateway.province(province_id).get("owner","")); if owner!="": _select_country(owner)

func _ruler_profile(country_id:String) -> Dictionary:
	return RULER_PROFILES.get(country_id,{"name":"기록되지 않은 군주","title":"계보 미상","age":0,"administration":0,"military":0})

func _refresh_ruler(country_id:String,animate:bool=false) -> void:
	if not ui.has("ruler_portrait"): return
	var profile:=_ruler_profile(country_id)
	ui.ruler_name.text=String(profile.get("name","기록되지 않은 군주"))
	ui.ruler_title.text="%s  ·  %d세  ·  행정 %d  무력 %d" % [profile.get("title","계보 미상"),int(profile.get("age",0)),int(profile.get("administration",0)),int(profile.get("military",0))]
	var portrait_path:=String(RULER_PORTRAIT_PATHS.get(country_id,""))
	if portrait_path!="" and ResourceLoader.exists(portrait_path):
		ui.ruler_portrait.texture=load(portrait_path); ui.ruler_portrait.show(); ui.ruler_fallback.hide()
	else:
		ui.ruler_portrait.texture=null; ui.ruler_portrait.hide(); ui.ruler_fallback.show()
	if not animate: return
	if ui.has("ruler_tween") and is_instance_valid(ui.ruler_tween): ui.ruler_tween.kill()
	var portrait:TextureRect=ui.ruler_portrait
	portrait.pivot_offset=portrait.size*0.5; portrait.modulate=Color(1,1,1,0); portrait.scale=Vector2(0.965,0.965)
	var tween:=create_tween().set_parallel(true)
	tween.tween_property(portrait,"modulate",Color.WHITE,0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait,"scale",Vector2.ONE,0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ui.ruler_tween=tween

func _refresh_country(animate_portrait:bool=false) -> void:
	if not ui.has("country_detail"): return
	var country:=gateway.country(selected_country)
	ui.country_detail.text="[font_size=22][color=#dec783]%s[/color][/font_size]\n[color=%s]████[/color]  %s\n\n정부  [b]%s[/b]\n출발 권역  [b]%s[/b]\n국고  [b]%s[/b]\n인구  [b]%s[/b]\n인력  [b]%s[/b]\n안정도  [b]%s[/b]\n난이도  [b]%s[/b]\n\nProvince %d · 육군 %s" % [country.get("name",selected_country),country.get("color","#777777"),country.get("id",""),country.get("government","정부"),_province_name(int(country.get("capital_province",-1))),_number(int(country.get("treasury",0))),_number(_country_total(selected_country,"population")),_number(int(country.get("manpower",0))),str(country.get("stability",0)),_difficulty(country),_owned(selected_country).size(),_number(_army_total(selected_country))]
	_refresh_ruler(selected_country,animate_portrait)

func _annal_entry(statement:String) -> String:
	var date:Dictionary=gateway.snapshot().get("date",{})
	return "[서기 %d년] %s" % [int(date.get("year",300)),statement]

func _campaign_save_data() -> Dictionary:
	return {
		"schema_version":CAMPAIGN_SAVE_SCHEMA_VERSION,
		"first_decree_reviewed":first_decree_reviewed,
		"founding_region_id":founding_region_id,
		"founding_sites_revealed":not founding_sites.is_empty(),
		"selected_founding_site_id":selected_founding_site_id,
		"founding_site_confirmed":founding_site_confirmed,
		"founded_city_name":founded_city_name,
		"first_construction_id":first_construction_id,
		"first_construction_stage":first_construction_stage,
		"settler_outcome":settler_outcome,
		"city_households":city_households,
		"city_population_profile":city_population_profile.duplicate(true),
		"city_food_reserve":city_food_reserve,
		"city_food_capacity":city_food_capacity,
		"city_reputation":city_reputation,
		"city_production":city_production,
		"city_security":city_security,
		"first_priority_project_id":first_priority_project_id,
		"city_management":city_management.duplicate(true),
		"logs":logs.duplicate(true),
	}

func _autosave_campaign_progress() -> Dictionary:
	gateway.set_campaign_save_data(_campaign_save_data())
	return gateway.save_autosave()

func _restore_campaign_state(data:Dictionary) -> bool:
	if data.is_empty(): return false
	var saved_version:=int(data.get("schema_version",0))
	if saved_version>CAMPAIGN_SAVE_SCHEMA_VERSION:
		_notify("개척 내정 세이브 버전이 현재 게임보다 새롭습니다.","warning")
		return false
	first_decree_reviewed=bool(data.get("first_decree_reviewed",false))
	founding_region_id=int(data.get("founding_region_id",gateway.country(selected_country).get("capital_province",-1)))
	selected_founding_site_id=String(data.get("selected_founding_site_id",""))
	founding_site_confirmed=bool(data.get("founding_site_confirmed",false))
	founded_city_name=String(data.get("founded_city_name",""))
	first_construction_id=String(data.get("first_construction_id",""))
	if not FIRST_CONSTRUCTIONS.has(first_construction_id): first_construction_id=""
	first_construction_stage=clampi(int(data.get("first_construction_stage",0)),0,3)
	settler_outcome=String(data.get("settler_outcome",""))
	if settler_outcome!="" and not SETTLER_CHOICES.has(settler_outcome): settler_outcome=""
	city_households=maxi(0,int(data.get("city_households",0)))
	var saved_population=data.get("city_population_profile",{})
	city_population_profile=saved_population.duplicate(true) if saved_population is Dictionary else {"farmers":0,"artisans":0,"guards":0}
	for population_key in ["farmers","artisans","guards"]:
		city_population_profile[population_key]=maxi(0,int(city_population_profile.get(population_key,0)))
	city_food_capacity=maxi(1,int(data.get("city_food_capacity",100)))
	city_food_reserve=clampi(int(data.get("city_food_reserve",100)),0,city_food_capacity)
	city_reputation=clampi(int(data.get("city_reputation",50)),0,100)
	city_production=maxi(0,int(data.get("city_production",0)))
	city_security=maxi(0,int(data.get("city_security",0)))
	first_priority_project_id=String(data.get("first_priority_project_id",""))
	if first_priority_project_id!="" and not PRIORITY_PROJECTS.has(first_priority_project_id): first_priority_project_id=""
	var saved_management=data.get("city_management",{})
	city_management=saved_management.duplicate(true) if saved_management is Dictionary else {"labor":40,"food":35,"guard":25}
	for management_key in ["labor","food","guard"]:
		city_management[management_key]=clampi(int(city_management.get(management_key,0)),0,100)
	if int(city_management.labor)+int(city_management.food)+int(city_management.guard)!=100:
		city_management={"labor":40,"food":35,"guard":25}
	logs.clear()
	var saved_logs=data.get("logs",[])
	if saved_logs is Array:
		for entry in saved_logs:
			if entry is Dictionary: logs.append(entry.duplicate(true))
	while logs.size()>LOG_LIMIT: logs.pop_front()
	_refresh_logs("전체")
	founding_sites=_game_map().founding_site_candidates(founding_region_id)
	if _founding_site(selected_founding_site_id).is_empty():
		selected_founding_site_id=""
		founding_site_confirmed=false
	selected_province=founding_region_id
	selected_provinces.clear()
	if founding_region_id!=-1: selected_provinces.append(founding_region_id)
	_game_map().selected_province_id=founding_region_id
	_game_map().set_selected_provinces(selected_provinces)
	if founded_city_name!="":
		_game_map().clear_founding_sites()
		var appearance:="camp"
		if first_construction_id!="": appearance=String(FIRST_CONSTRUCTIONS[first_construction_id].appearance)
		_update_settlement_marker(appearance)
	elif first_decree_reviewed and not founding_site_confirmed:
		_game_map().set_founding_sites(founding_sites)
		if selected_founding_site_id!="": _game_map().select_founding_site(selected_founding_site_id)
	else:
		_game_map().clear_founding_sites()
	return true

func _resume_campaign_after_load() -> void:
	_focus_starting_region()
	if founded_city_name=="":
		if not first_decree_reviewed:
			_show_first_decree()
		elif founding_site_confirmed:
			_open_city_naming()
		else:
			if ui.has("action_status"): ui.action_status.text="첫 과업 · 지도에 표시된 A·B·C 후보지 중 첫 도시의 터를 고르십시오."
		return
	if first_construction_id=="":
		if ui.has("action_status"): ui.action_status.text="첫 도시 · %s · 첫 사업을 정하십시오." % founded_city_name
		_open_first_construction()
		return
	var construction:Dictionary=FIRST_CONSTRUCTIONS[first_construction_id]
	_update_settlement_marker(String(construction.appearance))
	if first_construction_stage<3:
		if ui.has("action_status"): ui.action_status.text="%s · 공사 %d/3 복원" % [founded_city_name,first_construction_stage]
		_ensure_construction_timer()
		construction_timer.start()
		return
	if settler_outcome=="":
		_open_settler_request()
		return
	if first_priority_project_id=="":
		_open_priority_project_council()
		return
	if ui.has("action_status"): ui.action_status.text="%s · %s · 정착 %d가구 · 식량 %d/%d" % [founded_city_name,_priority_project_name(),city_households,city_food_reserve,city_food_capacity]

func _start_game() -> void:
	if selected_country=="": _notify("플레이할 세력을 선택하세요.","warning"); return
	if not gateway.select_player_country(selected_country): _notify("세력을 선택하지 못했습니다.","error"); return
	var country:=gateway.country(selected_country)
	first_decree_reviewed=false; founding_region_id=int(country.get("capital_province",-1)); founding_sites.clear(); selected_founding_site_id=""; founding_site_confirmed=false; founded_city_name=""; first_construction_id=""; first_construction_stage=0; settler_outcome=""; city_households=0; city_population_profile={"farmers":0,"artisans":0,"guards":0}; city_food_reserve=100; city_food_capacity=100; city_reputation=50; city_production=0; city_security=0; first_priority_project_id=""; city_management={"labor":40,"food":35,"guard":25}
	var starting_region_name:=_province_name(founding_region_id)
	var entry:=_annal_entry("%s(플레이어)가 %s 권역에 들어 첫 도시의 개척을 시작하다." % [_country_name(selected_country),starting_region_name])
	_add_log("중요",entry,"important"); _show(ScreenState.GAME)
	selected_province=founding_region_id; selected_provinces.clear(); _game_map().clear_founding_sites(); _game_map().set_settlement_markers([])
	if founding_region_id!=-1: selected_provinces.append(founding_region_id); _game_map().selected_province_id=founding_region_id
	_autosave_campaign_progress()
	call_deferred("_focus_starting_region")
	call_deferred("_show_first_decree")

func _focus_starting_region() -> void:
	if founding_region_id!=-1: _game_map().focus_province(founding_region_id,1.45)
func _show_first_decree() -> void:
	if not ui.has("first_decree_overlay"): return
	var country:=gateway.country(selected_country)
	var starting_region_name:=_province_name(int(country.get("capital_province",-1)))
	var profile:=_ruler_profile(selected_country)
	var ruler_name:=String(profile.get("name","군주"))
	ui.first_decree_title.text="%s의 첫 개척령" % ruler_name
	ui.first_decree_text.text="[color=#b9a477][서기 %d년 · 출발 권역 %s][/color]\n\n[font_size=25][color=#ead7a1]개척령[/color][/font_size]\n\n짐과 백성이 오늘 %s 권역에 이르렀다. 아직 이 땅에 우리의 도시는 없다.\n\n물과 경작지를 얻을 수 있고 외적을 막아내기 좋은 곳을 살펴, 이 권역 안에 우리 세력의 첫 도시를 세울 터를 정하라. 사람과 물자를 함부로 소모하지 말고 오래 버틸 자리를 택하도록 하라.\n\n[color=#c8b98f]첫 도시가 세워지는 날부터 우리의 연대기를 기록한다.[/color]" % [int(gateway.snapshot().get("date",{}).get("year",300)),starting_region_name,starting_region_name]
	var portrait_path:=String(RULER_PORTRAIT_PATHS.get(selected_country,""))
	ui.first_decree_portrait.texture=load(portrait_path) if portrait_path!="" and ResourceLoader.exists(portrait_path) else null
	ui.first_decree_overlay.show(); ui.first_decree_overlay.move_to_front()
	var panel:PanelContainer=ui.first_decree_panel; panel.pivot_offset=panel.size*0.5; panel.modulate=Color(1,1,1,0); panel.scale=Vector2(0.96,0.96)
	if ui.has("first_decree_tween") and is_instance_valid(ui.first_decree_tween): ui.first_decree_tween.kill()
	var tween:=create_tween().set_parallel(true); tween.tween_property(panel,"modulate",Color.WHITE,0.32); tween.tween_property(panel,"scale",Vector2.ONE,0.44).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT); ui.first_decree_tween=tween
	ui.first_decree_button.grab_focus()

func _close_first_decree() -> void:
	if not ui.has("first_decree_overlay") or not ui.first_decree_overlay.visible: return
	ui.first_decree_overlay.hide()
	first_decree_reviewed=true
	var starting_region_name:=_province_name(founding_region_id)
	_add_log("중요",_annal_entry("%s(플레이어)가 %s 권역에서 첫 도시의 터를 찾기 시작하다." % [_country_name(selected_country),starting_region_name]),"important")
	_prepare_founding_sites()

func _prepare_founding_sites() -> void:
	founding_sites=_game_map().founding_site_candidates(founding_region_id)
	_game_map().set_founding_sites(founding_sites)
	_focus_starting_region()
	if ui.has("action_status"): ui.action_status.text="첫 과업 · 지도에 표시된 A·B·C 후보지 중 첫 도시의 터를 고르십시오."
	_notify("%s 권역에 도시 후보지 3곳이 표시되었습니다." % _province_name(founding_region_id),"info")
	_autosave_campaign_progress()

func _founding_site(site_id:String) -> Dictionary:
	for site in founding_sites:
		if String(site.get("id",""))==site_id: return site
	return {}

func _founding_site_pick(site_id:String) -> void:
	if founding_site_confirmed: return
	var site:=_founding_site(site_id)
	if site.is_empty(): return
	selected_founding_site_id=site_id; _game_map().select_founding_site(site_id)
	if is_instance_valid(founding_dialog): founding_dialog.queue_free()
	founding_dialog=ConfirmationDialog.new(); founding_dialog.title="첫 도시 후보지 · %s" % String(site.get("name","후보지")); founding_dialog.ok_button_text="이곳을 도시 터로 정한다"; founding_dialog.cancel_button_text="다른 곳을 살핀다"
	founding_dialog.dialog_text="%s 후보 · %s\n\n강점  %s\n부담  %s\n\n이곳을 첫 도시의 터로 정하시겠습니까?" % [String(site.get("letter","?")),String(site.get("name","후보지")),String(site.get("summary","")),String(site.get("tradeoff",""))]
	founding_dialog.confirmed.connect(func(): _confirm_founding_site(site); founding_dialog.queue_free())
	founding_dialog.canceled.connect(func(): founding_dialog.queue_free())
	add_child(founding_dialog); founding_dialog.popup_centered(Vector2i(520,300))

func _confirm_founding_site(site:Dictionary) -> void:
	if site.is_empty() or founding_site_confirmed: return
	selected_founding_site_id=String(site.get("id","")); founding_site_confirmed=true
	_game_map().select_founding_site(selected_founding_site_id)
	var site_name:=String(site.get("name","후보지")); var region_name:=_province_name(founding_region_id)
	_add_log("중요",_annal_entry("%s(플레이어)가 %s 권역의 %s을 첫 도시의 터로 정하다." % [_country_name(selected_country),region_name,site_name]),"important")
	if ui.has("action_status"): ui.action_status.text="첫 도시 부지 확정 · %s · 도시의 이름을 정하십시오." % site_name
	_game_map().clear_founding_sites(); _notify("첫 도시의 터를 %s으로 정했습니다." % site_name,"success")
	_autosave_campaign_progress()
	call_deferred("_open_city_naming")

func _recommended_city_name() -> String:
	if DEFAULT_CITY_NAMES.has(selected_country): return String(DEFAULT_CITY_NAMES[selected_country])
	var region_name:=_province_name(founding_region_id)
	for suffix in [" 권역"," 분지"," 유역"]: region_name=region_name.trim_suffix(suffix)
	return region_name if region_name.ends_with("성") else region_name+"성"

func _open_city_naming() -> void:
	if is_instance_valid(city_name_dialog): city_name_dialog.queue_free()
	city_name_dialog=Window.new(); city_name_dialog.title="첫 도시의 이름"; city_name_dialog.size=Vector2i(520,290); city_name_dialog.unresizable=true; city_name_dialog.exclusive=true
	var box:=_window_box(city_name_dialog); box.add_child(_label("첫 도시를 어떻게 기록하겠습니까?",22,Color("#dec783")))
	box.add_child(_label("추천 이름이 입력되어 있습니다. 그대로 사용하거나 원하는 이름으로 고치십시오.",12,Color("#9eaaad")))
	city_name_input=LineEdit.new(); city_name_input.name="CityNameInput"; city_name_input.text=_recommended_city_name(); city_name_input.placeholder_text="도시 이름 입력"; city_name_input.max_length=18; city_name_input.text_submitted.connect(_confirm_city_name); ui.city_name_input=city_name_input; box.add_child(city_name_input)
	var hint:=_label("추천 · %s 세력과 %s의 역사 지명을 기준으로 제안" % [_country_name(selected_country),_province_name(founding_region_id)],11,Color("#887c63")); box.add_child(hint)
	var row:=HBoxContainer.new(); row.add_child(_button("추천 이름 되돌리기",func(): city_name_input.text=_recommended_city_name(),"small")); row.add_spacer(true); row.add_child(_button("이 이름으로 도시를 세운다",_confirm_city_name,"primary")); box.add_child(row)
	city_name_dialog.close_requested.connect(func(): _notify("첫 도시의 이름을 정해야 개척을 계속할 수 있습니다.","warning"))
	add_child(city_name_dialog); city_name_dialog.popup_centered(); city_name_input.grab_focus(); city_name_input.select_all()

func _confirm_city_name(submitted_name:String="") -> void:
	var city_name:=submitted_name.strip_edges() if submitted_name.strip_edges()!="" else city_name_input.text.strip_edges()
	if city_name=="": _notify("도시 이름을 입력하십시오.","warning"); city_name_input.grab_focus(); return
	founded_city_name=city_name
	if is_instance_valid(city_name_dialog): city_name_dialog.hide()
	var site:=_founding_site(selected_founding_site_id); var site_name:=String(site.get("name","후보지"))
	_add_log("중요",_annal_entry("%s(플레이어)가 %s에 첫 도시를 세우고 이름을 %s이라 하다." % [_country_name(selected_country),site_name,city_name]),"important")
	if ui.has("action_status"): ui.action_status.text="첫 도시 · %s · 첫 사업을 정하십시오." % city_name
	_update_settlement_marker("camp"); _notify("첫 도시 %s이(가) 연대기에 기록되었습니다." % city_name,"success")
	_autosave_campaign_progress()
	call_deferred("_open_first_construction")

func _recommended_first_construction() -> String:
	return {"waterside":"well_storage","farmland":"farmland","highland":"palisade"}.get(selected_founding_site_id,"well_storage")

func _open_first_construction() -> void:
	if is_instance_valid(first_construction_dialog): first_construction_dialog.queue_free()
	first_construction_dialog=Window.new(); first_construction_dialog.title="첫 도시의 첫 사업"; first_construction_dialog.size=Vector2i(760,610); first_construction_dialog.unresizable=true; first_construction_dialog.exclusive=true
	var box:=_window_box(first_construction_dialog); box.add_theme_constant_override("separation",7)
	box.add_child(_label("%s의 첫 모습을 정하십시오" % founded_city_name,23,Color("#dec783")))
	box.add_child(_label("추천 사업이 강조되어 있지만 세 가지 중 원하는 사업을 직접 선택할 수 있습니다.",12,Color("#9eaaad")))
	settlement_preview=SettlementPreviewControl.new(); settlement_preview.name="SettlementPreview"; settlement_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(settlement_preview)
	var recommended:=_recommended_first_construction(); settlement_preview.set_variant(recommended)
	var recommendation:=_label("군주의 추천 · %s" % String(FIRST_CONSTRUCTIONS[recommended].name),13,Color("#d7b868")); ui.construction_recommendation=recommendation; box.add_child(recommendation)
	var choices:=VBoxContainer.new(); choices.add_theme_constant_override("separation",5); ui.first_construction_buttons={}; box.add_child(choices)
	for construction_id in ["well_storage","farmland","palisade"]:
		var construction:Dictionary=FIRST_CONSTRUCTIONS[construction_id]
		var prefix:="추천 · " if construction_id==recommended else ""
		var button:=_button("%s%s    %s\n%s" % [prefix,String(construction.name),String(construction.effect),String(construction.summary)],_choose_first_construction.bind(construction_id),"primary" if construction_id==recommended else "default",58)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.mouse_entered.connect(_preview_first_construction.bind(construction_id)); choices.add_child(button); ui.first_construction_buttons[construction_id]=button
	first_construction_dialog.close_requested.connect(func(): _notify("첫 사업을 정해야 도시의 개척을 계속할 수 있습니다.","warning"))
	add_child(first_construction_dialog); first_construction_dialog.popup_centered(); ui.first_construction_buttons[recommended].grab_focus()

func _preview_first_construction(construction_id:String) -> void:
	if is_instance_valid(settlement_preview): settlement_preview.set_variant(construction_id)

func _choose_first_construction(construction_id:String) -> void:
	if not FIRST_CONSTRUCTIONS.has(construction_id): return
	first_construction_id=construction_id; first_construction_stage=1
	if is_instance_valid(first_construction_dialog): first_construction_dialog.hide()
	var construction:Dictionary=FIRST_CONSTRUCTIONS[construction_id]
	_update_settlement_marker(String(construction.appearance)); _ensure_construction_timer(); construction_timer.start()
	_add_log("중요",_annal_entry("%s(플레이어)가 첫 도시 %s의 첫 사업으로 %s을 명하고 터를 재다." % [_country_name(selected_country),founded_city_name,String(construction.name)]),"important")
	if ui.has("action_status"): ui.action_status.text="%s · 공사 1/3 · 측량과 자재 집결" % founded_city_name
	_notify("%s의 측량과 자재 집결을 시작했습니다." % founded_city_name,"info")
	_autosave_campaign_progress()

func _ensure_construction_timer() -> void:
	if is_instance_valid(construction_timer): return
	construction_timer=Timer.new(); construction_timer.one_shot=true; construction_timer.wait_time=12.0; construction_timer.timeout.connect(_advance_first_construction_stage); add_child(construction_timer)

func _advance_first_construction_stage() -> void:
	if first_construction_id=="" or first_construction_stage>=3: return
	first_construction_stage+=1; var construction:Dictionary=FIRST_CONSTRUCTIONS[first_construction_id]
	_update_settlement_marker(String(construction.appearance))
	if is_instance_valid(city_detail_preview): city_detail_preview.set_construction_stage(first_construction_stage)
	if ui.has("city_detail_stage"): ui.city_detail_stage.text=_construction_stage_text()
	if first_construction_stage==2:
		_add_log("일반",_annal_entry("%s의 첫 사업에 기둥과 골조가 서다." % founded_city_name),"normal")
		if ui.has("action_status"): ui.action_status.text="%s · 공사 2/3 · 기초와 골조 건설" % founded_city_name
		construction_timer.start()
	else:
		construction_timer.stop()
		_add_log("중요",_annal_entry("%s(플레이어)의 첫 도시 %s에 %s이 완공되다." % [_country_name(selected_country),founded_city_name,String(construction.name)]),"important")
		if ui.has("action_status"): ui.action_status.text="%s · 공사 3/3 완공 · %s" % [founded_city_name,String(construction.effect)]
		_notify("%s의 %s이 완공되었습니다." % [founded_city_name,String(construction.name)],"success")
		call_deferred("_open_settler_request")
	_autosave_campaign_progress()

func _construction_stage_text() -> String:
	return {0:"사업 미정",1:"1/3 · 측량과 자재 집결",2:"2/3 · 기초와 골조 건설",3:"3/3 · 완공"}.get(first_construction_stage,"사업 미정")

func _update_settlement_marker(appearance:String) -> void:
	var site:=_founding_site(selected_founding_site_id)
	if site.is_empty(): return
	var marker_stage:=3 if appearance=="camp" else maxi(1,first_construction_stage)
	_game_map().set_settlement_markers([{"id":"first_city","name":founded_city_name,"position":site.position,"appearance":appearance,"stage":marker_stage,"households":city_households}])

func _open_settler_request() -> void:
	if settler_outcome!="": return
	if is_instance_valid(settler_dialog): settler_dialog.queue_free()
	settler_dialog=Window.new()
	settler_dialog.title="성문 앞의 30가구"
	settler_dialog.size=Vector2i(670,500)
	settler_dialog.unresizable=true
	settler_dialog.exclusive=true
	var box:=_window_box(settler_dialog)
	box.add_child(_label("첫 이주민이 도착하다",23,Color("#dec783")))
	var report:=RichTextLabel.new()
	report.bbcode_enabled=true
	report.fit_content=false
	report.custom_minimum_size.y=145
	report.text="[color=#b9a477]%s[/color]\n\n인근을 떠돌던 서른 가구가 %s의 바깥에 이르렀다. 그들 가운데에는 농사꾼과 목수, 대장장이와 사냥꾼이 섞여 있다.\n\n식량을 나누어 모두 받아들이거나, 필요한 사람만 가려 받거나, 아직 비축이 부족하다는 이유로 돌려보낼 수 있다." % [_annal_entry("백성이 새 도시의 문 앞에 모이다."),founded_city_name]
	box.add_child(report)
	ui.settler_choice_buttons={}
	for choice_id in ["accept_all","selective","refuse"]:
		var choice:Dictionary=SETTLER_CHOICES[choice_id]
		var button:=_button("%s\n%s" % [String(choice.name),String(choice.summary)],_choose_settler_response.bind(choice_id),"primary" if choice_id=="selective" else "default",62)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(button)
		ui.settler_choice_buttons[choice_id]=button
	settler_dialog.close_requested.connect(func(): _notify("정착을 요청한 가구들에게 답을 내려야 합니다.","warning"))
	add_child(settler_dialog)
	settler_dialog.popup_centered()

func _choose_settler_response(choice_id:String) -> void:
	if not SETTLER_CHOICES.has(choice_id) or settler_outcome!="": return
	var choice:Dictionary=SETTLER_CHOICES[choice_id]
	settler_outcome=choice_id
	city_households=int(choice.households)
	city_population_profile={"farmers":int(choice.farmers),"artisans":int(choice.artisans),"guards":int(choice.guards)}
	city_food_reserve=clampi(city_food_reserve+int(choice.food),0,city_food_capacity)
	city_reputation=clampi(city_reputation+int(choice.reputation),0,100)
	if is_instance_valid(settler_dialog): settler_dialog.hide()
	var construction:Dictionary=FIRST_CONSTRUCTIONS.get(first_construction_id,{"appearance":"camp"})
	_update_settlement_marker(String(construction.appearance))
	var statement:="%s(플레이어)가 %s에 이른 백성 %d가구를 받아들이다." % [_country_name(selected_country),founded_city_name,city_households]
	if choice_id=="refuse":
		statement="%s(플레이어)가 식량이 부족하다 하여 %s에 이른 백성을 돌려보내다." % [_country_name(selected_country),founded_city_name]
	elif choice_id=="selective":
		statement="%s(플레이어)가 %s에 이른 백성 가운데 농민과 장인 18가구를 가려 받아들이다." % [_country_name(selected_country),founded_city_name]
	_add_log("중요",_annal_entry(statement),"important")
	if ui.has("action_status"): ui.action_status.text="%s · 정착 %d가구 · 식량 %d · 민심 %d" % [founded_city_name,city_households,city_food_reserve,city_reputation]
	_notify(String(choice.summary),"success" if choice_id!="refuse" else "warning")
	_autosave_campaign_progress()
	call_deferred("_open_priority_project_council")

func _recommended_priority_project() -> String:
	if city_food_reserve<=85 or int(city_population_profile.farmers)>=12: return "irrigation"
	if int(city_population_profile.artisans)>=6: return "workshop"
	return "outpost"

func _open_priority_project_council() -> void:
	if first_priority_project_id!="": return
	if is_instance_valid(priority_project_dialog): priority_project_dialog.queue_free()
	priority_project_dialog=Window.new()
	priority_project_dialog.title="첫 운영 회의"
	priority_project_dialog.size=Vector2i(710,540)
	priority_project_dialog.unresizable=true
	priority_project_dialog.exclusive=true
	var box:=_window_box(priority_project_dialog)
	box.add_child(_label("서로 다른 세 가지 청원",23,Color("#dec783")))
	var recommendation_id:=_recommended_priority_project()
	var recommendation:Dictionary=PRIORITY_PROJECTS[recommendation_id]
	var report:=RichTextLabel.new()
	report.bbcode_enabled=true
	report.fit_content=false
	report.custom_minimum_size.y=150
	report.text="[color=#b9a477]%s[/color]\n\n정착 결정을 내린 뒤, 농민과 장인과 경계 인력의 대표가 차례로 첫 운영 사업을 청하였다.\n\n[color=#dec783]현재 추천: %s[/color]\n%s\n추천은 도시 상황에 따른 조언이며 다른 사업도 자유롭게 명할 수 있다." % [_annal_entry("새 도시의 사람들이 첫 운영 사업을 두고 의논하다."),String(recommendation.name),String(recommendation.summary)]
	box.add_child(report)
	ui.priority_project_buttons={}
	ui.priority_project_recommendation=recommendation_id
	for project_id in ["irrigation","workshop","outpost"]:
		var project:Dictionary=PRIORITY_PROJECTS[project_id]
		var recommended:bool=project_id==recommendation_id
		var prefix:="[추천] " if recommended else ""
		var button:=_button("%s%s — %s\n%s" % [prefix,String(project.name),String(project.speaker),String(project.summary)],_choose_priority_project.bind(project_id),"primary" if recommended else "default",66)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(button)
		ui.priority_project_buttons[project_id]=button
	priority_project_dialog.close_requested.connect(func(): _notify("세 대표 가운데 한 사람에게 첫 사업을 맡겨야 합니다.","warning"))
	add_child(priority_project_dialog)
	priority_project_dialog.popup_centered()

func _choose_priority_project(project_id:String) -> void:
	if not PRIORITY_PROJECTS.has(project_id) or first_priority_project_id!="": return
	var project:Dictionary=PRIORITY_PROJECTS[project_id]
	first_priority_project_id=project_id
	city_food_capacity+=int(project.capacity)
	city_food_reserve=clampi(city_food_reserve+int(project.food),0,city_food_capacity)
	city_production+=int(project.production)
	city_security+=int(project.security)
	city_reputation=clampi(city_reputation+int(project.reputation),0,100)
	if is_instance_valid(priority_project_dialog): priority_project_dialog.hide()
	_add_log("중요",_annal_entry("%s(플레이어)가 %s의 첫 운영 사업으로 %s을 명하다." % [_country_name(selected_country),founded_city_name,String(project.name)]),"important")
	if ui.has("action_status"): ui.action_status.text="%s · %s 착수 · 식량 %d/%d · 생산 %d · 방비 %d" % [founded_city_name,String(project.name),city_food_reserve,city_food_capacity,city_production,city_security]
	_notify("%s을 첫 운영 사업으로 정했습니다. %s" % [String(project.name),String(project.summary)],"success")
	_autosave_campaign_progress()

func _priority_project_name() -> String:
	if first_priority_project_id=="": return "아직 정하지 않음"
	return String(PRIORITY_PROJECTS[first_priority_project_id].name)

func _city_detail_window_size(viewport_size:Vector2) -> Vector2i:
	return Vector2i(clampi(int(viewport_size.x*0.82),720,980),clampi(int(viewport_size.y*0.82),480,720))

func _city_stat_card(icon_key:String,caption:String,value:String) -> PanelContainer:
	var panel:=PanelContainer.new()
	panel.custom_minimum_size=Vector2(132,76)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",9)
	panel.add_child(row)
	var icon:=TextureRect.new()
	icon.custom_minimum_size=Vector2(28,28)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path:=String(CITY_ADMIN_ICON_PATHS.get(icon_key,""))
	if icon_path!="" and ResourceLoader.exists(icon_path): icon.texture=load(icon_path)
	row.add_child(icon)
	var labels:=VBoxContainer.new()
	labels.add_child(_label(caption,11,Color("#8f9ca2")))
	labels.add_child(_label(value,16,Color("#e2dcc9")))
	row.add_child(labels)
	return panel

func _open_city_detail(settlement_id:String) -> void:
	if settlement_id!="first_city" or founded_city_name=="": return
	if is_instance_valid(city_detail_dialog): city_detail_dialog.queue_free()
	city_detail_dialog=Window.new()
	city_detail_dialog.title="%s · 도시 내정" % founded_city_name
	var available_size:=size if size.x>0 and size.y>0 else get_viewport_rect().size
	city_detail_dialog.size=_city_detail_window_size(available_size)
	city_detail_dialog.unresizable=true
	var box:=_window_box(city_detail_dialog)
	box.add_child(_label("%s 내정 대시보드" % founded_city_name,22,Color("#dec783")))
	var tabs:=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	ui.city_detail_tabs=tabs
	box.add_child(tabs)

	var overview:=HBoxContainer.new()
	overview.name="현황"
	overview.add_theme_constant_override("separation",18)
	tabs.add_child(overview)
	city_detail_preview=SettlementPreviewControl.new()
	city_detail_preview.custom_minimum_size.x=360
	city_detail_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	city_detail_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
	city_detail_preview.set_variant(first_construction_id if first_construction_id!="" else "camp")
	city_detail_preview.set_construction_stage(maxi(1,first_construction_stage))
	overview.add_child(city_detail_preview)
	var summary:=VBoxContainer.new()
	summary.custom_minimum_size.x=270
	summary.add_theme_constant_override("separation",8)
	overview.add_child(summary)
	var stage_label:=_label(_construction_stage_text(),15,Color("#d7b868"))
	ui.city_detail_stage=stage_label
	summary.add_child(stage_label)
	summary.add_child(_label("첫 운영 사업 · %s" % _priority_project_name(),12,Color("#c6b785")))
	var cards:=GridContainer.new()
	cards.columns=2
	cards.add_theme_constant_override("h_separation",8)
	cards.add_theme_constant_override("v_separation",8)
	cards.add_child(_city_stat_card("population","정착 가구","%d가구" % city_households))
	cards.add_child(_city_stat_card("food","식량 비축","%d / %d" % [city_food_reserve,city_food_capacity]))
	cards.add_child(_city_stat_card("production","생산 기반",str(city_production)))
	cards.add_child(_city_stat_card("security","도시 방비",str(city_security)))
	summary.add_child(cards)
	summary.add_child(_label("농민 %d · 기술자 %d · 경계 인력 %d" % [int(city_population_profile.farmers),int(city_population_profile.artisans),int(city_population_profile.guards)],12,Color("#9eaaad")))
	summary.add_child(_label("민심 %d / 100" % city_reputation,12,Color("#9eaaad")))
	summary.add_spacer(true)
	summary.add_child(_button("인력 배분 열기",func(): tabs.current_tab=1,"primary",40))
	summary.add_child(_button("닫기",func(): city_detail_dialog.hide(),"default",36))

	var allocation_scroll:=ScrollContainer.new()
	allocation_scroll.name="인력 배분"
	tabs.add_child(allocation_scroll)
	var controls:=VBoxContainer.new()
	controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation",9)
	allocation_scroll.add_child(controls)
	controls.add_child(_label("도시 인력 배분",18,Color("#d7b868")))
	controls.add_child(_label("세 분야의 합계를 100으로 맞추십시오. 추천 프리셋을 사용한 뒤 직접 조정할 수도 있습니다.",12,Color("#9eaaad")))
	var preset_id:=_recommended_city_allocation_preset()
	ui.city_allocation_preset_recommendation=preset_id
	var preset_row:=HBoxContainer.new()
	preset_row.add_theme_constant_override("separation",8)
	ui.city_allocation_preset_buttons={}
	for candidate_id in ["balanced","growth","defense"]:
		var preset:Dictionary=CITY_ALLOCATION_PRESETS[candidate_id]
		var recommended:bool=candidate_id==preset_id
		var preset_button:=_button(("[추천] " if recommended else "")+String(preset.name),_apply_city_allocation_preset.bind(candidate_id),"primary" if recommended else "default",40)
		preset_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		preset_row.add_child(preset_button)
		ui.city_allocation_preset_buttons[candidate_id]=preset_button
	controls.add_child(preset_row)
	ui.city_allocation_spins={}
	for item in [["정착과 건설","labor"],["식량과 비축","food"],["경계와 치안","guard"]]:
		var row:=HBoxContainer.new()
		var caption:=_label(String(item[0]),13)
		caption.custom_minimum_size.x=150
		row.add_child(caption)
		var spin:=SpinBox.new()
		spin.min_value=0
		spin.max_value=100
		spin.step=5
		spin.value=int(city_management[item[1]])
		spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(spin)
		controls.add_child(row)
		ui.city_allocation_spins[item[1]]=spin
		spin.value_changed.connect(_refresh_city_allocation_total)
	var total_row:=HBoxContainer.new()
	ui.city_allocation_total=_label("",13)
	total_row.add_child(ui.city_allocation_total)
	var total_bar:=ProgressBar.new()
	total_bar.min_value=0
	total_bar.max_value=100
	total_bar.show_percentage=false
	total_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.city_allocation_bar=total_bar
	total_row.add_child(total_bar)
	controls.add_child(total_row)
	controls.add_spacer(true)
	var action_row:=HBoxContainer.new()
	action_row.add_spacer(true)
	action_row.add_child(_button("닫기",func(): city_detail_dialog.hide(),"default",40))
	ui.city_allocation_apply=_button("배분 적용",_apply_city_details,"primary",40)
	action_row.add_child(ui.city_allocation_apply)
	controls.add_child(action_row)
	_refresh_city_allocation_total()
	city_detail_dialog.close_requested.connect(func(): city_detail_dialog.hide())
	add_child(city_detail_dialog)
	city_detail_dialog.popup_centered()

func _recommended_city_allocation_preset() -> String:
	if city_security<10: return "defense"
	if city_food_capacity>0 and float(city_food_reserve)/float(city_food_capacity)<0.75: return "growth"
	return "balanced"

func _apply_city_allocation_preset(preset_id:String) -> void:
	if not CITY_ALLOCATION_PRESETS.has(preset_id) or not ui.has("city_allocation_spins"): return
	var preset:Dictionary=CITY_ALLOCATION_PRESETS[preset_id]
	ui.city_allocation_spins.labor.value=int(preset.labor)
	ui.city_allocation_spins.food.value=int(preset.food)
	ui.city_allocation_spins.guard.value=int(preset.guard)
	_refresh_city_allocation_total()

func _refresh_city_allocation_total(_changed_value:float=0.0) -> void:
	if not ui.has("city_allocation_spins") or not ui.has("city_allocation_total"): return
	var total:=int(ui.city_allocation_spins.labor.value)+int(ui.city_allocation_spins.food.value)+int(ui.city_allocation_spins.guard.value)
	var valid:=total==100
	ui.city_allocation_total.text="합계 %d / 100%s" % [total," · 적용 가능" if valid else " · 조정 필요"]
	ui.city_allocation_total.add_theme_color_override("font_color",Color("#7ec59f") if valid else Color("#d98a72"))
	ui.city_allocation_bar.value=mini(total,100)
	ui.city_allocation_apply.disabled=not valid

func _apply_city_details() -> void:
	var next:={"labor":int(ui.city_allocation_spins.labor.value),"food":int(ui.city_allocation_spins.food.value),"guard":int(ui.city_allocation_spins.guard.value)}
	if int(next.labor)+int(next.food)+int(next.guard)!=100:
		_notify("도시 인력 배분의 합계를 100으로 맞추십시오.","warning")
		_refresh_city_allocation_total()
		return
	city_management=next
	if is_instance_valid(city_detail_dialog): city_detail_dialog.hide()
	_add_log("일반",_annal_entry("%s의 정착민을 건설 %d, 비축 %d, 경계 %d의 비율로 나누다." % [founded_city_name,next.labor,next.food,next.guard]),"normal")
	_notify("%s의 도시 운영 배분을 적용했습니다." % founded_city_name,"success")
	_autosave_campaign_progress()
func _province_pick(province_id: int) -> void:
	selected_province = province_id
	if province_id not in selected_provinces:
		selected_provinces = [province_id]

	_game_map().selected_province_id = province_id
	_refresh_province()


func _selection_changed(province_ids: Array[int]) -> void:
	selected_provinces = province_ids.duplicate()
	if selected_provinces.is_empty():
		selected_province = -1
	else:
		selected_province = selected_provinces.back()
	_refresh_province()


func _active_selection() -> Array[int]:
	return read_model.active_selection(
		selected_provinces,
		selected_province
	)


func _owned_selection() -> Array[int]:
	return read_model.owned_selection(
		selected_provinces,
		selected_province,
		selected_country
	)


func _refresh_province() -> void:
	if not ui.has("province_detail"):
		return

	if selected_province == -1:
		_show_empty_province_selection()
		return

	if selected_provinces.size() > 1:
		_show_multiple_province_selection()
		return

	_show_single_province_selection()


func _show_empty_province_selection() -> void:
	ui.province_title.text = "Province를 선택하세요"
	ui.province_detail.text = (
        "[color=#96a5aa]클릭·Shift 클릭·드래그 박스로 "
		+ "여러 Province를 선택하세요.[/color]"
	)


func _show_multiple_province_selection() -> void:
	var population := 0
	var economy := 0
	var manpower := 0
	var army_total := 0
	var armies: Dictionary = gateway.snapshot().get("armies", {})

	for province_id in selected_provinces:
		var province := gateway.province(province_id)
		population += int(province.get("population", 0))
		economy += int(province.get("economy", 0))
		manpower += int(province.get("manpower", 0))
		army_total += int(armies.get(province_id, 0))

	ui.province_title.text = "%d개 Province 선택" % selected_provinces.size()
	ui.province_detail.text = (
        "[b]일괄 관리 준비됨[/b]\n\n"
		+ "총 인구  %s\n"
		+ "총 경제  %s\n"
		+ "총 인력  %s\n"
		+ "총 주둔군  %s\n\n"
		+ "개발·요새·모집은 선택한 자국 Province에 한 번에 예약됩니다."
	) % [
		_number(population),
		_number(economy),
		_number(manpower),
		_number(army_total)
	]
	ui.action_status.text = "다중 선택 · Shift로 추가/해제 · 빈 영역 드래그 선택"


func _show_single_province_selection() -> void:
	var province := gateway.province(selected_province)
	if province.is_empty():
		selected_province = -1
		_refresh_province()
		return

	var owner_id := String(province.get("owner", ""))
	var owner := gateway.country(owner_id)
	var armies: Dictionary = gateway.snapshot().get("armies", {})
	var capital_suffix := ""
	if int(owner.get("capital_province", -1)) == selected_province:
		capital_suffix = "  ★ 수도"

	ui.province_title.text = (
		String(province.get("name", "Province")) + capital_suffix
	)
	ui.province_detail.text = (
        "[color=#9eacb1]소유국[/color]  [b]%s[/b]\n"
		+ "[color=#9eacb1]점령국[/color]  %s\n\n"
		+ "인구  [b]%s[/b]     경제  [b]%s[/b]\n"
		+ "개발도  [b]%s[/b]     인력  [b]%s[/b]\n"
		+ "지형  [b]%s[/b]     요새  [b]%s[/b]\n"
		+ "불안도  [b]%s%%[/b]     주둔군  [b]%s[/b]\n\n"
		+ "예상 세입  [color=#7ec59f]+%s[/color]\n"
		+ "인접 Province  %s"
	) % [
		_country_name(owner_id),
		_country_name(String(province.get("controller", owner_id))),
		_number(int(province.get("population", 0))),
		_number(int(province.get("economy", 0))),
		str(province.get("development", 0)),
		_number(int(province.get("manpower", 0))),
		_terrain(String(province.get("terrain", "plains"))),
		str(province.get("fort", 0)),
		str(province.get("revolt_risk", 0)),
		_number(int(armies.get(selected_province, 0))),
		str(
			int(
				float(province.get("economy", 0))
				* float(owner.get("tax_rate", 0.2))
			)
		),
		_neighbor_names(province.get("neighbors", []))
	]
	ui.action_status.text = _province_action_status(owner_id)


func _province_action_status(owner_id: String) -> String:
	if owner_id == selected_country:
		return "자국 Province"
	if gateway.at_war(selected_country, owner_id):
		return "적국 · 전쟁 중"
	return "외국 · 공격 전 전쟁 선포 필요"


# Domestic and military commands --------------------------------------------

func _queue_recruit() -> void:
	var targets := _owned_selection()
	if targets.is_empty():
		_notify("모집할 자국 Province를 선택하세요.", "warning")
		return

	var queued_count := 0
	for province_id in targets:
		var command_id := gateway.queue_command(
			"recruit",
			{
				"province_id": province_id,
				"amount": 100
			},
			{
				"title": "일괄 병력 모집",
				"from": _province_name(province_id),
				"amount": 100,
				"cost": 2
			}
		)
		if command_id != -1:
			queued_count += 1

	_notify(
        "%d개 Province 모집 작업을 Task Queue에 추가했습니다."
		% queued_count,
        "success"
	)


func _simple_command(command_type: String) -> void:
	var targets := _owned_selection()
	if targets.is_empty():
		_notify("관리할 자국 Province를 선택하세요.", "warning")
		return

	var command_labels := {
		"develop": "개발 투자",
		"fortify": "요새 건설",
		"move_capital": "수도 이전",
		"occupation": "점령지 관리"
	}
	var queued_count := 0

	for province_id in targets:
		var command_id := gateway.queue_command(
			command_type,
			{"province_id": province_id},
			{
				"title": command_labels.get(command_type, command_type),
				"from": _province_name(province_id),
				"cost": 40
			}
		)
		if command_id != -1:
			queued_count += 1

	_notify(
		"%d개 작업을 Task Queue에 추가했습니다." % queued_count,
		"success" if queued_count > 0 else "warning"
	)


func _prepare_move(command_type: String = "move") -> void:
	pending_sources = _owned_selection()
	if pending_sources.is_empty():
		_notify("출발할 자국 Province를 선택하세요.", "warning")
		return

	var available: int = read_model.available_army(pending_sources)
	if available <= 0:
		_notify("이동 가능한 병력이 없습니다.", "warning")
		_cancel_mode()
		return

	pending_source = pending_sources[0]
	pending_kind = command_type
	pending_amount = available

	ui.move_amount.max_value = available
	ui.move_amount.value = available
	ui.move_summary.text = "%d개 출발지 · 총 가용 병력 %d" % [
		pending_sources.size(),
		available
	]

	_game_map().set_interaction_state(
		StrategicMap.InputState.MODAL_OPEN,
		pending_source
	)
	move_dialog.popup_centered()


func _move_fraction(fraction: float) -> void:
	var available := int(ui.move_amount.max_value)
	if fraction <= 0.0 or fraction >= 1.0:
		ui.move_amount.value = available
	else:
		ui.move_amount.value = maxi(
			1,
			int(float(available) * fraction)
		)


func _begin_target() -> void:
	pending_amount = int(ui.move_amount.value)
	move_dialog.hide()

	var target_state := StrategicMap.InputState.CHOOSING_MOVE_TARGET
	if pending_kind == "attack":
		target_state = StrategicMap.InputState.CHOOSING_ATTACK_TARGET

	_game_map().set_interaction_state(target_state, pending_source)
	ui.action_status.text = (
        "목적지 선택 중 · 우클릭 드래그 패닝 · Esc 취소"
	)
	_notify("지도에서 목적지를 선택하세요.", "info")


func _map_target(province_id: int) -> void:
	if pending_kind == "peace":
		_toggle_peace_demand(province_id)
		return
	if pending_kind.is_empty():
		return

	var sources := pending_sources.duplicate()
	if sources.is_empty():
		sources = [pending_source]

	var target := gateway.province(province_id)
	var target_owner := String(target.get("owner", ""))
	var queued_count := 0

	for source_id_value in sources:
		var source_id := int(source_id_value)
		var source := gateway.province(source_id)
		if not _has_neighbor(source, province_id):
			continue

		var command_type := pending_kind
		if target_owner != selected_country:
			command_type = "attack"
		if (
			command_type == "attack"
			and not gateway.at_war(selected_country, target_owner)
		):
			continue

		var amount := _distributed_move_amount(
			source_id,
			sources.size()
		)
		var command_id := gateway.queue_command(
			command_type,
			{
				"from_id": source_id,
				"to_id": province_id,
				"amount": amount,
				"leave_garrison": 1
			},
			{
				"title": (
                    "일괄 공격"
					if command_type == "attack"
					else "일괄 이동"
				),
				"from": _province_name(source_id),
				"to": _province_name(province_id),
				"amount": amount,
				"warning": (
                    "전투 발생 가능"
					if command_type == "attack"
					else ""
				)
			}
		)
		if command_id != -1:
			queued_count += 1

	_cancel_mode()
	_notify(
		"%d개 이동 작업을 Task Queue에 추가했습니다." % queued_count,
		"success" if queued_count > 0 else "warning"
	)


func _distributed_move_amount(source_id: int, source_count: int) -> int:
	var armies: Dictionary = gateway.snapshot().get("armies", {})
	var available := maxi(1, int(armies.get(source_id, 0)) - 1)
	var requested_share := maxi(
		1,
		int(float(pending_amount) / float(source_count))
	)
	return mini(available, requested_share)


func _quick_drag_move(from_id: int, to_id: int) -> void:
	var source := gateway.province(from_id)
	if String(source.get("owner", "")) != selected_country:
		_notify("자국 군대만 드래그할 수 있습니다.", "warning")
		return
	if not _has_neighbor(source, to_id):
		_notify("인접 Province로만 이동할 수 있습니다.", "warning")
		return

	var target_owner := String(gateway.province(to_id).get("owner", ""))
	var command_type := "move"
	if target_owner != selected_country:
		command_type = "attack"

	if (
		command_type == "attack"
		and not gateway.at_war(selected_country, target_owner)
	):
		_notify("공격 전 전쟁 상태가 필요합니다.", "warning")
		return

	var armies: Dictionary = gateway.snapshot().get("armies", {})
	var amount := maxi(1, int(armies.get(from_id, 0)) - 1)
	var command_id := gateway.queue_command(
		command_type,
		{
			"from_id": from_id,
			"to_id": to_id,
			"amount": amount,
			"leave_garrison": 1
		},
		{
			"title": "Drag & Drop 이동",
			"from": _province_name(from_id),
			"to": _province_name(to_id),
			"amount": amount
		}
	)

	if command_id != -1:
		_notify(
			"Drag & Drop 명령을 Task Queue에 추가했습니다.",
            "success"
		)


func _cancel_mode() -> void:
	move_dialog.hide()
	pending_source = -1
	pending_sources.clear()
	pending_kind = ""
	pending_amount = 0
	_game_map().clear_interaction()

	if ui.has("action_status"):
		ui.action_status.text = "명령 준비 상태가 해제되었습니다."


# Automated recommendations --------------------------------------------------

func _smart_recommend(recommendation_type: String = "economy") -> void:
	var owned_provinces := _owned(selected_country)
	if owned_provinces.is_empty():
		return

	owned_provinces.sort_custom(
		func(first_id: int, second_id: int) -> bool:
			return (
				_recommendation_score(first_id, recommendation_type)
				< _recommendation_score(second_id, recommendation_type)
			)
	)

	selected_provinces.clear()
	for province_index in range(mini(3, owned_provinces.size())):
		selected_provinces.append(owned_provinces[province_index])

	selected_province = selected_provinces.back()
	_game_map().set_selected_provinces(selected_provinces)
	_set_map_mode(recommendation_type)
	_game_map().focus_province(selected_province)
	_notify(
        "AI Assistant가 우선 관리할 %d개 Province를 선택했습니다."
		% selected_provinces.size(),
        "info"
	)


func _recommendation_score(
	province_id: int,
	recommendation_type: String
) -> float:
	if recommendation_type == "economy":
		return float(gateway.province(province_id).get("economy", 0))
	return read_model.supply_score(province_id)


func _toggle_governor() -> void:
	governor_enabled = not governor_enabled
	_notify(
        "Governor 자동 관리 %s"
		% ("활성" if governor_enabled else "비활성"),
		"success" if governor_enabled else "info"
	)


func _before_turn(_commands:Array) -> void:
	gateway.set_campaign_save_data(_campaign_save_data())
	if governor_enabled: _governor_plan()


func _governor_plan() -> void:
	var owned_provinces := _owned(selected_country)
	owned_provinces.sort_custom(
		func(first_id: int, second_id: int) -> bool:
			return (
				float(gateway.province(first_id).get("economy", 0))
				< float(gateway.province(second_id).get("economy", 0))
			)
	)
	if owned_provinces.is_empty():
		return

	var target_id := int(owned_provinces[0])
	gateway.queue_command(
		"develop",
		{"province_id": target_id},
		{
			"title": "Governor 자동 투자",
			"from": _province_name(target_id),
			"cost": 40,
			"warning": "AI 추천"
		}
	)


func _open_ai_assistant() -> void:
	var owned_provinces := _owned(selected_country)
	if owned_provinces.is_empty():
		return

	var weakest_id := int(owned_provinces[0])
	for province_id in owned_provinces:
		if (
			float(gateway.province(province_id).get("economy", 0))
			< float(gateway.province(weakest_id).get("economy", 0))
		):
			weakest_id = province_id

	var dialog := ConfirmationDialog.new()
	dialog.title = "AI Assistant · 전략 브리핑"
	dialog.dialog_text = (
        "추천 1순위: %s 개발 투자\n"
		+ "이유: 자국 내 경제 수치가 가장 낮습니다.\n\n"
		+ "[추천 적용]을 누르면 선택하고 Task Queue에 개발을 예약합니다."
	) % _province_name(weakest_id)
	dialog.ok_button_text = "추천 적용"
	dialog.confirmed.connect(
		_apply_ai_development_recommendation.bind(weakest_id, dialog)
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 300))


func _apply_ai_development_recommendation(
	province_id: int,
	dialog: ConfirmationDialog
) -> void:
	selected_provinces = [province_id]
	selected_province = province_id
	_game_map().set_selected_provinces(selected_provinces)
	_simple_command("develop")
	dialog.queue_free()


# Command queue --------------------------------------------------------------

func _rebuild_queue(commands: Array) -> void:
	if not ui.has("queue"):
		return

	for child in ui.queue.get_children():
		child.queue_free()

	var command_paths: Array = []
	if commands.is_empty():
		ui.queue.add_child(
			_label(
				"예약된 명령이 없습니다.",
				13,
				Color("#829098")
			)
		)

	for command_value in commands:
		if command_value is not Dictionary:
			continue
		var command: Dictionary = command_value
		ui.queue.add_child(_build_queue_row(command))

		var payload: Dictionary = command.get("payload", {})
		if payload.has("from_id") and payload.has("to_id"):
			command_paths.append({
				"from_id": payload.get("from_id", -1),
				"to_id": payload.get("to_id", -1),
				"type": command.get("type", "move")
			})

	_game_map().set_command_paths(command_paths)


func _build_queue_row(command: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var presentation: Dictionary = command.get("presentation", {})
	var text := "#%d  %s  %s" % [
		int(command.get("id", 0)),
		_command_icon(String(command.get("type", ""))),
		String(
			presentation.get(
				"title",
				command.get("type", "명령")
			)
		)
	]

	if not String(presentation.get("from", "")).is_empty():
		text += " · " + String(presentation.get("from", ""))
	if not String(presentation.get("to", "")).is_empty():
		text += " → " + String(presentation.get("to", ""))
	if presentation.has("amount"):
		text += " · 병력 %s" % str(presentation.get("amount", 0))

	var label := _label(text, 13, Color("#d9d4c5"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var warning := String(presentation.get("warning", ""))
	if not warning.is_empty():
		row.add_child(
			_label("⚠ " + warning, 11, Color("#d9986f"))
		)

	row.add_child(
		_button(
			"수정",
			func(): _notify(
				"수정 API 준비됨 · 취소 후 다시 입력하세요.",
                "info"
			),
            "small"
		)
	)
	row.add_child(
		_button(
			"취소",
			_cancel_queued.bind(int(command.get("id", 0))),
            "small"
		)
	)
	return row


func _cancel_queued(command_id: int) -> void:
	if gateway.cancel_command(command_id):
		_notify("명령 #%d을 취소했습니다." % command_id, "success")


# Diplomacy ------------------------------------------------------------------

func _open_diplomacy() -> void:
	var target_country_id := _foreign_country()
	if target_country_id.is_empty():
		target_country_id = _first_foreign_country()
	if target_country_id.is_empty():
		return

	for child in ui.diplomacy_box.get_children():
		child.queue_free()

	var relation_value := gateway.relation(
		selected_country,
		target_country_id
	)
	var at_war := gateway.at_war(selected_country, target_country_id)

	ui.diplomacy_box.add_child(
		_label(
			"%s ↔ %s" % [
				_country_name(selected_country),
				_country_name(target_country_id)
			],
			25,
			Color("#dec77f")
		)
	)
	ui.diplomacy_box.add_child(
		_label(
			_diplomacy_summary(
				target_country_id,
				relation_value,
				at_war
			),
			14,
			Color("#b9c2c2")
		)
	)

	var grid := GridContainer.new()
	grid.columns = 2
	ui.diplomacy_box.add_child(grid)
	_add_diplomacy_actions(
		grid,
		target_country_id,
		relation_value
	)
	diplomacy_dialog.popup_centered()


func _first_foreign_country() -> String:
	for country_id_value in gateway.countries().keys():
		var country_id := String(country_id_value)
		if country_id != selected_country:
			return country_id
	return ""


func _diplomacy_summary(
	target_country_id: String,
	relation_value: int,
	at_war: bool
) -> String:
	var relation_name := "중립"
	if at_war:
		relation_name = "전쟁"
	elif relation_value >= 20:
		relation_name = "우호"
	elif relation_value <= -20:
		relation_name = "긴장"

	return (
        "관계도 %d · %s\n"
		+ "현재 전쟁 %s · 동맹 없음 · 불가침 없음 · 휴전 없음\n"
		+ "국력 비교  아군 %s : 상대 %s\n"
		+ "국경 Province  %s"
	) % [
		relation_value,
		relation_name,
		"진행 중" if at_war else "없음",
		_number(_army_total(selected_country)),
		_number(_army_total(target_country_id)),
		_border_names(selected_country, target_country_id)
	]


func _add_diplomacy_actions(
	grid: GridContainer,
	target_country_id: String,
	relation_value: int
) -> void:
	var actions := [
		["관계 개선", "improve_relations", 25],
		["모욕", "insult", 0],
		["전쟁 선포", "declare_war", 50],
		["평화 제안", "offer_peace", 20],
		["동맹 제안", "offer_alliance", 35],
		["불가침 제안", "offer_non_aggression", 20],
		["군사 통행 요청", "request_access", 15],
		["속국화 요구", "demand_vassalization", 80],
		["독립 요구", "demand_independence", 60]
	]

	for action in actions:
		var action_name := String(action[0])
		var command_type := String(action[1])
		var cost := int(action[2])
		var acceptance := clampi(
			50 + relation_value - cost / 2,
			0,
			100
		)
		grid.add_child(
			_button(
				"%s\n비용 %d · 수락 예상 %d%%" % [
					action_name,
					cost,
					acceptance
				],
				_queue_diplomacy.bind(
					command_type,
					target_country_id,
					cost,
					acceptance
				),
				"danger" if command_type == "declare_war" else "list",
				58
			)
		)


func _queue_diplomacy(
	command_type: String,
	target_country_id: String,
	cost: int,
	acceptance: int
) -> void:
	if command_type == "offer_peace":
		diplomacy_dialog.hide()
		_open_peace()
		return

	var command_id := gateway.queue_command(
		command_type,
		{"target_country_id": target_country_id},
		{
			"title": _diplomacy_name(command_type),
			"to": _country_name(target_country_id),
			"cost": cost,
			"warning": "수락 예상 %d%%" % acceptance
		}
	)
	if command_id == -1:
		return

	diplomacy_dialog.hide()
	_add_log(
		"외교",
		"명령 #%d · %s → %s" % [
			command_id,
			_diplomacy_name(command_type),
			_country_name(target_country_id)
		],
        "important"
	)
	_notify("외교 명령을 예약했습니다.", "success")


# Peace negotiation ----------------------------------------------------------

func _open_peace() -> void:
	var target_country_id := _foreign_country()
	if target_country_id.is_empty():
		_notify("협상 상대 Province를 먼저 선택하세요.", "warning")
		return

	for child in ui.peace_box.get_children():
		child.queue_free()

	ui.peace_box.add_child(
		_label(
			"%s 평화 협상" % _country_name(target_country_id),
			24,
			Color("#dec77f")
		)
	)
	ui.peace_box.add_child(
		_label(
            "전쟁 점수 0 · 점령 Province 0\n"
			+ "지도에서 요구할 Province를 직접 선택할 수 있습니다.",
			14,
			Color("#b9c2c2")
		)
	)

	var reparations := SpinBox.new()
	reparations.name = "Reparations"
	reparations.min_value = 0
	reparations.max_value = 1000
	reparations.step = 25
	reparations.suffix = " 배상금"
	ui.peace_box.add_child(reparations)

	var vassalize := CheckBox.new()
	vassalize.name = "Vassalize"
	vassalize.text = "속국화 요구"
	ui.peace_box.add_child(vassalize)

	var independence := CheckBox.new()
	independence.name = "Independence"
	independence.text = "독립 승인"
	ui.peace_box.add_child(independence)

	ui.peace_box.add_child(
		_label(
			"제안 전송 시 코어가 전쟁 점수와 협상 비용을 검증합니다.",
			12,
			Color("#d09b70")
		)
	)

	var row := HBoxContainer.new()
	row.add_child(_button("제안 초기화", _reset_peace))
	row.add_child(_button("지도에서 Province 요구", _begin_peace))
	row.add_child(
		_button(
			"제안 전송",
			_submit_peace.bind(target_country_id),
            "primary"
		)
	)
	ui.peace_box.add_child(row)
	peace_dialog.popup_centered()


func _begin_peace() -> void:
	peace_dialog.hide()
	pending_kind = "peace"
	_game_map().set_interaction_state(
		StrategicMap.InputState.SELECTING_PEACE_TERMS
	)
	_notify(
		"지도에서 요구할 Province를 선택한 뒤 평화 창을 다시 여세요.",
        "info"
	)


func _toggle_peace_demand(province_id: int) -> void:
	if province_id in peace_demands:
		peace_demands.erase(province_id)
	else:
		peace_demands.append(province_id)
	_game_map().set_peace_demands(peace_demands)


func _reset_peace() -> void:
	peace_demands.clear()
	_game_map().set_peace_demands(peace_demands)
	_notify("평화 제안을 초기화했습니다.", "info")


func _submit_peace(target_country_id: String) -> void:
	var reparations := (
		ui.peace_box.get_node_or_null("Reparations") as SpinBox
	)
	var vassalize := (
		ui.peace_box.get_node_or_null("Vassalize") as CheckBox
	)
	var independence := (
		ui.peace_box.get_node_or_null("Independence") as CheckBox
	)

	var payload := {
		"target_country_id": target_country_id,
		"province_demands": peace_demands.duplicate(),
		"reparations": int(reparations.value if reparations else 0),
		"vassalize": vassalize.button_pressed if vassalize else false,
		"recognize_independence": (
			independence.button_pressed if independence else false
		)
	}
	var command_id := gateway.queue_command(
		"peace_offer",
		payload,
		{
			"title": "평화 제안",
			"to": _country_name(target_country_id),
			"cost": (
				peace_demands.size() * 20
				+ int(payload.get("reparations", 0)) / 25
			),
			"warning": "코어 검증 완료"
		}
	)
	if command_id == -1:
		return

	_close_peace()
	_notify("평화 제안을 명령 큐에 추가했습니다.", "success")


func _close_peace() -> void:
	peace_dialog.hide()
	if pending_kind == "peace":
		pending_kind = ""
	_game_map().clear_interaction()


# Map mode, search, and tooltip ----------------------------------------------

func _set_map_mode(mode: String) -> void:
	_game_map().set_mode(mode)
	map_mode_index = _map_mode_index(mode)
	ui.mode_title.text = "%s 지도" % _game_map().mode_label()
	_legend()
	_notify("%s 지도 모드" % _game_map().mode_label(), "info")


func _map_mode_index(mode: String) -> int:
	for index in range(MAP_MODES.size()):
		if String(MAP_MODES[index][0]) == mode:
			return index
	return map_mode_index


func _legend() -> void:
	if not ui.has("legend") or not maps.has(ScreenState.GAME):
		return

	var mode := _game_map().map_mode
	if mode == "political":
		ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
			+ "■ 국가색  ▣ 선택\n"
			+ "청록 국경: 자국\n"
			+ "적색 국경: 적국"
		)
	elif mode in ["relations", "war"]:
		ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
			+ "■ 자국  ■ 동맹/우호\n"
			+ "■ 적국/전쟁  ■ 중립"
		)
	elif mode == "terrain":
		ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
			+ "■ 평원  ■ 구릉\n"
			+ "■ 숲  ■ 해안"
		)
	else:
		ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
			+ "낮음  ░▒▓█  높음\n"
			+ "8–92 분위수 정규화"
		)


func _map_tooltip(text: String, position: Vector2) -> void:
	if text.is_empty():
		ui.tooltip.hide()
		return

	ui.tooltip_label.text = text
	ui.tooltip.position = position + Vector2(14, 14)
	ui.tooltip.show()
	ui.tooltip.position = ui.tooltip.position.clamp(
		Vector2(8, 8),
		get_viewport_rect().size - ui.tooltip.size - Vector2(8, 8)
	)


func _search_province(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	for province_id_value in gateway.snapshot().get("provinces", {}).keys():
		var province_id := int(province_id_value)
		if needle in _province_name(province_id).to_lower():
			selected_province = province_id
			_game_map().selected_province_id = province_id
			_game_map().focus_province(province_id)
			_refresh_province()
			return
	_notify("일치하는 Province가 없습니다.", "warning")


# War and event presentation -------------------------------------------------

func _refresh_wars() -> void:
	if not ui.has("wars"):
		return

	var wars: Array = gateway.snapshot().get("wars", [])
	if wars.is_empty():
		ui.wars.text = (
            "[color=#85949a]진행 중인 전쟁이 없습니다.[/color]"
		)
		return

	var text := "[font_size=18][color=#dec77f]전쟁 현황[/color][/font_size]\n"
	for war_value in wars:
		if war_value is not Dictionary:
			continue
		var war: Dictionary = war_value
		text += "\n%s ⚔ %s · 전쟁 점수 %s" % [
			_country_name(String(war.get("attacker", ""))),
			_country_name(String(war.get("defender", ""))),
			str(war.get("war_score", war.get("score", 0)))
		]
	ui.wars.text = text


func _add_log(
	category: String,
	message: String,
	importance: String = "normal"
) -> void:
	logs.append({
		"category": category,
		"message": message,
		"importance": importance,
		"time": Time.get_time_string_from_system()
	})
	if logs.size() > LOG_LIMIT:
		logs.pop_front()

	if ui.has("alert_button"):
		ui.alert_button.text = "알림 %d" % logs.size()
	_refresh_logs("전체")


func _filter_logs(category: String) -> void:
	_refresh_logs(category)


func _refresh_logs(filter: String) -> void:
	if not ui.has("log"):
		return

	var text := ""
	for entry in logs:
		if not _log_matches_filter(entry, filter):
			continue

		var color := _log_color(entry)
		text += (
            "[color=#748087]%s[/color] "
			+ "[color=%s][%s][/color] %s\n"
		) % [
			entry.get("time", ""),
			color,
			entry.get("category", ""),
			entry.get("message", "")
		]

	ui.log.text = text
	ui.log.scroll_to_line(maxi(0, ui.log.get_line_count() - 1))


func _log_matches_filter(entry: Dictionary, filter: String) -> bool:
	if filter == "전체":
		return true
	if String(entry.get("category", "")) == filter:
		return true
	return (
		filter == "중요"
		and String(entry.get("importance", "")) == "important"
	)


func _log_color(entry: Dictionary) -> String:
	if String(entry.get("importance", "")) == "important":
		return "#e1b56d"

	match String(entry.get("category", "")):
		"전쟁":
			return "#e18070"
		"외교":
			return "#78b7c5"
		"경제":
			return "#83bd8d"
	return "#d4cfc0"


func _notify(message: String, kind: String = "info") -> void:
	ui.toast_label.text = message
	var border := "#d0ad64"

	match kind:
		"success":
			border = "#6fb292"
		"warning":
			border = "#d38d62"
		"error":
			border = "#c85c5c"

	toast.add_theme_stylebox_override(
		"panel",
		_style("#22313a", border, 1, 8)
	)
	toast.show()
	toast_timer.start(3.2)
	_on_resize()


# Settings and layout --------------------------------------------------------

func _settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "설정"
	dialog.dialog_text = (
        "UI 배율·접근성 설정은 저장 API 연결 후 영구 보관됩니다.\n"
		+ "현재 화면은 Container와 anchor로 반응형 배치됩니다."
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 220))


func _on_resize() -> void:
	var viewport_size:=get_viewport_rect().size
	if toast: toast.position=Vector2(viewport_size.x*0.5-toast.custom_minimum_size.x*0.5,18)
	if ui.has("country_left"):
		ui.country_left.custom_minimum_size.x=clampf(viewport_size.x*0.16,170.0,230.0)
		ui.country_dossier.custom_minimum_size.x=clampf(viewport_size.x*0.22,238.0,330.0)
		ui.country_portrait.custom_minimum_size.y=clampf(viewport_size.y*0.27,145.0,300.0)
		ui.ruler_fallback.custom_minimum_size.y=ui.country_portrait.custom_minimum_size.y
		ui.country_detail.custom_minimum_size.y=clampf(viewport_size.y*0.10,54.0,108.0)
	if ui.has("first_decree_panel"):
		ui.first_decree_panel.custom_minimum_size=Vector2(clampf(viewport_size.x*0.62,560.0,760.0),clampf(viewport_size.y*0.68,390.0,560.0))


func _frame_map(strategy_map: StrategicMap) -> void:
	if strategy_map != null:
		strategy_map.frame_world()


func _bottom_tab(index: int) -> void:
	ui.bottom_tabs.current_tab = clampi(
		index,
		0,
		ui.bottom_tabs.get_tab_count() - 1
	)


func _game_map() -> StrategicMap:
	return maps.get(ScreenState.GAME) as StrategicMap


# Compatibility and semantic helper adapters --------------------------------

func _owned_selected() -> bool:
	if selected_province == -1:
		_notify("먼저 Province를 선택하세요.", "warning")
		return false
	if (
		String(gateway.province(selected_province).get("owner", ""))
		!= selected_country
	):
		_notify("자국 Province에서만 실행할 수 있습니다.", "warning")
		return false
	return true


func _foreign_country() -> String:
	return read_model.foreign_country(
		selected_province,
		selected_country
	)


func _margin(amount: int) -> MarginContainer:
	return ProjectEpochUiFactoryScript.margin_container(amount)


func _header(
	title: String,
	subtitle: String,
	back_action: Callable
) -> Control:
	return ProjectEpochUiFactoryScript.header(
		title,
		subtitle,
		back_action
	)


func _section(title: String, minimum_width: int = 0) -> VBoxContainer:
	return ProjectEpochUiFactoryScript.section(title, minimum_width)


func _window_box(window: Window) -> VBoxContainer:
	return ProjectEpochUiFactoryScript.window_box(window)


func _label(
	text: String,
	font_size: int = 14,
	color: Color = Color.WHITE,
	alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	return ProjectEpochUiFactoryScript.label(
		text,
		font_size,
		color,
		alignment
	)


func _button(
	text: String,
	action: Callable,
	variant: String = "default",
	minimum_height: int = 40
) -> Button:
	return ProjectEpochUiFactoryScript.button(
		text,
		action,
		variant,
		minimum_height
	)


func _stat(caption: String, value: String) -> Label:
	return ProjectEpochUiFactoryScript.stat(caption, value)


func _style(
	background: String,
	border: String,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	return ProjectEpochUiFactoryScript.style(
		background,
		border,
		border_width,
		corner_radius
	)


func _number(value: int) -> String:
	return read_model.number(value)


func _country_name(country_id: String) -> String:
	return read_model.country_name(country_id)


func _province_name(province_id: int) -> String:
	return read_model.province_name(province_id)


func _terrain(terrain_id: String) -> String:
	return read_model.terrain_name(terrain_id)


func _difficulty(country: Dictionary) -> String:
	return read_model.difficulty(country)


func _owned(country_id: String) -> Array[int]:
	return read_model.owned_provinces(country_id)


func _country_total(country_id: String, field_name: String) -> int:
	return read_model.country_total(country_id, field_name)


func _army_total(country_id: String) -> int:
	return read_model.army_total(country_id)


func _income(country_id: String) -> int:
	return read_model.income(country_id)


func _has_neighbor(province: Dictionary, target_id: int) -> bool:
	return read_model.has_neighbor(province, target_id)


func _neighbor_names(neighbor_ids: Array) -> String:
	return read_model.neighbor_names(neighbor_ids)


func _border_names(
	first_country_id: String,
	second_country_id: String
) -> String:
	return read_model.border_names(
		first_country_id,
		second_country_id
	)


func _command_icon(command_type: String) -> String:
	return read_model.command_icon(command_type)


func _diplomacy_name(command_type: String) -> String:
	return read_model.diplomacy_name(command_type)
