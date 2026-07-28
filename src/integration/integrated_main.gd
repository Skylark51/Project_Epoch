extends Control

const BASE_MAIN_SCENE := preload("res://src/main.tscn")
const GOVERNANCE_SESSION_SCRIPT := preload("res://src/governance/governance_session.gd")

const GOVERNANCE_STATE_PATH := "res://data/governance/sample_governance_state.json"
const GOVERNANCE_SAVE_PATH := "user://governance_autosave.json"
const GAME_SCREEN_STATE := 3

var base_ui: Control
var governance
var launcher: Button
var status_badge: Label
var dashboard: Window
var dashboard_title: Label
var tabs: TabContainer
var overview_text: RichTextLabel
var group_list: VBoxContainer
var group_detail_text: RichTextLabel
var reform_text: RichTextLabel
var reform_selector: OptionButton
var reform_action_status: Label
var rebellion_text: RichTextLabel
var province_text: RichTextLabel
var alert_text: RichTextLabel

var selected_group_id := "aristocracy"
var last_player_country := ""
var last_selected_province := -1
var last_core_turn := -1
var setup_complete := false
var save_loaded := false


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    base_ui = BASE_MAIN_SCENE.instantiate()
    base_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(base_ui)
    call_deferred("_finish_setup")


func _finish_setup() -> void:
    governance = GOVERNANCE_SESSION_SCRIPT.new()
    governance.governance_changed.connect(_on_governance_changed)
    governance.governance_alert.connect(_on_governance_alert)
    governance.reform_changed.connect(_on_reform_changed)
    governance.rebellion_started.connect(_on_rebellion_started)
    governance.negotiation_changed.connect(_on_negotiation_changed)

    _build_overlay()
    var gateway = _gateway()
    if gateway == null:
        push_error("IntegratedMain: StrategyGateway를 찾지 못했습니다.")
        return

    gateway.snapshot_changed.connect(_on_core_snapshot)
    gateway.integration_notice.connect(_on_core_notice)

    var core_snapshot: Dictionary = gateway.snapshot()
    _initialize_governance(core_snapshot)
    last_core_turn = int(core_snapshot.get("turn", 1))
    last_player_country = String(core_snapshot.get("player_country_id", ""))
    setup_complete = true
    _refresh_all()
    set_process(true)


func _process(_delta: float) -> void:
    if not setup_complete or base_ui == null:
        return
    var current_state := int(base_ui.get("state"))
    launcher.visible = current_state == GAME_SCREEN_STATE
    status_badge.visible = launcher.visible

    var player_country := String(base_ui.get("selected_country"))
    var province_id := int(base_ui.get("selected_province"))
    if player_country != last_player_country or province_id != last_selected_province:
        last_player_country = player_country
        last_selected_province = province_id
        if dashboard.visible:
            _refresh_all()
        _refresh_badge()


func _build_overlay() -> void:
    launcher = Button.new()
    launcher.name = "GovernanceLauncher"
    launcher.text = "⚖ 통치 · 반란"
    launcher.anchor_left = 1.0
    launcher.anchor_right = 1.0
    launcher.offset_left = -420.0
    launcher.offset_right = -282.0
    launcher.offset_top = 10.0
    launcher.offset_bottom = 50.0
    launcher.z_index = 250
    launcher.visible = false
    launcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    launcher.pressed.connect(_open_dashboard)
    add_child(launcher)

    status_badge = Label.new()
    status_badge.name = "GovernanceStatusBadge"
    status_badge.anchor_left = 1.0
    status_badge.anchor_right = 1.0
    status_badge.offset_left = -278.0
    status_badge.offset_right = -205.0
    status_badge.offset_top = 18.0
    status_badge.offset_bottom = 42.0
    status_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_badge.z_index = 251
    status_badge.visible = false
    status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(status_badge)

    dashboard = Window.new()
    dashboard.name = "GovernanceDashboard"
    dashboard.title = "통치 · 개혁 · 정치집단 · 반란"
    dashboard.size = Vector2i(1080, 760)
    dashboard.min_size = Vector2i(880, 640)
    dashboard.visible = false
    dashboard.exclusive = true
    dashboard.close_requested.connect(dashboard.hide)
    add_child(dashboard)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    dashboard.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margin.add_child(root)

    var header := HBoxContainer.new()
    dashboard_title = _label("국가 통치 현황", 23, Color("#e1c77f"))
    header.add_child(dashboard_title)
    header.add_spacer(true)
    header.add_child(_button("상태 저장", _save_governance, "primary"))
    header.add_child(_button("새로고침", _refresh_all))
    header.add_child(_button("닫기", dashboard.hide))
    root.add_child(header)

    tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tabs.tab_changed.connect(func(_index): _refresh_all())
    root.add_child(tabs)

    overview_text = _rich_text("국가 개요")
    tabs.add_child(_scroll_wrap(overview_text))

    var groups_root := HSplitContainer.new()
    groups_root.name = "정치 집단"
    groups_root.split_offset = 360
    group_list = VBoxContainer.new()
    group_list.custom_minimum_size.x = 330
    group_list.add_theme_constant_override("separation", 6)
    var group_scroll := ScrollContainer.new()
    group_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    group_scroll.add_child(group_list)
    groups_root.add_child(group_scroll)
    group_detail_text = RichTextLabel.new()
    group_detail_text.bbcode_enabled = true
    group_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    group_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    groups_root.add_child(group_detail_text)
    tabs.add_child(groups_root)

    var reform_root := VBoxContainer.new()
    reform_root.name = "통치체제 개혁"
    reform_root.add_theme_constant_override("separation", 9)
    reform_text = RichTextLabel.new()
    reform_text.bbcode_enabled = true
    reform_text.custom_minimum_size.y = 310
    reform_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    reform_root.add_child(reform_text)
    var reform_row := HBoxContainer.new()
    reform_selector = OptionButton.new()
    reform_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reform_row.add_child(reform_selector)
    reform_row.add_child(_button("개혁 시작", _start_selected_reform, "primary"))
    reform_root.add_child(reform_row)
    reform_action_status = _label("진행 중인 개혁이 있으면 반발 대응을 선택할 수 있습니다.", 12, Color("#9da9ad"))
    reform_action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    reform_root.add_child(reform_action_status)
    var response_grid := GridContainer.new()
    response_grid.columns = 4
    response_grid.add_child(_button("협상", _respond_reform.bind("negotiate"), "list"))
    response_grid.add_child(_button("매수", _respond_reform.bind("bribe"), "list"))
    response_grid.add_child(_button("숙청", _respond_reform.bind("purge"), "danger"))
    response_grid.add_child(_button("군사 진압", _respond_reform.bind("suppress"), "danger"))
    reform_root.add_child(response_grid)
    tabs.add_child(reform_root)

    rebellion_text = _rich_text("반란 · 독립협상")
    tabs.add_child(_scroll_wrap(rebellion_text))

    province_text = _rich_text("프로빈스 통치")
    tabs.add_child(_scroll_wrap(province_text))

    alert_text = _rich_text("통치 기록")
    tabs.add_child(_scroll_wrap(alert_text))


