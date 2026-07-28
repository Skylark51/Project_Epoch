extends Control

enum ScreenState { START, SCENARIO, COUNTRY, GAME }
const MAP_MODES := [["political","정치"],["relations","외교"],["war","전쟁"],["economy","경제"],["population","인구"],["development","개발"],["manpower","인력"],["stability","안정"],["revolt","반란"],["terrain","지형"],["fort","요새"]]
const LOG_LIMIT := 120

var gateway := StrategyGateway.new()
var state := ScreenState.START
var selected_country := "AUR"
var selected_province := -1
var pending_source := -1
var pending_kind := ""
var pending_amount := 0
var peace_demands: Array[int] = []
var logs: Array[Dictionary] = []
var screens: Dictionary = {}
var maps: Dictionary = {}
var ui: Dictionary = {}
var move_dialog: Window
var diplomacy_dialog: Window
var peace_dialog: Window
var toast: PanelContainer
var toast_timer: Timer

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var epoch_theme = load("res://themes/project_epoch_theme.tres")
    if epoch_theme is Theme: theme = epoch_theme
    _build_screens()
    gateway.snapshot_changed.connect(_sync_snapshot)
    gateway.command_queue_changed.connect(_rebuild_queue)
    gateway.integration_notice.connect(func(message): _notify(message,"info"); _add_log("일반",message,"normal"))
    gateway.turn_requested.connect(func(commands): _add_log("중요","코어 턴 처리 요청 · %d개 명령" % commands.size(),"important"))
    if gateway.load_local_catalog():
        selected_country = String(gateway.snapshot().get("player_country_id","AUR"))
        _sync_snapshot(gateway.snapshot())
    else: _notify("기본 JSON 데이터를 불러오지 못했습니다.","error")
    _show(ScreenState.START)
    get_viewport().size_changed.connect(_on_resize)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event.pressed or event.echo or state != ScreenState.GAME: return
    var focused := get_viewport().gui_get_focus_owner()
    if focused is LineEdit or focused is SpinBox: return
    match event.keycode:
        KEY_ESCAPE:
            if pending_kind != "": _cancel_mode()
            else: _show(ScreenState.START)
        KEY_SPACE: gateway.submit_turn()
        KEY_M: _prepare_move("move")
        KEY_A: _prepare_move("attack")
        KEY_R: _queue_recruit()
        KEY_F: if selected_province != -1: _game_map().focus_province(selected_province)
        KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6:
            var index := int(event.keycode-KEY_1)
            if index < MAP_MODES.size(): _set_map_mode(String(MAP_MODES[index][0]))

func _build_screens() -> void:
    var background := ColorRect.new(); background.color=Color("#10161d"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
    for entry in [[ScreenState.START,_build_start()],[ScreenState.SCENARIO,_build_scenario()],[ScreenState.COUNTRY,_build_country()],[ScreenState.GAME,_build_game()]]:
        screens[entry[0]]=entry[1]; add_child(entry[1])
    _build_dialogs()

func _build_start() -> Control:
    var root:=_margin(48); var center:=CenterContainer.new(); root.add_child(center)
    var panel:=PanelContainer.new(); panel.custom_minimum_size=Vector2(520,560); panel.add_theme_stylebox_override("panel",_style("#17212a","#8f7448",2,18)); center.add_child(panel)
    var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",18); panel.add_child(box)
    box.add_child(_label("◆  PROJECT EPOCH  ◆",34,Color("#d7bb79"),HORIZONTAL_ALIGNMENT_CENTER))
    box.add_child(_label("역사의 주도권은 지도 위에서 시작됩니다",16,Color("#aeb9bd"),HORIZONTAL_ALIGNMENT_CENTER)); box.add_child(HSeparator.new())
    box.add_child(_button("새 게임",func():_show(ScreenState.SCENARIO),"primary",58))
    box.add_child(_button("불러오기",func():_notify("저장 API 연결 대기 중입니다.","info")))
    box.add_child(_button("설정",_settings)); box.add_child(_button("종료",func():get_tree().quit()))
    box.add_child(_label("Province 중심 대전략 · 데스크톱 고밀도 인터페이스",12,Color("#74828a"),HORIZONTAL_ALIGNMENT_CENTER))
    return root

func _build_scenario() -> Control:
    var root:=_margin(18); var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",12); root.add_child(outer)
    outer.add_child(_header("시나리오 선택","시대와 지역을 고른 뒤 지도를 확인하세요",func():_show(ScreenState.START)))
    var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.split_offset=270; outer.add_child(split)
    var left:=_section("시대 · 지역 · 시나리오",250); split.add_child(left)
    var era:=OptionButton.new(); era.add_item("중세 · 1000년"); era.add_item("근세 · 준비 중"); left.add_child(era)
    var region:=OptionButton.new(); region.add_item("프로토타입 대륙"); left.add_child(region)
    left.add_child(_button("삼국의 균형\n1000. 1. 1.",_refresh_scenario,"list",72))
    var middle:=_section("지도 미리보기"); middle.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(middle)
    var map:=StrategicMap.new(); map.size_flags_vertical=Control.SIZE_EXPAND_FILL; maps[ScreenState.SCENARIO]=map; middle.add_child(map)
    var right:=_section("시나리오 정보",310); split.add_child(right)
    var detail:=RichTextLabel.new(); detail.bbcode_enabled=true; detail.size_flags_vertical=Control.SIZE_EXPAND_FILL; ui.scenario_detail=detail; right.add_child(detail)
    var footer:=HBoxContainer.new(); footer.add_spacer(true); footer.add_child(_button("이전",func():_show(ScreenState.START))); footer.add_child(_button("국가 선택",func():_show(ScreenState.COUNTRY),"primary")); outer.add_child(footer)
    return root

func _build_country() -> Control:
    var root:=_margin(18); var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",12); root.add_child(outer)
    outer.add_child(_header("국가 선택","지도 또는 검색 결과에서 국가를 선택하세요",func():_show(ScreenState.SCENARIO)))
    var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.split_offset=300; outer.add_child(split)
    var left:=_section("국가 검색",285); split.add_child(left)
    var search:=LineEdit.new(); search.placeholder_text="국가명 · 정부 형태 검색"; search.text_changed.connect(_rebuild_countries); left.add_child(search)
    var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; left.add_child(scroll)
    var list:=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; ui.country_list=list; scroll.add_child(list)
    var middle:=_section("지도에서 국가 선택"); middle.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(middle)
    var map:=StrategicMap.new(); map.size_flags_vertical=Control.SIZE_EXPAND_FILL; map.province_selected.connect(_country_map_pick); maps[ScreenState.COUNTRY]=map; middle.add_child(map)
    var right:=_section("국가 개요",330); split.add_child(right)
    var detail:=RichTextLabel.new(); detail.bbcode_enabled=true; detail.size_flags_vertical=Control.SIZE_EXPAND_FILL; ui.country_detail=detail; right.add_child(detail)
    var spectate:=CheckBox.new(); spectate.text="관전 모드"; right.add_child(spectate); right.add_child(_button("플레이 시작",_start_game,"primary"))
    return root

func _build_game() -> Control:
    var root:=_margin(8); var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",6); root.add_child(outer)
    outer.add_child(_top_bar())
    var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.split_offset=244; outer.add_child(split)
    split.add_child(_left_panel())
    var center_right:=HSplitContainer.new(); center_right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center_right.split_offset=760; split.add_child(center_right)
    var center:=VBoxContainer.new(); center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; center.add_theme_constant_override("separation",6); center_right.add_child(center)
    var map_panel:=PanelContainer.new(); map_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL; map_panel.add_theme_stylebox_override("panel",_style("#0d151c","#46535a",1,8)); center.add_child(map_panel)
    var map:=StrategicMap.new(); maps[ScreenState.GAME]=map; map.province_selected.connect(_province_pick); map.command_target_selected.connect(_map_target); map.tooltip_changed.connect(_map_tooltip); map_panel.add_child(map)
    center.add_child(_bottom_panel()); center_right.add_child(_right_panel())
    return root

func _top_bar() -> Control:
    var panel:=PanelContainer.new(); panel.custom_minimum_size.y=62; panel.add_theme_stylebox_override("panel",_style("#18232c","#8d764b",1,8))
    var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",10); panel.add_child(row)
    row.add_child(_button("☰",func():_show(ScreenState.START))); var title:=_label("PROJECT EPOCH",18,Color("#d8bd7a")); title.custom_minimum_size.x=160; row.add_child(title)
    for item in [["날짜","date","1000. 1. 1"],["국고","treasury","0"],["수입","income","+0"],["인력","manpower","0"],["안정도","stability","0"],["전쟁 피로","exhaustion","0%"]]:
        var value:=_stat(item[0],item[2]); ui[item[1]]=value; row.add_child(value.get_parent())
    row.add_spacer(true); row.add_child(_button("알림 0",func():_bottom_tab(1))); row.add_child(_button("턴 실행  Space",gateway.submit_turn,"primary"))
    return panel

func _left_panel() -> Control:
    var tabs:=TabContainer.new(); tabs.custom_minimum_size.x=230; tabs.mouse_filter=Control.MOUSE_FILTER_STOP
    var map_box:=_section("지도 모드"); map_box.name="지도"
    var search:=LineEdit.new(); search.placeholder_text="Province 검색"; search.text_submitted.connect(_search_province); map_box.add_child(search)
    var grid:=GridContainer.new(); grid.columns=2; map_box.add_child(grid)
    for mode in MAP_MODES: grid.add_child(_button(String(mode[1]),_set_map_mode.bind(String(mode[0])),"small"))
    ui.mode_title=_label("정치 지도",15,Color("#d7ba76")); map_box.add_child(ui.mode_title)
    var legend:=RichTextLabel.new(); legend.bbcode_enabled=true; legend.fit_content=true; ui.legend=legend; map_box.add_child(legend); tabs.add_child(map_box)
    var nation:=_section("국가 개요"); nation.name="국가"; nation.add_child(_label("국가 자원과 외교 상태를 빠르게 확인합니다.",13,Color("#aab5b9"))); nation.add_child(_button("외교 화면",_open_diplomacy)); nation.add_child(_button("전쟁 · 평화",_open_peace)); tabs.add_child(nation)
    var alerts:=_section("중요 알림"); alerts.name="알림"; alerts.add_child(_label("전쟁, 반란, 외교 제안을 중요도 순으로 표시합니다.",13,Color("#aab5b9"))); tabs.add_child(alerts)
    return tabs

func _right_panel() -> Control:
    var tabs:=TabContainer.new(); tabs.custom_minimum_size.x=330; tabs.mouse_filter=Control.MOUSE_FILTER_STOP
    var province:=_section("Province 정보"); province.name="Province"
    ui.province_title=_label("Province를 선택하세요",21,Color("#e4cf97")); province.add_child(ui.province_title)
    var detail:=RichTextLabel.new(); detail.bbcode_enabled=true; detail.size_flags_vertical=Control.SIZE_EXPAND_FILL; ui.province_detail=detail; province.add_child(detail)
    ui.action_status=_label("지도에서 Province를 선택하세요.",12,Color("#91a0a6")); ui.action_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; province.add_child(ui.action_status)
    var actions:=GridContainer.new(); actions.columns=2; province.add_child(actions)
    for item in [["병력 모집  R",_queue_recruit,"primary"],["군대 이동  M",_prepare_move.bind("move"),"default"],["공격  A",_prepare_move.bind("attack"),"danger"],["개발 투자",_simple_command.bind("develop"),"default"],["요새 건설",_simple_command.bind("fortify"),"default"],["수도 이전",_simple_command.bind("move_capital"),"default"],["점령지 관리",_simple_command.bind("occupation"),"default"],["외교",_open_diplomacy,"default"]]: actions.add_child(_button(item[0],item[1],item[2]))
    tabs.add_child(province)
    var army:=_section("군대"); army.name="군대"; army.add_child(_label("출발지 → 병력 수 → 목적지\n명령은 턴 실행 전까지 취소할 수 있습니다.",13,Color("#aab5b9"))); tabs.add_child(army)
    var diplomacy:=_section("외교"); diplomacy.name="외교"; diplomacy.add_child(_button("선택 국가 외교",_open_diplomacy,"primary")); diplomacy.add_child(_button("평화 협상",_open_peace)); tabs.add_child(diplomacy)
    return tabs

func _bottom_panel() -> Control:
    var tabs:=TabContainer.new(); tabs.name="BottomTabs"; tabs.custom_minimum_size.y=188; tabs.mouse_filter=Control.MOUSE_FILTER_STOP; ui.bottom_tabs=tabs
    var scroll:=ScrollContainer.new(); scroll.name="명령 큐"; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
    var queue:=VBoxContainer.new(); queue.size_flags_horizontal=Control.SIZE_EXPAND_FILL; ui.queue=queue; scroll.add_child(queue); tabs.add_child(scroll)
    var log_box:=VBoxContainer.new(); log_box.name="이벤트 로그"; var filters:=HBoxContainer.new(); log_box.add_child(filters)
    for category in ["전체","전쟁","외교","경제","반란","중요"]: filters.add_child(_button(category,_filter_logs.bind(category),"small"))
    var log:=RichTextLabel.new(); log.bbcode_enabled=true; log.size_flags_vertical=Control.SIZE_EXPAND_FILL; ui.log=log; log_box.add_child(log); tabs.add_child(log_box)
    var wars:=RichTextLabel.new(); wars.name="전쟁 현황"; wars.bbcode_enabled=true; ui.wars=wars; tabs.add_child(wars)
    return tabs
func _build_dialogs() -> void:
    var tip:=PanelContainer.new(); tip.visible=false; tip.mouse_filter=Control.MOUSE_FILTER_IGNORE; tip.z_index=90; tip.add_theme_stylebox_override("panel",_style("#101820","#b59b63",1,7)); ui.tooltip=tip; add_child(tip)
    var tip_label:=Label.new(); tip_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; tip_label.custom_minimum_size=Vector2(210,0); ui.tooltip_label=tip_label; tip.add_child(tip_label)
    toast=PanelContainer.new(); toast.visible=false; toast.z_index=100; toast.custom_minimum_size=Vector2(440,52); add_child(toast)
    var toast_label:=Label.new(); toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; toast_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; ui.toast_label=toast_label; toast.add_child(toast_label)
    toast_timer=Timer.new(); toast_timer.one_shot=true; toast_timer.timeout.connect(func():toast.hide()); add_child(toast_timer)
    move_dialog=Window.new(); move_dialog.visible=false; move_dialog.exclusive=true; move_dialog.title="군대 명령"; move_dialog.size=Vector2i(440,300); move_dialog.close_requested.connect(_cancel_mode); add_child(move_dialog)
    var move_box:=_window_box(move_dialog); ui.move_summary=_label("출발 Province",16,Color("#dfc889")); move_box.add_child(ui.move_summary)
    var amount:=SpinBox.new(); amount.min_value=1; amount.max_value=999999; amount.value_changed.connect(func(value):pending_amount=int(value)); ui.move_amount=amount; move_box.add_child(amount)
    var presets:=HBoxContainer.new(); move_box.add_child(presets); presets.add_child(_button("전 병력",_move_fraction.bind(1.0),"small")); presets.add_child(_button("절반",_move_fraction.bind(0.5),"small")); presets.add_child(_button("주둔군 1 남기기",_move_fraction.bind(0.0),"small"))
    move_box.add_child(_label("적국 목적지는 공격으로 표시됩니다. 전쟁 상태를 먼저 확인합니다.",12,Color("#c99572")))
    var move_buttons:=HBoxContainer.new(); move_buttons.add_spacer(true); move_buttons.add_child(_button("취소",_cancel_mode)); move_buttons.add_child(_button("목적지 선택",_begin_target,"primary")); move_box.add_child(move_buttons)
    diplomacy_dialog=Window.new(); diplomacy_dialog.visible=false; diplomacy_dialog.exclusive=true; diplomacy_dialog.title="외교"; diplomacy_dialog.size=Vector2i(720,620); diplomacy_dialog.close_requested.connect(func():diplomacy_dialog.hide()); add_child(diplomacy_dialog)
    var diplomacy_scroll:=ScrollContainer.new(); diplomacy_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); diplomacy_dialog.add_child(diplomacy_scroll)
    var diplomacy_box:=VBoxContainer.new(); diplomacy_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; diplomacy_box.add_theme_constant_override("separation",10); ui.diplomacy_box=diplomacy_box; diplomacy_scroll.add_child(diplomacy_box)
    peace_dialog=Window.new(); peace_dialog.visible=false; peace_dialog.exclusive=true; peace_dialog.title="평화 협상"; peace_dialog.size=Vector2i(760,650); peace_dialog.close_requested.connect(_close_peace); add_child(peace_dialog)
    var peace_scroll:=ScrollContainer.new(); peace_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); peace_dialog.add_child(peace_scroll)
    var peace_box:=VBoxContainer.new(); peace_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; peace_box.add_theme_constant_override("separation",10); ui.peace_box=peace_box; peace_scroll.add_child(peace_box)