func _rich_text(tab_name: String) -> RichTextLabel:
    var text := RichTextLabel.new()
    text.name = tab_name
    text.bbcode_enabled = true
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    return text


func _scroll_wrap(content: Control) -> ScrollContainer:
    var scroll := ScrollContainer.new()
    scroll.name = content.name
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.name = "Content"
    content.custom_minimum_size.x = 760
    scroll.add_child(content)
    return scroll


func _initialize_governance(core_snapshot: Dictionary) -> void:
    var saved := _load_json(GOVERNANCE_SAVE_PATH)
    if saved is Dictionary and not saved.is_empty():
        var saved_core_turn := int(saved.get("core_turn", -999))
        var current_turn := int(core_snapshot.get("turn", 1))
        if saved_core_turn == current_turn and saved.has("governance"):
            _restore_governance(saved.governance)
            save_loaded = true
            _sync_governance_from_core(core_snapshot)
            return

    save_loaded = false
    _seed_governance(core_snapshot)
    _save_governance()


func _seed_governance(core_snapshot: Dictionary) -> void:
    governance.turn = 0
    governance.alerts.clear()
    governance.factions.clear()
    governance.provinces.clear()
    governance.political_groups.clear()
    governance.rebellions.clear()
    governance.negotiations.clear()

    var presets_value = _load_json(GOVERNANCE_STATE_PATH)
    var presets: Dictionary = presets_value if presets_value is Dictionary else {}
    var faction_presets: Dictionary = presets.get("factions", {})
    var governor_presets: Dictionary = presets.get("governors", {})

    var countries: Dictionary = core_snapshot.get("countries", {})
    for country_id_value in countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = countries[country_id_value]
        var preset: Dictionary = faction_presets.get(country_id, {})
        var administration_level := int(country.get("technology", {}).get("administration", 1))
        governance.register_faction({
            "faction_id": country_id,
            "name": country.get("name", country_id),
            "government_type": preset.get("government_type", _map_government(String(country.get("government", "")))),
            "authority_hidden": float(preset.get("authority_hidden", country.get("stability", 50.0))),
            "legitimacy_hidden": float(preset.get("legitimacy_hidden", country.get("stability", 50.0))),
            "corruption_hidden": float(preset.get("corruption_hidden", 15.0)),
            "administration_capacity": int(preset.get("administration_capacity", 20 + administration_level * 18)),
            "treasury": int(country.get("treasury", 0)),
            "technology_tags": preset.get("technology_tags", _technology_tags(administration_level)),
            "reform_stage": "none",
            "active_reform": {},
        })

        var group_presets: Dictionary = preset.get("groups", {})
        for group_definition_value in governance.definitions.get("groups", {}).get("groups", []):
            if group_definition_value is not Dictionary:
                continue
            var group_definition: Dictionary = group_definition_value
            var group_id := String(group_definition.get("id", ""))
            var group_preset: Dictionary = group_presets.get(group_id, {})
            governance.register_group(country_id, {
                "group_id": group_id,
                "group_type": group_id,
                "name": group_definition.get("name", group_id),
                "interests": group_definition.get("interests", []).duplicate(true),
                "influence_hidden": float(group_preset.get("influence_hidden", _default_group_influence(group_id, country))),
                "satisfaction_hidden": float(group_preset.get("satisfaction_hidden", _default_group_satisfaction(group_id, country))),
                "rebellion_risk_hidden": float(group_preset.get("rebellion_risk_hidden", 12.0)),
                "mobilization_capacity": float(group_preset.get("mobilization_capacity", _default_mobilization(group_id))),
                "demands": group_preset.get("demands", _default_demands(group_id)).duplicate(true),
                "reform_stance": "neutral",
                "active_causes": [],
                "recent_modifiers": [],
                "representative_character_id": String(group_preset.get("representative_character_id", "REP_%s_%s" % [country_id, group_id.to_upper()])),
            })

    var provinces: Dictionary = core_snapshot.get("provinces", {})
    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id_value]
        var governor: Dictionary = governor_presets.get(str(province_id), _fallback_governor(province_id))
        var owner_id := String(province.get("owner", ""))
        var controller_id := String(province.get("controller", owner_id))
        governance.register_province({
            "province_id": str(province_id),
            "name": province.get("name", "Province %d" % province_id),
            "owner_faction_id": owner_id,
            "controller_faction_id": controller_id,
            "control_progress_hidden": 100.0 if owner_id == controller_id else 68.0,
            "governor_character_id": String(governor.get("character_id", "GOV_%d" % province_id)),
            "governor_name": String(governor.get("name", "무명 지방관")),
            "governor_type": String(governor.get("governor_type", "appointed_governor")),
            "governor_personality": String(governor.get("personality", "pragmatic")),
            "governor_loyalty": float(governor.get("loyalty", 60.0)),
            "governor_ambition": float(governor.get("ambition", 40.0)),
            "governor_administration": float(governor.get("administration", 50.0)),
            "governor_military": float(governor.get("military", 45.0)),
            "population": int(province.get("population", 0)),
            "strategic_point_ids": _strategic_points(province_id, province),
            "temporary_status": "",
        })

    governance.call("_emit_snapshot")


func _restore_governance(snapshot_data: Dictionary) -> void:
    governance.turn = int(snapshot_data.get("turn", 0))
    governance.factions = snapshot_data.get("factions", {}).duplicate(true)
    governance.provinces = snapshot_data.get("provinces", {}).duplicate(true)
    governance.political_groups = snapshot_data.get("political_groups", {}).duplicate(true)
    governance.rebellions = snapshot_data.get("rebellions", {}).duplicate(true)
    governance.negotiations = snapshot_data.get("negotiations", {}).duplicate(true)
    governance.alerts = snapshot_data.get("alerts", []).duplicate(true)
    governance.call("_emit_snapshot")


func _sync_governance_from_core(core_snapshot: Dictionary) -> void:
    for country_id_value in core_snapshot.get("countries", {}).keys():
        var country_id := String(country_id_value)
        if not governance.factions.has(country_id):
            continue
        var country: Dictionary = core_snapshot.countries[country_id_value]
        var faction: Dictionary = governance.factions[country_id]
        faction["treasury"] = int(country.get("treasury", faction.get("treasury", 0)))
        faction["authority_hidden"] = clampf(float(country.get("stability", 50.0)) * 0.75 + float(faction.get("authority_hidden", 50.0)) * 0.25, 0.0, 100.0)
        governance.factions[country_id] = faction

    for province_id_value in core_snapshot.get("provinces", {}).keys():
        var province_key := str(int(province_id_value))
        if not governance.provinces.has(province_key):
            continue
        var core_province: Dictionary = core_snapshot.provinces[province_id_value]
        var province: Dictionary = governance.provinces[province_key]
        var old_controller := String(province.get("controller_faction_id", ""))
        var owner_id := String(core_province.get("owner", ""))
        var controller_id := String(core_province.get("controller", owner_id))
        province["owner_faction_id"] = owner_id
        province["controller_faction_id"] = controller_id
        province["population"] = int(core_province.get("population", province.get("population", 0)))
        governance.provinces[province_key] = province
        if old_controller != controller_id:
            governance.update_province_control(province_key, {
                "controller_change": 30.0 if controller_id == owner_id else -32.0,
                "garrison": float(_gateway().snapshot().get("armies", {}).get(int(province_id_value), 0)) / 150.0,
                "local_support": maxf(0.0, 20.0 - float(core_province.get("revolt_risk", 0.0))),
                "occupation_abuse": 8.0 if controller_id != owner_id else 0.0,
            }, _governor_view(province), {
                "enemy_pressure": controller_id != owner_id,
                "relief_possible": true,
            })
    governance.call("_emit_snapshot")


func _on_core_snapshot(core_snapshot: Dictionary) -> void:
    if not setup_complete:
        return
    var core_turn := int(core_snapshot.get("turn", 1))
    if last_core_turn >= 0 and core_turn < last_core_turn:
        _seed_governance(core_snapshot)
    elif last_core_turn >= 0 and core_turn > last_core_turn:
        for _step in range(core_turn - last_core_turn):
            governance.advance_turn(_build_turn_contexts(core_snapshot))
    last_core_turn = core_turn
    _sync_governance_from_core(core_snapshot)
    _save_governance()
    _refresh_all()


func _build_turn_contexts(core_snapshot: Dictionary) -> Dictionary:
    var group_contexts := {}
    var reform_contexts := {}
    var coalition_contexts := {}
    var statehood_contexts := {}

    var countries: Dictionary = core_snapshot.get("countries", {})
    for country_id_value in countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = countries[country_id_value]
        var stability := float(country.get("stability", 50.0))
        var exhaustion := float(country.get("war_exhaustion", 0.0))
        var treasury := float(country.get("treasury", 0.0))
        var foreign_war := _country_at_war(country_id, core_snapshot)
        var group_map := {}

        for group_id_value in governance.political_groups.get(country_id, {}).keys():
            var group_id := String(group_id_value)
            var base_delta := (stability - 55.0) * 0.035
            var causes: Array[String] = []
            var policy_effects := {}

            if treasury < 80.0:
                base_delta -= 1.2
                causes.append("국고 부족")
            if exhaustion > 35.0:
                base_delta -= minf(exhaustion / 30.0, 3.5)
                causes.append("전쟁 피로")
            if foreign_war:
                causes.append("대외 전쟁")

            match group_id:
                "aristocracy":
                    policy_effects["hereditary_rights"] = -2.5 if _group_opposes_reform(country_id, group_id) else 0.4
                "military":
                    policy_effects["pay"] = -2.0 if treasury < 120.0 else 0.8
                    policy_effects["war_policy"] = -1.5 if exhaustion > 50.0 else (0.7 if foreign_war else 0.0)
                "bureaucracy":
                    var capacity := float(governance.factions.get(country_id, {}).get("administration_capacity", 30))
                    policy_effects["administrative_stability"] = (capacity - 40.0) * 0.035
                "religious_estate":
                    policy_effects["ritual"] = 0.2
                "local_populace":
                    var tax_rate := float(country.get("tax_rate", 0.24))
                    policy_effects["tax"] = -3.0 if tax_rate > 0.26 else 0.8
                    policy_effects["security"] = (stability - 50.0) * 0.035
                    if tax_rate > 0.26:
                        causes.append("높은 세금")

            group_map[group_id] = {
                "base_satisfaction_delta": base_delta,
                "policy_effects": policy_effects,
                "foreign_war": foreign_war,
                "central_army_deterrence": minf(float(_army_total_for_country(country_id, core_snapshot)) / 800.0, 18.0),
                "central_control_deterrence": maxf(0.0, (stability - 30.0) * 0.18),
                "causes": causes,
                "gradual_change": true,
                "risk_smoothing": 0.28,
            }

        group_contexts[country_id] = group_map
        reform_contexts[country_id] = {
            "major_war": foreign_war and exhaustion > 45.0,
            "treasury_crisis": treasury < 50.0,
            "low_central_control": stability < 40.0,
            "famine": false,
            "epidemic": false,
            "major_disaster": false,
            "succession_crisis": false,
        }

        var origin_ids := _country_province_ids(country_id, core_snapshot)
        coalition_contexts[country_id] = {
            "foreign_war": foreign_war,
            "capital_control_weak": stability < 38.0,
            "central_army_absent": _army_total_for_country(country_id, core_snapshot) < 1000,
            "major_defeat": exhaustion > 70.0,
            "secret_network": _has_multiple_dangerous_groups(country_id),
            "private_army": _aristocracy_is_strong(country_id),
            "secured_province": not origin_ids.is_empty() and stability < 45.0,
            "origin_province_ids": origin_ids,
            "secret_meetings": _has_multiple_dangerous_groups(country_id),
            "fund_transfers": treasury < 80.0,
            "private_army_growth": _aristocracy_is_strong(country_id),
            "rumors": stability < 45.0,
            "order_refusal": stability < 35.0,
            "incompatible_group_pairs": [["aristocracy", "local_populace"]] if stability >= 25.0 else [],
        }

    for rebellion_id_value in governance.rebellions.keys():
        var rebellion_id := String(rebellion_id_value)
        var rebellion: Dictionary = governance.rebellions[rebellion_id]
        var occupied: Array = rebellion.get("occupied_province_ids", [])
        var population := 0
        var centers: Array[Dictionary] = []
        for province_id_value in occupied:
            var province_id := int(String(province_id_value))
            var core_province: Dictionary = core_snapshot.get("provinces", {}).get(province_id, {})
            population += int(core_province.get("population", 0))
            if not core_province.is_empty():
                centers.append({
                    "id": str(province_id),
                    "name": core_province.get("name", str(province_id)),
                    "historical_center": bool(core_province.get("capital", false)),
                    "leader_home": true,
                    "former_capital": bool(core_province.get("capital", false)),
                    "defense": float(core_province.get("fort", 0)) * 20.0,
                    "logistics": float(core_province.get("economy", 0)),
                })
        statehood_contexts[rebellion_id] = {
            "controlled_population": population,
            "parent_state_weak": _parent_state_is_weak(String(rebellion.get("parent_faction_id", "")), core_snapshot),
            "historical_candidates": _historical_state_candidates(rebellion),
            "controlled_centers": centers,
        }

    return {
        "group_contexts": group_contexts,
        "reform_contexts": reform_contexts,
        "coalition_contexts": coalition_contexts,
        "statehood_contexts": statehood_contexts,
    }