func _show(next: ScreenState) -> void:
    state=next
    for key in screens: screens[key].visible=key==next
    if ui.has("tooltip"): ui.tooltip.hide()
    if next==ScreenState.SCENARIO: _refresh_scenario(); call_deferred("_frame_map",maps.get(next))
    elif next==ScreenState.COUNTRY: _rebuild_countries(""); _refresh_country(); call_deferred("_frame_map",maps.get(next))
    elif next==ScreenState.GAME: _sync_snapshot(gateway.snapshot()); call_deferred("_frame_map",maps.get(next))

func _sync_snapshot(snapshot: Dictionary) -> void:
    for map in maps.values(): map.set_snapshot(snapshot)
    selected_country=String(snapshot.get("player_country_id",selected_country))
    var country:=gateway.country(selected_country); var date:Dictionary=snapshot.get("date",{})
    if ui.has("date"): ui.date.text="%d. %d. %d" % [int(date.get("year",1000)),int(date.get("month",1)),int(date.get("day",1))]
    if ui.has("treasury"): ui.treasury.text=_number(int(country.get("treasury",0)))
    if ui.has("income"): ui.income.text="+%s" % _number(_income(selected_country))
    if ui.has("manpower"): ui.manpower.text=_number(int(country.get("manpower",0)))
    if ui.has("stability"): ui.stability.text=str(country.get("stability",0))
    if ui.has("exhaustion"): ui.exhaustion.text="%d%%" % int(country.get("war_exhaustion",0))
    _refresh_province(); _refresh_wars(); _legend()