func _open_dashboard() -> void:
    _refresh_all()
    dashboard.popup_centered()


func _refresh_all() -> void:
    if not setup_complete:
        return
    _refresh_badge()
    _refresh_overview()
    _refresh_groups()
    _refresh_reform()
    _refresh_rebellions()
    _refresh_province()
    _refresh_alerts()


func _refresh_badge() -> void:
    if status_badge == null or governance == null:
        return
    var country_id := _current_country_id()
    var highest_risk := "안정"
    var risk_order := {"안정": 0, "주의": 1, "불안": 2, "위험": 3, "임박": 4}
    var highest_value := 0
    for group_id_value in governance.political_groups.get(country_id, {}).keys():
        var detail: Dictionary = governance.group_detail(country_id, String(group_id_value))
        var name := String(detail.get("rebellion_risk", {}).get("name", "안정"))
        var value := int(risk_order.get(name, 0))
        if value > highest_value:
            highest_value = value
            highest_risk = name
    status_badge.text = highest_risk
    status_badge.add_theme_color_override("font_color", _risk_color(highest_risk))


func _refresh_overview() -> void:
    var country_id := _current_country_id()
    var faction: Dictionary = governance.factions.get(country_id, {})
    var government: Dictionary = governance.government_definition(String(faction.get("government_type", "")))
    var authority := EpochStageScale.stage(float(faction.get("authority_hidden", 0.0)), EpochStageScale.INFLUENCE)
    var legitimacy := EpochStageScale.stage(float(faction.get("legitimacy_hidden", 0.0)), EpochStageScale.INFLUENCE)
    var reform: Dictionary = faction.get("active_reform", {})
    var reform_line := "진행 중인 개혁 없음"
    if not reform.is_empty() and bool(reform.get("is_active", false)):
        var stage_view: Dictionary = governance.reform_system.stage_view(reform)
        reform_line = "%s · %s · %s" % [
            governance.government_definition(String(reform.get("target_government_id", ""))).get("name", "새 제도"),
            stage_view.get("stage_name", ""),
            stage_view.get("progress_stage", {}).get("name", ""),
        ]

    dashboard_title.text = "%s · 국가 통치 현황" % _country_name(country_id)
    overview_text.text = (
        "[font_size=26][color=#e2ca82]%s[/color][/font_size]\n"
        "[color=#9aa8ad]기본 통치체제[/color]  [b]%s[/b]\n"
        "[color=#9aa8ad]군주 권위[/color]  [b]%s[/b]\n"
        "[color=#9aa8ad]정통성[/color]  [b]%s[/b]\n"
        "[color=#9aa8ad]행정 역량[/color]  [b]%d[/b]\n"
        "[color=#9aa8ad]통치 재정[/color]  [b]%d[/b]\n"
        "[color=#9aa8ad]개혁 상태[/color]  [b]%s[/b]\n"
        "[color=#9aa8ad]통치 시스템 턴[/color]  [b]%d[/b]\n\n"
        "[color=#d5b76d]운영 원칙[/color]\n"
        "• 국가는 하나의 기본 통치체제를 유지합니다.\n"
        "• 체제 변경은 준비 → 시행 → 정착의 3단계 개혁으로 진행됩니다.\n"
        "• 정치 집단의 태도는 매 턴 점진적으로 변합니다.\n"
        "• 공동반란은 복수 집단·공통 명분·국가 위기·거점이 모두 필요합니다.\n"
        "• 반란 세력은 공동의 적을 공유해도 각자 별도 세력으로 움직입니다."
    ) % [
        _country_name(country_id),
        government.get("name", faction.get("government_type", "미정")),
        authority.get("name", ""),
        legitimacy.get("name", ""),
        int(faction.get("administration_capacity", 0)),
        int(faction.get("treasury", 0)),
        reform_line,
        int(governance.turn),
    ]


func _refresh_groups() -> void:
    for child in group_list.get_children():
        child.queue_free()
    var country_id := _current_country_id()
    var groups: Dictionary = governance.political_groups.get(country_id, {})
    if groups.is_empty():
        group_list.add_child(_label("등록된 정치 집단이 없습니다.", 13, Color("#8d9ba1")))
        group_detail_text.text = ""
        return

    if not groups.has(selected_group_id):
        selected_group_id = String(groups.keys()[0])

    for group_id_value in groups.keys():
        var group_id := String(group_id_value)
        var detail: Dictionary = governance.group_detail(country_id, group_id)
        var caption := "%s\n영향력 %s · 만족도 %s · 반란 %s" % [
            detail.get("name", group_id),
            detail.get("influence", {}).get("name", ""),
            detail.get("satisfaction", {}).get("name", ""),
            detail.get("rebellion_risk", {}).get("name", ""),
        ]
        group_list.add_child(_button(caption, _select_group.bind(group_id), "primary" if group_id == selected_group_id else "list", 62))

    _refresh_group_detail()


func _select_group(group_id: String) -> void:
    selected_group_id = group_id
    _refresh_groups()


func _refresh_group_detail() -> void:
    var country_id := _current_country_id()
    var detail: Dictionary = governance.group_detail(country_id, selected_group_id)
    if detail.is_empty():
        group_detail_text.text = ""
        return
    var demands: Array = detail.get("demands", [])
    var history: Array = detail.get("recent_modifiers", [])
    var history_text := "기록 없음"
    if not history.is_empty():
        var lines := PackedStringArray()
        for item_value in history:
            if item_value is Dictionary:
                var item: Dictionary = item_value
                lines.append("• %s턴 · 만족도 %+.1f · 위험 %+.1f · %s" % [
                    str(item.get("turn", "?")),
                    float(item.get("satisfaction_delta", item.get("delta", 0.0))),
                    float(item.get("risk_delta", 0.0)),
                    ", ".join(PackedStringArray(item.get("causes", []))) if not item.get("causes", []).is_empty() else "특이사항 없음",
                ])
        history_text = "\n".join(lines)

    group_detail_text.text = (
        "[font_size=24][color=#e0c77e]%s[/color][/font_size]\n\n"
        "영향력  [b]%s[/b]\n"
        "만족도  [b]%s[/b]\n"
        "반란 위험  [b]%s[/b]\n"
        "다음 단계 근접도  [b]%s[/b]\n"
        "추세  [b]%s[/b]\n"
        "개혁 태도  [b]%s[/b]\n\n"
        "[color=#d3b468]현재 요구[/color]\n%s\n\n"
        "[color=#d3b468]최근 10턴 기록[/color]\n%s"
    ) % [
        detail.get("name", selected_group_id),
        detail.get("influence", {}).get("name", ""),
        detail.get("satisfaction", {}).get("name", ""),
        detail.get("rebellion_risk", {}).get("name", ""),
        detail.get("proximity", {}).get("name", ""),
        detail.get("trend", "유지"),
        _stance_name(String(detail.get("reform_stance", "neutral"))),
        "• " + "\n• ".join(PackedStringArray(demands)) if not demands.is_empty() else "요구 없음",
        history_text,
    ]


func _refresh_reform() -> void:
    var country_id := _current_country_id()
    var faction: Dictionary = governance.factions.get(country_id, {})
    var current_government: Dictionary = governance.government_definition(String(faction.get("government_type", "")))
    var active: Dictionary = faction.get("active_reform", {})

    reform_selector.clear()
    var definitions: Array = governance.definitions.get("governments", {}).get("government_types", [])
    for definition_value in definitions:
        if definition_value is not Dictionary:
            continue
        var definition: Dictionary = definition_value
        reform_selector.add_item(String(definition.get("name", definition.get("id", ""))))
        reform_selector.set_item_metadata(reform_selector.item_count - 1, String(definition.get("id", "")))

    var active_text := "진행 중인 개혁이 없습니다."
    if not active.is_empty() and bool(active.get("is_active", false)):
        var view: Dictionary = governance.reform_system.stage_view(active)
        var target := governance.government_definition(String(active.get("target_government_id", "")))
        active_text = (
            "[b]%s[/b] 전환\n"
            "현재 단계: [b]%s[/b]\n"
            "단계 진행: [b]%s[/b]\n"
            "단계 체류: [b]%d턴[/b]\n"
            "지지 집단: %s\n"
            "반대 집단: %s"
        ) % [
            target.get("name", "새 체제"),
            view.get("stage_name", ""),
            view.get("progress_stage", {}).get("name", ""),
            int(view.get("turns_in_stage", 0)),
            ", ".join(PackedStringArray(active.get("support_group_ids", []))) if not active.get("support_group_ids", []).is_empty() else "없음",
            ", ".join(PackedStringArray(active.get("opposition_group_ids", []))) if not active.get("opposition_group_ids", []).is_empty() else "없음",
        ]

    reform_text.text = (
        "[font_size=24][color=#dfc57a]통치체제 개혁[/color][/font_size]\n\n"
        "현재 체제  [b]%s[/b]\n\n%s\n\n"
        "[color=#9da9ad]개혁 시작 조건은 군주 권위, 행정 역량, 재정, 기술, 수도 상태를 함께 검사합니다. "
        "진행 중에는 협상·매수·숙청·군사 진압으로 반발에 대응할 수 있습니다.[/color]"
    ) % [current_government.get("name", "미정"), active_text]


func _start_selected_reform() -> void:
    if reform_selector.item_count == 0:
        return
    var target_id := String(reform_selector.get_item_metadata(reform_selector.selected))
    var country_id := _current_country_id()
    var result: Dictionary = governance.start_reform(country_id, target_id, {
        "succession_crisis": false,
        "capital_occupied": _capital_is_occupied(country_id),
    })
    if bool(result.get("accepted", false)):
        _configure_reform_stances(country_id, target_id)
        reform_action_status.text = "개혁을 시작했습니다."
        _notify_base("통치체제 개혁을 시작했습니다.", "success")
        _save_governance()
        _refresh_all()
        return
    var reasons: Array = result.get("reasons", [])
    reform_action_status.text = "개혁 시작 불가: %s" % (", ".join(PackedStringArray(reasons)) if not reasons.is_empty() else result.get("reason", "조건 미충족"))
    _notify_base(reform_action_status.text, "warning")


func _configure_reform_stances(country_id: String, target_id: String) -> void:
    var stances := {
        "aristocracy": "neutral",
        "military": "neutral",
        "bureaucracy": "neutral",
        "religious_estate": "neutral",
        "local_populace": "neutral",
    }
    if target_id in ["commandery_county", "autocratic_bureaucracy"]:
        stances["aristocracy"] = "oppose"
        stances["bureaucracy"] = "support"
        stances["military"] = "oppose" if target_id == "autocratic_bureaucracy" else "neutral"
        stances["local_populace"] = "support"
    elif target_id in ["feudal", "aristocratic_council"]:
        stances["aristocracy"] = "support"
        stances["bureaucracy"] = "oppose"
        stances["local_populace"] = "oppose"
    elif target_id == "military_governorate":
        stances["military"] = "support"
        stances["bureaucracy"] = "oppose"
        stances["local_populace"] = "oppose"
    elif target_id == "tribal_confederation":
        stances["aristocracy"] = "support"
        stances["bureaucracy"] = "oppose"

    for group_id_value in stances.keys():
        var group_id := String(group_id_value)
        if not governance.political_groups.get(country_id, {}).has(group_id):
            continue
        var group: Dictionary = governance.political_groups[country_id][group_id]
        group["reform_stance"] = stances[group_id]
        group["active_causes"] = ["통치체제 개혁"] if stances[group_id] == "oppose" else []
        governance.political_groups[country_id][group_id] = group
    governance.call("_emit_snapshot")