func _refresh_scenario() -> void:
    if not ui.has("scenario_detail"): return
    var scenario:Dictionary=gateway.scenarios()[0] if not gateway.scenarios().is_empty() else {}
    ui.scenario_detail.text="[font_size=22][color=#ddc47e]%s[/color][/font_size]\n\n시작 연도  [b]%s[/b]\n국가 수  [b]%d[/b]\n턴 방식  [b]동시 명령[/b]\n\n%s\n\n[color=#9fb0b5]추천 국가[/color]\n• 아우렐리아 · 균형형\n• 보레알 왕국 · 군사형\n• 세레네 공화국 · 경제형" % [String(scenario.get("name","삼국의 균형")),str(scenario.get("start_date",{}).get("year",1000)),gateway.countries().size(),String(scenario.get("description",""))]

func _rebuild_countries(filter_text:String) -> void:
    if not ui.has("country_list"): return
    for child in ui.country_list.get_children(): child.queue_free()
    var needle:=filter_text.strip_edges().to_lower()
    for id_value in gateway.countries().keys():
        var id:=String(id_value); var country:=gateway.country(id); var haystack:=(String(country.get("name",""))+" "+String(country.get("government",""))).to_lower()
        if needle!="" and needle not in haystack: continue
        ui.country_list.add_child(_button("%s\n%s · 난이도 %s" % [country.get("name",id),country.get("government","정부"),_difficulty(country)],_select_country.bind(id),"list",64))

func _select_country(country_id:String) -> void:
    selected_country=country_id; _refresh_country(); var capital:=int(gateway.country(country_id).get("capital_province",-1))
    if capital!=-1: maps[ScreenState.COUNTRY].selected_province_id=capital; maps[ScreenState.COUNTRY].focus_province(capital)

func _country_map_pick(province_id:int) -> void:
    var owner:=String(gateway.province(province_id).get("owner","")); if owner!="": _select_country(owner)

func _refresh_country() -> void:
    if not ui.has("country_detail"): return
    var country:=gateway.country(selected_country)
    ui.country_detail.text="[font_size=24][color=#dec783]%s[/color][/font_size]\n[color=%s]████[/color]  %s\n\n정부  [b]%s[/b]\n수도  [b]%s[/b]\n국고  [b]%s[/b]\n인구  [b]%s[/b]\n경제  [b]%s[/b]\n인력  [b]%s[/b]\n안정도  [b]%s[/b]\n난이도  [b]%s[/b]\n\nProvince %d · 육군 %s" % [country.get("name",selected_country),country.get("color","#777777"),country.get("id",""),country.get("government","정부"),_province_name(int(country.get("capital_province",-1))),_number(int(country.get("treasury",0))),_number(_country_total(selected_country,"population")),_number(_country_total(selected_country,"economy")),_number(int(country.get("manpower",0))),str(country.get("stability",0)),_difficulty(country),_owned(selected_country).size(),_number(_army_total(selected_country))]

func _start_game() -> void:
    if selected_country=="": _notify("플레이할 국가를 선택하세요.","warning"); return
    gateway.select_player_country(selected_country); _add_log("중요","%s로 플레이를 시작했습니다." % _country_name(selected_country),"important"); _show(ScreenState.GAME)

func _province_pick(province_id:int) -> void:
    selected_province=province_id; _game_map().selected_province_id=province_id; _refresh_province()