func _respond_reform(response_id: String) -> void:
    var country_id := _current_country_id()
    var target_group := selected_group_id if _group_opposes_reform(country_id, selected_group_id) else ""
    var result: Dictionary = governance.respond_to_reform_opposition(country_id, response_id, target_group)
    if bool(result.get("accepted", false)):
        reform_action_status.text = "'%s' 대응을 적용했습니다." % _response_name(response_id)
        _notify_base(reform_action_status.text, "success")
        _save_governance()
        _refresh_all()
    else:
        reform_action_status.text = String(result.get("reason", "대응 실패"))
        _notify_base(reform_action_status.text, "warning")


func _refresh_rebellions() -> void:
    var country_id := _current_country_id()
    var lines := PackedStringArray()
    lines.append("[font_size=24][color=#dfc57a]반란 · 독립협상[/color][/font_size]")
    lines.append("")

    var rebellion_count := 0
    for rebellion_value in governance.rebellions.values():
        if rebellion_value is not Dictionary:
            continue
        var rebellion: Dictionary = rebellion_value
        if String(rebellion.get("parent_faction_id", "")) != country_id:
            continue
        rebellion_count += 1
        lines.append("[b]%s[/b] · %s" % [rebellion.get("name", rebellion.get("rebellion_id", "")), _rebellion_status_name(String(rebellion.get("status", "active")))])
        lines.append("목표: %s · 병력 %d · 식량 %d · 생존 %d턴" % [
            rebellion.get("goal", ""),
            int(rebellion.get("troops", 0)),
            int(rebellion.get("food", 0)),
            int(rebellion.get("turns_survived", 0)),
        ])
        lines.append("점령지: %s · 국가 선포 진행 %d%%" % [
            ", ".join(PackedStringArray(rebellion.get("occupied_province_ids", []))) if not rebellion.get("occupied_province_ids", []).is_empty() else "없음",
            int(float(rebellion.get("statehood_progress", 0.0))),
        ])
        if String(rebellion.get("declared_state_name", "")) != "":
            lines.append("선포 국호: [b]%s[/b] · 수도 %s" % [rebellion.get("declared_state_name", ""), rebellion.get("capital_id", "")])
        lines.append("")

    if rebellion_count == 0:
        lines.append("[color=#8e9da2]현재 활동 중인 반란 세력이 없습니다.[/color]")
        lines.append("공동반란은 둘 이상의 불만 집단, 강한 영향력 집단, 공통 명분, 국가적 위기, 거점·병력 조건을 모두 요구합니다.")

    lines.append("")
    lines.append("[color=#d3b468]진행 중인 독립 협상[/color]")
    var negotiation_count := 0
    for negotiation_value in governance.negotiations.values():
        if negotiation_value is not Dictionary:
            continue
        var negotiation: Dictionary = negotiation_value
        if String(negotiation.get("initiator_id", "")) != country_id and String(negotiation.get("counterpart_id", "")) != country_id:
            continue
        negotiation_count += 1
        lines.append("• %s · %s · %s" % [
            negotiation.get("negotiation_id", ""),
            _negotiation_stage_name(String(negotiation.get("stage", "opening"))),
            negotiation.get("status", "active"),
        ])
        if not negotiation.get("armistice", {}).is_empty():
            var armistice: Dictionary = negotiation.armistice
            lines.append("  휴전: %s · %d~%d턴 · 병력 이동 %s" % [
                armistice.get("status", "proposed"),
                int(armistice.get("start_turn", 0)),
                int(armistice.get("end_turn", 0)),
                armistice.get("movement_policy", "limited"),
            ])
    if negotiation_count == 0:
        lines.append("• 없음")

    rebellion_text.text = "\n".join(lines)


func _refresh_province() -> void:
    var province_id := _current_province_id()
    if province_id < 0:
        province_text.text = "[font_size=24][color=#dfc57a]프로빈스 통치[/color][/font_size]\n\n지도에서 프로빈스를 선택하세요."
        return
    var province: Dictionary = governance.provinces.get(str(province_id), {})
    if province.is_empty():
        province_text.text = "통치 데이터가 없습니다."
        return
    var control_name := EpochStageScale.stage_name(float(province.get("control_progress_hidden", 0.0)), EpochStageScale.CONTROL)
    var strategic_points: Array = province.get("strategic_point_ids", [])
    province_text.text = (
        "[font_size=24][color=#dfc57a]%s[/color][/font_size]\n\n"
        "정치적 소유국  [b]%s[/b]\n"
        "군사적 통제국  [b]%s[/b]\n"
        "통제율 단계  [b]%s[/b]\n"
        "지방 통치자  [b]%s[/b]\n"
        "통치자 유형  [b]%s[/b]\n"
        "충성도 경향  [b]%s[/b]\n"
        "야망 경향  [b]%s[/b]\n"
        "최근 판단  [b]%s[/b]\n\n"
        "[color=#d3b468]핵심 지점 %d개[/color]\n• %s\n\n"
        "[color=#9da9ad]프로빈스의 중심 도시를 점령하더라도 군사 통제율과 통치자의 항복·도주·저항 결정을 거쳐야 정치적 귀속이 확정됩니다.[/color]"
    ) % [
        province.get("name", str(province_id)),
        _country_name(String(province.get("owner_faction_id", ""))),
        _country_name(String(province.get("controller_faction_id", ""))),
        control_name,
        province.get("governor_name", province.get("governor_character_id", "")),
        _governor_type_name(String(province.get("governor_type", ""))),
        _trait_stage(float(province.get("governor_loyalty", 50.0))),
        _trait_stage(float(province.get("governor_ambition", 50.0))),
        _governor_decision_name(String(province.get("governor_decision", "hold"))),
        strategic_points.size(),
        "\n• ".join(PackedStringArray(strategic_points)),
    ]


func _refresh_alerts() -> void:
    var lines := PackedStringArray()
    lines.append("[font_size=24][color=#dfc57a]통치 기록[/color][/font_size]")
    lines.append("")
    var entries: Array = governance.alerts
    var start := maxi(0, entries.size() - 40)
    for index in range(start, entries.size()):
        var entry: Dictionary = entries[index]
        lines.append("[color=#89979c]%s턴[/color] [b][%s][/b] %s" % [
            str(entry.get("turn", "?")),
            entry.get("category", "일반"),
            entry.get("message", ""),
        ])
    if entries.is_empty():
        lines.append("기록 없음")
    alert_text.text = "\n".join(lines)


func _on_governance_changed(_snapshot: Dictionary) -> void:
    if setup_complete and dashboard != null and dashboard.visible:
        _refresh_all()
    if setup_complete:
        _refresh_badge()


func _on_governance_alert(alert: Dictionary) -> void:
    if not setup_complete:
        return
    var category := "반란" if String(alert.get("category", "")) in ["rebellion", "politics"] else "중요"
    if base_ui.has_method("_add_log"):
        base_ui.call("_add_log", category, String(alert.get("message", "")), "important")
    _notify_base(String(alert.get("message", "")), "warning" if String(alert.get("importance", "")) == "danger" else "info")


func _on_reform_changed(_faction_id: String, _state: Dictionary) -> void:
    _save_governance()


func _on_rebellion_started(rebellion_list: Array) -> void:
    _save_governance()
    if not rebellion_list.is_empty():
        _notify_base("%d개 정치 집단이 별도 반란 세력으로 봉기했습니다." % rebellion_list.size(), "warning")


func _on_negotiation_changed(_negotiation_id: String, _state: Dictionary) -> void:
    _save_governance()


func _on_core_notice(message: String) -> void:
    if "자동 저장" in message:
        _save_governance()