func _refresh_province() -> void:
    if not ui.has("province_detail"): return
    if selected_province==-1:
        ui.province_title.text="Province를 선택하세요"; ui.province_detail.text="[color=#96a5aa]좌클릭하면 상세 정보와 명령 버튼이 활성화됩니다.[/color]"; return
    var province:=gateway.province(selected_province)
    if province.is_empty(): selected_province=-1; _refresh_province(); return
    var owner_id:=String(province.get("owner","")); var owner:=gateway.country(owner_id); var armies:Dictionary=gateway.snapshot().get("armies",{})
    ui.province_title.text=String(province.get("name","Province"))+("  ★ 수도" if int(owner.get("capital_province",-1))==selected_province else "")
    ui.province_detail.text="[color=#9eacb1]소유국[/color]  [b]%s[/b]\n[color=#9eacb1]점령국[/color]  %s\n\n인구  [b]%s[/b]     경제  [b]%s[/b]\n개발도  [b]%s[/b]     인력  [b]%s[/b]\n지형  [b]%s[/b]     요새  [b]%s[/b]\n불안도  [b]%s%%[/b]     주둔군  [b]%s[/b]\n\n예상 세입  [color=#7ec59f]+%s[/color]\n예상 모집량  [color=#7ec5c9]+%s[/color]\n인접 Province  %s" % [_country_name(owner_id),_country_name(String(province.get("controller",owner_id))),_number(int(province.get("population",0))),_number(int(province.get("economy",0))),str(province.get("development",0)),_number(int(province.get("manpower",float(province.get("population",0))*0.2))),_terrain(String(province.get("terrain","plains"))),str(province.get("fort",0)),str(province.get("revolt_risk",max(0,100-int(owner.get("stability",70))))),_number(int(armies.get(selected_province,province.get("army",0)))),str(int(float(province.get("economy",0))*float(owner.get("tax_rate",0.2)))),str(int(float(province.get("population",0))*0.12+float(province.get("development",0)))),_neighbor_names(province.get("neighbors",[]))]
    ui.action_status.text="자국 Province" if owner_id==selected_country else ("적국 · 전쟁 중" if gateway.at_war(selected_country,owner_id) else "외국 · 공격 전 전쟁 선포 필요")

func _queue_recruit() -> void:
    if not _owned_selected(): return
    var id:=gateway.queue_command("recruit",{"province_id":selected_province,"amount":10},{"title":"병력 모집","from":_province_name(selected_province),"amount":10,"cost":20})
    _add_log("군사","명령 #%d · 병력 10 모집" % id,"normal"); _notify("모집 명령을 추가했습니다.","success")

func _simple_command(kind:String) -> void:
    if not _owned_selected(): return
    var labels:={"develop":"개발 투자","fortify":"요새 건설","move_capital":"수도 이전","occupation":"점령지 관리"}
    gateway.queue_command(kind,{"province_id":selected_province},{"title":labels.get(kind,kind),"from":_province_name(selected_province),"cost":40})

func _prepare_move(kind:String="move") -> void:
    if not _owned_selected(): return
    pending_source=selected_province; pending_kind=kind; var available:=int(gateway.snapshot().get("armies",{}).get(pending_source,0))
    if available<=1: _notify("이동 가능한 병력이 없습니다.","warning"); _cancel_mode(); return
    ui.move_amount.max_value=available-1; ui.move_amount.value=available-1; pending_amount=available-1; ui.move_summary.text="%s · 가용 병력 %d" % [_province_name(pending_source),available]
    _game_map().set_interaction_state(StrategicMap.InputState.MODAL_OPEN,pending_source); move_dialog.popup_centered()

func _move_fraction(fraction:float) -> void:
    var available:=int(gateway.snapshot().get("armies",{}).get(pending_source,0)); ui.move_amount.value=available-1 if fraction<=0.0 or fraction>=1.0 else max(1,int(float(available)*fraction))

func _begin_target() -> void:
    pending_amount=int(ui.move_amount.value); move_dialog.hide(); var target_state:=StrategicMap.InputState.CHOOSING_ATTACK_TARGET if pending_kind=="attack" else StrategicMap.InputState.CHOOSING_MOVE_TARGET
    _game_map().set_interaction_state(target_state,pending_source); ui.action_status.text="목적지 선택 중 · 우클릭 드래그 패닝 · Esc 취소"; _notify("지도에서 목적지를 선택하세요.","info")

func _map_target(province_id:int) -> void:
    if pending_kind=="peace":
        if province_id in peace_demands: peace_demands.erase(province_id)
        else: peace_demands.append(province_id)
        _game_map().set_peace_demands(peace_demands); return
    if pending_kind=="": return
    var source:=gateway.province(pending_source); var target:=gateway.province(province_id)
    if not _has_neighbor(source, province_id): _notify("인접 Province만 선택할 수 있습니다.","warning"); return
    var owner:=String(target.get("owner","")); var kind:="attack" if owner!=selected_country else pending_kind
    if kind=="attack" and not gateway.at_war(selected_country,owner): _notify("전쟁 상태가 아닙니다. 전쟁 선포를 먼저 예약하세요.","warning"); return
    var id:=gateway.queue_command(kind,{"from_id":pending_source,"to_id":province_id,"amount":pending_amount,"leave_garrison":1},{"title":"공격" if kind=="attack" else "이동","from":_province_name(pending_source),"to":_province_name(province_id),"amount":pending_amount,"warning":"전투 발생 가능" if kind=="attack" else ""})
    _add_log("전쟁" if kind=="attack" else "군사","명령 #%d · %s → %s" % [id,_province_name(pending_source),_province_name(province_id)],"important" if kind=="attack" else "normal"); _cancel_mode(); _notify("명령 큐와 지도 화살표에 반영했습니다.","success")

func _cancel_mode() -> void:
    move_dialog.hide(); pending_source=-1; pending_kind=""; pending_amount=0; _game_map().clear_interaction()
    if ui.has("action_status"): ui.action_status.text="명령 준비 상태가 해제되었습니다."