func _save_governance() -> void:
    if governance == null:
        return
    var gateway = _gateway()
    var payload := {
        "schema_version": 1,
        "core_turn": int(gateway.snapshot().get("turn", 1)) if gateway != null else last_core_turn,
        "player_country_id": _current_country_id(),
        "governance": governance.snapshot(),
    }
    var file := FileAccess.open(GOVERNANCE_SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_error("IntegratedMain: 통치 자동 저장 파일을 열 수 없습니다.")
        return
    file.store_string(JSON.stringify(payload, "\t"))
    if setup_complete:
        _notify_base("통치 상태를 저장했습니다.", "success")


func _gateway():
    if base_ui == null:
        return null
    return base_ui.get("gateway")


func _current_country_id() -> String:
    if base_ui != null:
        var selected := String(base_ui.get("selected_country"))
        if selected != "":
            return selected
    var gateway = _gateway()
    return String(gateway.snapshot().get("player_country_id", "")) if gateway != null else ""


func _current_province_id() -> int:
    return int(base_ui.get("selected_province")) if base_ui != null else -1


func _country_name(country_id: String) -> String:
    var gateway = _gateway()
    if gateway == null:
        return country_id
    return String(gateway.country(country_id).get("name", country_id))


func _country_at_war(country_id: String, core_snapshot: Dictionary) -> bool:
    for war_value in core_snapshot.get("wars", []):
        if war_value is not Dictionary:
            continue
        var war: Dictionary = war_value
        if String(war.get("attacker", "")) == country_id or String(war.get("defender", "")) == country_id:
            return true
    return false


func _army_total_for_country(country_id: String, core_snapshot: Dictionary) -> int:
    var total := 0
    var armies: Dictionary = core_snapshot.get("armies", {})
    for province_id_value in core_snapshot.get("provinces", {}).keys():
        var province: Dictionary = core_snapshot.provinces[province_id_value]
        if String(province.get("owner", "")) == country_id:
            total += int(armies.get(int(province_id_value), 0))
    return total


func _country_province_ids(country_id: String, core_snapshot: Dictionary) -> Array:
    var result: Array = []
    for province_id_value in core_snapshot.get("provinces", {}).keys():
        var province: Dictionary = core_snapshot.provinces[province_id_value]
        if String(province.get("owner", "")) == country_id:
            result.append(str(int(province_id_value)))
    return result


func _capital_is_occupied(country_id: String) -> bool:
    var gateway = _gateway()
    if gateway == null:
        return false
    var country: Dictionary = gateway.country(country_id)
    var capital_id := int(country.get("capital_province", -1))
    var province: Dictionary = gateway.province(capital_id)
    return String(province.get("controller", country_id)) != country_id


func _parent_state_is_weak(country_id: String, core_snapshot: Dictionary) -> bool:
    var country: Dictionary = core_snapshot.get("countries", {}).get(country_id, {})
    return float(country.get("stability", 50.0)) < 42.0 or float(country.get("war_exhaustion", 0.0)) > 60.0


func _historical_state_candidates(rebellion: Dictionary) -> Array:
    var group_type := String(rebellion.get("group_type", ""))
    return [
        {"type": "historical_regional_state", "name": "동방 연맹", "available": group_type == "local_populace"},
        {"type": "clan_or_tribal_state", "name": "대호족국", "available": group_type == "aristocracy"},
        {"type": "restored_dynasty", "name": "복고 왕조", "available": group_type == "bureaucracy"},
        {"type": "historical_capital_name", "name": "%s 정권" % rebellion.get("name", "신생"), "available": true},
    ]


func _group_opposes_reform(country_id: String, group_id: String) -> bool:
    return String(governance.political_groups.get(country_id, {}).get(group_id, {}).get("reform_stance", "neutral")) == "oppose"


func _has_multiple_dangerous_groups(country_id: String) -> bool:
    var count := 0
    for group_id_value in governance.political_groups.get(country_id, {}).keys():
        var detail: Dictionary = governance.group_detail(country_id, String(group_id_value))
        var risk_id := String(detail.get("rebellion_risk", {}).get("id", "stable"))
        if risk_id in ["danger", "imminent"]:
            count += 1
    return count >= 2


func _aristocracy_is_strong(country_id: String) -> bool:
    var detail: Dictionary = governance.group_detail(country_id, "aristocracy")
    return String(detail.get("influence", {}).get("id", "")) in ["strong", "overwhelming"]


func _governor_view(province: Dictionary) -> Dictionary:
    return {
        "name": province.get("governor_name", ""),
        "personality": province.get("governor_personality", "pragmatic"),
        "loyalty": province.get("governor_loyalty", 50.0),
        "ambition": province.get("governor_ambition", 50.0),
        "local_base": province.get("governor_administration", 50.0),
        "military": province.get("governor_military", 50.0),
    }


func _strategic_points(province_id: int, province: Dictionary) -> Array:
    var name := String(province.get("name", "Province %d" % province_id))
    var terrain := String(province.get("terrain", "plains"))
    var points := [
        "%s 중심 도시" % name,
        "%s 관아" % name,
        "%s 시장" % name,
        "%s 도로 교차점" % name,
        "%s 농업 거점" % name,
    ]
    if int(province.get("fort", 0)) > 0:
        points.append("%s 요새" % name)
    elif terrain == "hills":
        points.append("%s 산길" % name)
    elif terrain == "coast":
        points.append("%s 항구" % name)
    else:
        points.append("%s 촌락" % name)
    return points


func _fallback_governor(province_id: int) -> Dictionary:
    var names := ["유진", "장휘", "서림", "고연", "탁무", "한도", "해윤", "문규", "노진"]
    return {
        "character_id": "GOV_%02d" % province_id,
        "name": names[(province_id - 1) % names.size()],
        "governor_type": "appointed_governor",
        "personality": "pragmatic",
        "loyalty": 58 + (province_id * 7) % 24,
        "ambition": 30 + (province_id * 11) % 45,
        "administration": 45 + (province_id * 9) % 35,
        "military": 38 + (province_id * 13) % 42,
    }


func _map_government(core_government: String) -> String:
    return {
        "monarchy": "feudal",
        "military_monarchy": "military_governorate",
        "republic": "aristocratic_council",
    }.get(core_government, "tribal_confederation")


func _technology_tags(level: int) -> Array:
    var tags: Array = ["council_law", "land_grants"]
    if level >= 2:
        tags.append_array(["frontier_command", "household_register", "land_survey", "central_law"])
    if level >= 3:
        tags.append_array(["imperial_bureaucracy", "standardized_law", "national_census"])
    return tags


func _default_group_influence(group_id: String, country: Dictionary) -> float:
    var government := String(country.get("government", ""))
    match group_id:
        "aristocracy":
            return 68.0 if government in ["monarchy", "military_monarchy"] else 55.0
        "military":
            return 72.0 if government == "military_monarchy" else 52.0
        "bureaucracy":
            return 66.0 if government == "republic" else 48.0
        "religious_estate":
            return 42.0
        "local_populace":
            return 64.0
    return 50.0


func _default_group_satisfaction(group_id: String, country: Dictionary) -> float:
    var stability := float(country.get("stability", 55.0))
    match group_id:
        "military":
            return clampf(stability - float(country.get("war_exhaustion", 0.0)) * 0.2, 0.0, 100.0)
        "local_populace":
            return clampf(stability - maxf(float(country.get("tax_rate", 0.24)) - 0.24, 0.0) * 120.0, 0.0, 100.0)
    return clampf(stability, 0.0, 100.0)


func _default_mobilization(group_id: String) -> float:
    return {
        "aristocracy": 62.0,
        "military": 72.0,
        "bureaucracy": 36.0,
        "religious_estate": 48.0,
        "local_populace": 58.0,
    }.get(group_id, 45.0)


func _default_demands(group_id: String) -> Array:
    return {
        "aristocracy": ["세습권 보장", "사병 유지", "고위 관직"],
        "military": ["군권 보장", "봉급 지급", "전공에 따른 승진"],
        "bureaucracy": ["행정 안정", "명확한 임용·승진 기준", "법령 정비"],
        "religious_estate": ["의례 보장", "종교 재산 보호", "종교 지도자 지위"],
        "local_populace": ["감세", "부역 완화", "식량과 치안"],
    }.get(group_id, [])


func _risk_color(risk_name: String) -> Color:
    return {
        "안정": Color("#78b990"),
        "주의": Color("#c2b46f"),
        "불안": Color("#d49b67"),
        "위험": Color("#dc796b"),
        "임박": Color("#ef5f5f"),
    }.get(risk_name, Color.WHITE)


func _stance_name(stance: String) -> String:
    return {"support": "지지", "oppose": "반대", "neutral": "중립"}.get(stance, stance)


func _response_name(response_id: String) -> String:
    return {"negotiate": "협상", "bribe": "매수", "purge": "숙청", "suppress": "군사 진압"}.get(response_id, response_id)


func _governor_type_name(governor_type: String) -> String:
    return {
        "appointed_governor": "중앙 임명 지방관",
        "hereditary_lord": "세습 영주·호족",
        "royal_feudal_lord": "왕족 봉건 영주",
        "military_governor": "군사 총독",
        "tribal_leader": "부족 지도자",
        "religious_leader": "종교 지도자",
    }.get(governor_type, governor_type)


func _governor_decision_name(decision: String) -> String:
    return {
        "surrender": "항복",
        "conditional_surrender": "조건부 항복",
        "request_vassalage": "봉신 편입 요청",
        "seek_armistice": "휴전 모색",
        "flee": "도주",
        "resist": "끝까지 저항",
        "request_relief": "구원 요청",
        "hold": "현 위치 사수",
    }.get(decision, decision)


func _trait_stage(value: float) -> String:
    if value >= 80.0:
        return "매우 높음"
    if value >= 60.0:
        return "높음"
    if value >= 40.0:
        return "보통"
    if value >= 20.0:
        return "낮음"
    return "매우 낮음"


func _rebellion_status_name(status: String) -> String:
    return {"active": "반란 점령지", "declared_state": "정식 국가 선포", "defeated": "진압됨"}.get(status, status)


func _negotiation_stage_name(stage: String) -> String:
    return {"opening": "협상 개시", "demands": "핵심 요구", "counteroffer": "수정안", "final_agreement": "최종 합의"}.get(stage, stage)


func _notify_base(message: String, kind: String = "info") -> void:
    if base_ui != null and base_ui.has_method("_notify"):
        base_ui.call("_notify", message, kind)


func _load_json(path: String):
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Dictionary else {}


func _label(text_value: String, font_size: int = 14, color: Color = Color.WHITE) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _button(text_value: String, callback: Callable, variant: String = "default", height: int = 40) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size.y = height
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.pressed.connect(callback)
    if variant == "primary":
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#6f5935")
        style.border_color = Color("#d0b06a")
        style.set_border_width_all(1)
        style.set_corner_radius_all(6)
        button.add_theme_stylebox_override("normal", style)
    elif variant == "danger":
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#573238")
        style.border_color = Color("#bd6d69")
        style.set_border_width_all(1)
        style.set_corner_radius_all(6)
        button.add_theme_stylebox_override("normal", style)
    elif variant == "list":
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    return button