func _rebuild_queue(commands:Array) -> void:
    if not ui.has("queue"): return
    for child in ui.queue.get_children(): child.queue_free()
    var paths:Array=[]
    if commands.is_empty(): ui.queue.add_child(_label("예약된 명령이 없습니다.",13,Color("#829098")))
    for command in commands:
        var row:=HBoxContainer.new(); var p:Dictionary=command.get("presentation",{}); var payload:Dictionary=command.get("payload",{})
        var text:="#%d  %s  %s" % [int(command.get("id",0)),_command_icon(String(command.get("type",""))),String(p.get("title",command.get("type","명령")))]
        if String(p.get("from",""))!="": text+=" · "+String(p.from)
        if String(p.get("to",""))!="": text+=" → "+String(p.to)
        if p.has("amount"): text+=" · 병력 %s" % str(p.amount)
        var label:=_label(text,13,Color("#d9d4c5")); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
        if String(p.get("warning",""))!="": row.add_child(_label("⚠ "+String(p.warning),11,Color("#d9986f")))
        row.add_child(_button("수정",func():_notify("수정 API 준비됨 · 취소 후 다시 입력하세요.","info"),"small")); row.add_child(_button("취소",_cancel_queued.bind(int(command.get("id",0))),"small")); ui.queue.add_child(row)
        if payload.has("from_id") and payload.has("to_id"): paths.append({"from_id":payload.from_id,"to_id":payload.to_id,"type":command.get("type","move")})
    _game_map().set_command_paths(paths)

func _cancel_queued(id:int) -> void:
    if gateway.cancel_command(id): _notify("명령 #%d을 취소했습니다." % id,"success")
func _open_diplomacy() -> void:
    var target:=_foreign_country()
    if target=="":
        for id in gateway.countries().keys():
            if String(id)!=selected_country: target=String(id); break
    if target=="": return
    for child in ui.diplomacy_box.get_children(): child.queue_free()
    var relation:=gateway.relation(selected_country,target); var at_war:=gateway.at_war(selected_country,target)
    ui.diplomacy_box.add_child(_label("%s ↔ %s" % [_country_name(selected_country),_country_name(target)],25,Color("#dec77f")))
    ui.diplomacy_box.add_child(_label("관계도 %d · %s\n현재 전쟁 %s · 동맹 없음 · 불가침 없음 · 휴전 없음\n국력 비교  아군 %s : 상대 %s\n국경 Province  %s" % [relation,"전쟁" if at_war else ("우호" if relation>=20 else "긴장" if relation<=-20 else "중립"),"진행 중" if at_war else "없음",_number(_army_total(selected_country)),_number(_army_total(target)),_border_names(selected_country,target)],14,Color("#b9c2c2")))
    var grid:=GridContainer.new(); grid.columns=2; ui.diplomacy_box.add_child(grid)
    for action in [["관계 개선","improve_relations",25],["모욕","insult",0],["전쟁 선포","declare_war",50],["평화 제안","offer_peace",20],["동맹 제안","offer_alliance",35],["불가침 제안","offer_non_aggression",20],["군사 통행 요청","request_access",15],["속국화 요구","demand_vassalization",80],["독립 요구","demand_independence",60]]:
        var acceptance:=clampi(50+relation-int(action[2])/2,0,100); grid.add_child(_button("%s\n비용 %d · 수락 예상 %d%%" % [action[0],action[2],acceptance],_queue_diplomacy.bind(String(action[1]),target,int(action[2]),acceptance),"danger" if action[1]=="declare_war" else "list",58))
    diplomacy_dialog.popup_centered()

func _queue_diplomacy(kind:String,target:String,cost:int,acceptance:int) -> void:
    var id:=gateway.queue_command(kind,{"target_country_id":target},{"title":_diplomacy_name(kind),"to":_country_name(target),"cost":cost,"warning":"수락 예상 %d%%" % acceptance})
    diplomacy_dialog.hide(); _add_log("외교","명령 #%d · %s → %s" % [id,_diplomacy_name(kind),_country_name(target)],"important"); _notify("외교 명령을 예약했습니다.","success")

func _open_peace() -> void:
    var target:=_foreign_country()
    if target=="": _notify("협상 상대 Province를 먼저 선택하세요.","warning"); return
    for child in ui.peace_box.get_children(): child.queue_free()
    ui.peace_box.add_child(_label("%s 평화 협상" % _country_name(target),24,Color("#dec77f")))
    ui.peace_box.add_child(_label("전쟁 점수 0 · 점령 Province 0\n지도에서 요구할 Province를 직접 선택할 수 있습니다.",14,Color("#b9c2c2")))
    var reparations:=SpinBox.new(); reparations.name="Reparations"; reparations.min_value=0; reparations.max_value=1000; reparations.step=25; reparations.suffix=" 배상금"; ui.peace_box.add_child(reparations)
    var vassal:=CheckBox.new(); vassal.name="Vassalize"; vassal.text="속국화 요구"; ui.peace_box.add_child(vassal)
    var independence:=CheckBox.new(); independence.name="Independence"; independence.text="독립 승인"; ui.peace_box.add_child(independence)
    ui.peace_box.add_child(_label("협상 비용과 AI 수락 예상치는 코어 평가 API 연결 후 갱신됩니다.",12,Color("#d09b70")))
    var row:=HBoxContainer.new(); row.add_child(_button("제안 초기화",_reset_peace)); row.add_child(_button("지도에서 Province 요구",_begin_peace)); row.add_child(_button("제안 전송",_submit_peace.bind(target),"primary")); ui.peace_box.add_child(row)
    peace_dialog.popup_centered()

func _begin_peace() -> void:
    peace_dialog.hide(); pending_kind="peace"; _game_map().set_interaction_state(StrategicMap.InputState.SELECTING_PEACE_TERMS); _notify("지도에서 요구할 Province를 선택한 뒤 평화 창을 다시 여세요.","info")

func _reset_peace() -> void:
    peace_demands.clear(); _game_map().set_peace_demands(peace_demands); _notify("평화 제안을 초기화했습니다.","info")

func _submit_peace(target:String) -> void:
    var reparations:=ui.peace_box.get_node_or_null("Reparations") as SpinBox; var vassal:=ui.peace_box.get_node_or_null("Vassalize") as CheckBox; var independence:=ui.peace_box.get_node_or_null("Independence") as CheckBox
    var payload:={"target_country_id":target,"province_demands":peace_demands.duplicate(),"reparations":int(reparations.value if reparations else 0),"vassalize":vassal.button_pressed if vassal else false,"recognize_independence":independence.button_pressed if independence else false}
    gateway.queue_command("peace_offer",payload,{"title":"평화 제안","to":_country_name(target),"cost":peace_demands.size()*20+int(payload.reparations)/25,"warning":"AI 수락 평가 대기"}); _close_peace(); _notify("평화 제안을 명령 큐에 추가했습니다.","success")

func _close_peace() -> void:
    peace_dialog.hide()
    if pending_kind=="peace": pending_kind=""
    _game_map().clear_interaction()

func _set_map_mode(mode:String) -> void:
    _game_map().set_mode(mode); ui.mode_title.text="%s 지도" % _game_map().mode_label(); _legend(); _notify("%s 지도 모드" % _game_map().mode_label(),"info")

func _legend() -> void:
    if not ui.has("legend") or not maps.has(ScreenState.GAME): return
    var mode:=_game_map().map_mode
    if mode=="political": ui.legend.text="[color=#d2b16c]범례[/color]\n■ 국가색  ▣ 선택\n청록 국경: 자국\n적색 국경: 적국"
    elif mode in ["relations","war"]: ui.legend.text="[color=#d2b16c]범례[/color]\n■ 자국  ■ 동맹/우호\n■ 적국/전쟁  ■ 중립"
    elif mode=="terrain": ui.legend.text="[color=#d2b16c]범례[/color]\n■ 평원  ■ 구릉\n■ 숲  ■ 해안"
    else: ui.legend.text="[color=#d2b16c]범례[/color]\n낮음  ░▒▓█  높음\n8–92 분위수 정규화"

func _map_tooltip(text:String,position:Vector2) -> void:
    if text=="": ui.tooltip.hide(); return
    ui.tooltip_label.text=text; ui.tooltip.position=position+Vector2(14,14); ui.tooltip.show(); ui.tooltip.position=ui.tooltip.position.clamp(Vector2(8,8),get_viewport_rect().size-ui.tooltip.size-Vector2(8,8))

func _search_province(query:String) -> void:
    var needle:=query.strip_edges().to_lower()
    for id in gateway.snapshot().get("provinces",{}).keys():
        if needle in _province_name(int(id)).to_lower(): selected_province=int(id); _game_map().selected_province_id=int(id); _game_map().focus_province(int(id)); _refresh_province(); return
    _notify("일치하는 Province가 없습니다.","warning")

func _refresh_wars() -> void:
    if not ui.has("wars"): return
    var wars:Array=gateway.snapshot().get("wars",[])
    if wars.is_empty(): ui.wars.text="[color=#85949a]진행 중인 전쟁이 없습니다.[/color]"; return
    var text:="[font_size=18][color=#dec77f]전쟁 현황[/color][/font_size]\n"
    for war in wars: text+="\n%s ⚔ %s · 전쟁 점수 %s" % [_country_name(String(war.get("attacker",""))),_country_name(String(war.get("defender",""))),str(war.get("war_score",war.get("score",0)))]
    ui.wars.text=text

func _add_log(category:String,message:String,importance:String="normal") -> void:
    logs.append({"category":category,"message":message,"importance":importance,"time":Time.get_time_string_from_system()}); if logs.size()>LOG_LIMIT: logs.pop_front(); _refresh_logs("전체")
func _filter_logs(category:String) -> void: _refresh_logs(category)
func _refresh_logs(filter:String) -> void:
    if not ui.has("log"): return
    var text:=""
    for entry in logs:
        if filter!="전체" and String(entry.category)!=filter and not (filter=="중요" and entry.importance=="important"): continue
        var color := "#d4cfc0"
        if entry.importance == "important":
            color = "#e1b56d"
        if entry.category == "전쟁":
            color = "#e18070"
        elif entry.category == "외교":
            color = "#78b7c5"
        elif entry.category == "경제":
            color = "#83bd8d"
        text+="[color=#748087]%s[/color] [color=%s][%s][/color] %s\n" % [entry.time,color,entry.category,entry.message]
    ui.log.text=text; ui.log.scroll_to_line(max(0,ui.log.get_line_count()-1))

func _notify(message:String,kind:String="info") -> void:
    ui.toast_label.text = message
    var border := "#d0ad64"
    if kind == "success":
        border = "#6fb292"
    elif kind == "warning":
        border = "#d38d62"
    elif kind == "error":
        border = "#c85c5c"
    toast.add_theme_stylebox_override("panel",_style("#22313a",border,1,8)); toast.show(); toast_timer.start(3.2); _on_resize()

func _settings() -> void:
    var dialog:=AcceptDialog.new(); dialog.title="설정"; dialog.dialog_text="UI 배율·접근성 설정은 저장 API 연결 후 영구 보관됩니다.\n현재 화면은 Container와 anchor로 반응형 배치됩니다."; dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered(Vector2i(520,220))

func _on_resize() -> void:
    if toast: toast.position=Vector2(get_viewport_rect().size.x*0.5-toast.custom_minimum_size.x*0.5,18)
func _frame_map(map:StrategicMap) -> void: if map: map.frame_world()
func _bottom_tab(index:int) -> void: ui.bottom_tabs.current_tab=clampi(index,0,ui.bottom_tabs.get_tab_count()-1)
func _game_map() -> StrategicMap: return maps.get(ScreenState.GAME) as StrategicMap

func _owned_selected() -> bool:
    if selected_province==-1: _notify("먼저 Province를 선택하세요.","warning"); return false
    if String(gateway.province(selected_province).get("owner",""))!=selected_country: _notify("자국 Province에서만 실행할 수 있습니다.","warning"); return false
    return true
func _foreign_country() -> String:
    if selected_province==-1:return ""
    var owner:=String(gateway.province(selected_province).get("owner","")); return "" if owner==selected_country else owner

func _margin(amount:int) -> MarginContainer:
    var node:=MarginContainer.new(); node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); node.add_theme_constant_override("margin_left",amount); node.add_theme_constant_override("margin_right",amount); node.add_theme_constant_override("margin_top",amount); node.add_theme_constant_override("margin_bottom",amount); return node
func _header(title:String,subtitle:String,back:Callable) -> Control:
    var row:=HBoxContainer.new(); row.custom_minimum_size.y=62; row.add_child(_button("← 이전",back)); var box:=VBoxContainer.new(); box.add_child(_label(title,25,Color("#ddc47e"))); box.add_child(_label(subtitle,12,Color("#8f9ca2"))); row.add_child(box); row.add_spacer(true); row.add_child(_label("PROJECT EPOCH",16,Color("#72664c"))); return row
func _section(title:String,min_width:int=0) -> VBoxContainer:
    var box:=VBoxContainer.new(); box.custom_minimum_size.x=min_width; box.add_theme_constant_override("separation",10); box.mouse_filter=Control.MOUSE_FILTER_STOP; box.add_child(_label(title,17,Color("#d8bf7c"))); return box
func _window_box(window:Window) -> VBoxContainer:
    var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",18); margin.add_theme_constant_override("margin_right",18); margin.add_theme_constant_override("margin_top",18); margin.add_theme_constant_override("margin_bottom",18); window.add_child(margin); var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",10); margin.add_child(box); return box
func _label(value:String,size_value:int=14,color:Color=Color.WHITE,alignment:int=HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var node:=Label.new(); node.text=value; node.add_theme_font_size_override("font_size",size_value); node.add_theme_color_override("font_color",color); node.horizontal_alignment=alignment; return node
func _button(value:String,callback:Callable,variant:String="default",height:int=40) -> Button:
    var node:=Button.new(); node.text=value; node.custom_minimum_size.y=height; node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; node.pressed.connect(callback)
    if variant=="primary":node.add_theme_stylebox_override("normal",_style("#7a6139","#d0b06a",1,6))
    elif variant=="danger":node.add_theme_stylebox_override("normal",_style("#593337","#b96864",1,6))
    elif variant=="list":node.alignment=HORIZONTAL_ALIGNMENT_LEFT
    return node
func _stat(caption:String,value:String) -> Label:
    var box:=VBoxContainer.new(); box.custom_minimum_size.x=74; box.add_child(_label(caption,10,Color("#87959b"),HORIZONTAL_ALIGNMENT_CENTER)); var result:=_label(value,14,Color("#e2dcc9"),HORIZONTAL_ALIGNMENT_CENTER); box.add_child(result); return result
func _style(bg:String,border:String,width:int,radius:int) -> StyleBoxFlat:
    var style:=StyleBoxFlat.new(); style.bg_color=Color(bg); style.border_color=Color(border); style.set_border_width_all(width); style.set_corner_radius_all(radius); style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=10; style.content_margin_bottom=10; return style
func _number(value:int) -> String:
    if abs(value)>=1000000:return "%.1fM" % (float(value)/1000000.0)
    if abs(value)>=1000:return "%.1fK" % (float(value)/1000.0)
    return str(value)
func _country_name(id:String)->String:return String(gateway.country(id).get("name",id))
func _province_name(id:int)->String:return String(gateway.province(id).get("name","Province %d"%id))
func _terrain(id:String)->String:return {"plains":"평원","hills":"구릉","forest":"숲","coast":"해안"}.get(id,id)
func _difficulty(country:Dictionary)->String:return "쉬움" if int(country.get("treasury",0))>=130 else "어려움" if int(country.get("aggression",50))>=70 else "보통"
func _owned(country:String)->Array:
    var result:=[]
    for id in gateway.snapshot().get("provinces",{}).keys():
        if String(gateway.province(int(id)).get("owner",""))==country:result.append(int(id))
    return result
func _country_total(country:String,key:String)->int:
    var total:=0
    for id in _owned(country):total+=int(gateway.province(id).get(key,0))
    return total
func _army_total(country:String)->int:
    var total:=0;var armies:Dictionary=gateway.snapshot().get("armies",{})
    for id in _owned(country):total+=int(armies.get(id,0))
    return total
func _income(country:String)->int:return int(float(_country_total(country,"economy"))*float(gateway.country(country).get("tax_rate",0.2)))
func _has_neighbor(province:Dictionary,target_id:int)->bool:
    for neighbor in province.get("neighbors",[]):
        if int(neighbor)==target_id:return true
    return false
func _neighbor_names(ids:Array)->String:
    var names:=PackedStringArray();for id in ids:names.append(_province_name(int(id)))
    return ", ".join(names)
func _border_names(a:String,b:String)->String:
    var names:=PackedStringArray()
    for id in _owned(a):
        for neighbor in gateway.province(id).get("neighbors",[]):
            if String(gateway.province(int(neighbor)).get("owner",""))==b:names.append(_province_name(id));break
    return ", ".join(names) if not names.is_empty() else "없음"
func _command_icon(kind:String)->String:return {"move":"→","attack":"⚔","recruit":"+","declare_war":"!","peace_offer":"◇","develop":"◆","fortify":"▣"}.get(kind,"•")
func _diplomacy_name(kind:String)->String:return {"improve_relations":"관계 개선","insult":"모욕","declare_war":"전쟁 선포","offer_peace":"평화 제안","offer_alliance":"동맹 제안","offer_non_aggression":"불가침 제안","request_access":"군사 통행 요청","demand_vassalization":"속국화 요구","demand_independence":"독립 요구"}.get(kind,kind)
