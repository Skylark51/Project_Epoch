extends Control

const GOVERNANCE_SESSION_SCRIPT := preload("res://src/governance/governance_session.gd")
const SEED_PATH := "res://data/governance/sample_governance_state.json"
const GOVERNANCE_DATA_VERSION := 1
const GAME_SCREEN_STATE := 3

var base_ui: Control
var governance
var launcher: Button
var badge: Label
var dashboard: Window
var dashboard_title: Label
var tabs: TabContainer
var overview_text: RichTextLabel
var group_list: VBoxContainer
var group_detail: RichTextLabel
var reform_text: RichTextLabel
var reform_selector: OptionButton
var reform_status: Label
var rebellion_text: RichTextLabel
var province_text: RichTextLabel
var history_text: RichTextLabel

var selected_group_id := "aristocracy"
var last_core_turn := -1
var last_country_id := ""
var last_province_id := -1
var setup_complete := false


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    base_ui = get_parent() as Control
    set_process(false)
    call_deferred("_setup_integration")


func _setup_integration() -> void:
    governance = GOVERNANCE_SESSION_SCRIPT.new()
    governance.governance_changed.connect(_on_governance_changed)
    governance.governance_alert.connect(_on_governance_alert)
    governance.rebellion_started.connect(_on_rebellion_started)
    governance.reform_changed.connect(_on_reform_changed)
    governance.negotiation_changed.connect(_on_negotiation_changed)
    _build_overlay()

    var gateway = _gateway()
    if gateway == null:
        push_error("GovernanceDashboard: StrategyGateway를 찾지 못했습니다.")
        return
    gateway.snapshot_changed.connect(_on_core_snapshot)
    gateway.new_game_started.connect(_on_new_game_started)
    gateway.autosave_loaded.connect(_on_autosave_loaded)

    var snapshot: Dictionary = gateway.snapshot()
    _seed_governance(snapshot)
    _sync_from_core(snapshot)
    last_core_turn = int(snapshot.get("turn", 1))
    last_country_id = String(snapshot.get("player_country_id", ""))
    setup_complete = true
    _save_governance(false)
    _refresh_all()
    set_process(true)


func _process(_delta: float) -> void:
    if not setup_complete:
        return
    var in_game := int(base_ui.get("state")) == GAME_SCREEN_STATE
    launcher.visible = in_game
    badge.visible = in_game
    var country_id := _current_country_id()
    var province_id := _current_province_id()
    if country_id != last_country_id or province_id != last_province_id:
        last_country_id = country_id
        last_province_id = province_id
        _refresh_badge()
        if dashboard.visible:
            _refresh_all()


func _build_overlay() -> void:
    var host: Node = self
    var base_ui_refs = base_ui.get("ui")
    if base_ui_refs is Dictionary and base_ui_refs.has("governance_slot"):
        var slot_value = base_ui_refs.get("governance_slot")
        if slot_value is Container:
            host = slot_value
    launcher = Button.new()
    launcher.name = "GovernanceLauncher"
    launcher.text = "⚖ 통치 · 반란"
    launcher.custom_minimum_size.y = 40.0
    launcher.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    launcher.z_index = 250
    launcher.visible = false
    launcher.pressed.connect(_open_dashboard)
    host.add_child(launcher)

    badge = Label.new()
    badge.name = "GovernanceStatusBadge"
    badge.custom_minimum_size.y = 24.0
    badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.z_index = 251
    badge.visible = false
    host.add_child(badge)

    dashboard = Window.new()
    dashboard.name = "GovernanceDashboard"
    dashboard.title = "통치 · 개혁 · 정치집단 · 반란"
    dashboard.size = Vector2i(1060, 740)
    dashboard.min_size = Vector2i(860, 620)
    dashboard.exclusive = true
    dashboard.visible = false
    dashboard.close_requested.connect(func(): dashboard.hide())
    add_child(dashboard)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 16)
    margin.add_theme_constant_override("margin_right", 16)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    dashboard.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    margin.add_child(root)

    var header := HBoxContainer.new()
    dashboard_title = _label("국가 통치 현황", 23, Color("#e1c77f"))
    header.add_child(dashboard_title)
    header.add_spacer(true)
    header.add_child(_button("저장", func(): _save_governance(true), "primary"))
    header.add_child(_button("새로고침", _refresh_all))
    header.add_child(_button("닫기", func(): dashboard.hide()))
    root.add_child(header)

    tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(tabs)

    overview_text = _tab_text("국가 개요")
    tabs.add_child(overview_text)

    var groups := HSplitContainer.new()
    groups.name = "정치 집단"
    groups.split_offset = 350
    group_list = VBoxContainer.new()
    group_list.custom_minimum_size.x = 330
    group_list.add_theme_constant_override("separation", 6)
    var group_scroll := ScrollContainer.new()
    group_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    group_scroll.add_child(group_list)
    groups.add_child(group_scroll)
    group_detail = RichTextLabel.new()
    group_detail.bbcode_enabled = true
    group_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    group_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    groups.add_child(group_detail)
    tabs.add_child(groups)

    var reform_root := VBoxContainer.new()
    reform_root.name = "통치체제 개혁"
    reform_root.add_theme_constant_override("separation", 8)
    reform_text = RichTextLabel.new()
    reform_text.bbcode_enabled = true
    reform_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    reform_root.add_child(reform_text)
    var reform_row := HBoxContainer.new()
    reform_selector = OptionButton.new()
    reform_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reform_row.add_child(reform_selector)
    reform_row.add_child(_button("개혁 시작", _start_reform, "primary"))
    reform_root.add_child(reform_row)
    reform_status = _label("개혁 대상과 대응 방식을 선택합니다.", 12, Color("#9da9ad"))
    reform_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    reform_root.add_child(reform_status)
    var response_row := GridContainer.new()
    response_row.columns = 4
    response_row.add_child(_button("협상", _respond_reform.bind("negotiate"), "list"))
    response_row.add_child(_button("매수", _respond_reform.bind("bribe"), "list"))
    response_row.add_child(_button("숙청", _respond_reform.bind("purge"), "danger"))
    response_row.add_child(_button("군사 진압", _respond_reform.bind("suppress"), "danger"))
    reform_root.add_child(response_row)
    tabs.add_child(reform_root)

    rebellion_text = _tab_text("반란 · 독립협상")
    tabs.add_child(rebellion_text)
    province_text = _tab_text("프로빈스 통치")
    tabs.add_child(province_text)
    history_text = _tab_text("통치 기록")
    tabs.add_child(history_text)


func _tab_text(tab_name: String) -> RichTextLabel:
    var text := RichTextLabel.new()
    text.name = tab_name
    text.bbcode_enabled = true
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    return text


func _restore_governance(core_snapshot: Dictionary, envelope: Dictionary) -> bool:
    if int(envelope.get("data_version", -1)) != GOVERNANCE_DATA_VERSION:
        push_error("GovernanceDashboard: 지원하지 않는 통치 저장 버전입니다.")
        return false
    if int(envelope.get("core_turn", -1)) != int(core_snapshot.get("turn", 1)):
        push_error("GovernanceDashboard: 코어 턴과 통치 저장 턴이 일치하지 않습니다.")
        return false
    var state: Dictionary = envelope.get("state", {})
    if state.is_empty():
        push_error("GovernanceDashboard: 통치 저장 상태가 비어 있습니다.")
        return false
    governance.turn = int(state.get("turn", 0))
    governance.factions = state.get("factions", {}).duplicate(true)
    governance.provinces = state.get("provinces", {}).duplicate(true)
    governance.political_groups = state.get("political_groups", {}).duplicate(true)
    governance.rebellions = state.get("rebellions", {}).duplicate(true)
    governance.negotiations = state.get("negotiations", {}).duplicate(true)
    governance.alerts.clear()
    for alert in state.get("alerts", []):
        if alert is Dictionary:
            governance.alerts.append(alert.duplicate(true))
    return true

func _seed_governance(core_snapshot: Dictionary) -> void:
    governance.turn = 0
    governance.factions.clear()
    governance.provinces.clear()
    governance.political_groups.clear()
    governance.rebellions.clear()
    governance.negotiations.clear()
    governance.alerts.clear()

    var seed_value = _load_json(SEED_PATH)
    var seed: Dictionary = seed_value if seed_value is Dictionary else {}
    var faction_seed: Dictionary = seed.get("factions", {})
    var governor_seed: Dictionary = seed.get("governors", {})

    for country_id_value in core_snapshot.get("countries", {}).keys():
        var country_id := String(country_id_value)
        var country: Dictionary = core_snapshot.get("countries", {}).get(country_id_value, {})
        var preset: Dictionary = faction_seed.get(country_id, {})
        var administration_level := int(country.get("technology", {}).get("administration", 1))
        governance.register_faction({
            "faction_id": country_id,
            "name": country.get("name", country_id),
            "government_type": preset.get("government_type", _map_government(String(country.get("government", "")))),
            "authority_hidden": float(preset.get("authority_hidden", country.get("authority_hidden", country.get("stability", 55.0)))),
            "legitimacy_hidden": float(preset.get("legitimacy_hidden", country.get("legitimacy_hidden", country.get("stability", 55.0)))),
            "corruption_hidden": float(preset.get("corruption_hidden", 15.0)),
            "administration_capacity": int(preset.get("administration_capacity", country.get("administration_capacity", 20 + administration_level * 18))),
            "treasury": int(country.get("treasury", 0)),
            "technology_tags": preset.get("technology_tags", country.get("technology_tags", _technology_tags(administration_level))),
            "active_reform": {},
            "reform_stage": "none",
        })
        var preset_groups: Dictionary = preset.get("groups", {})
        var runtime_groups := {}
        for runtime_group_value in country.get("governance_groups", []):
            if runtime_group_value is Dictionary:
                runtime_groups[String(runtime_group_value.get("group_type", ""))] = runtime_group_value
        for definition_value in governance.definitions.get("groups", {}).get("groups", []):
            if definition_value is not Dictionary:
                continue
            var definition: Dictionary = definition_value
            var group_id := String(definition.get("id", ""))
            var group_preset: Dictionary = preset_groups.get(group_id, runtime_groups.get(group_id, {}))
            governance.register_group(country_id, {
                "group_id": group_id,
                "group_type": group_id,
                "name": group_preset.get("name", definition.get("name", group_id)),
                "interests": definition.get("interests", []).duplicate(true),
                "influence_hidden": float(group_preset.get("influence_hidden", _default_influence(group_id, country))),
                "satisfaction_hidden": float(group_preset.get("satisfaction_hidden", country.get("stability", 55.0))),
                "rebellion_risk_hidden": float(group_preset.get("rebellion_risk_hidden", 12.0)),
                "mobilization_capacity": float(group_preset.get("mobilization_capacity", _default_mobilization(group_id))),
                "demands": group_preset.get("demands", _default_demands(group_id)).duplicate(true),
                "reform_stance": group_preset.get("reform_stance", "neutral"),
                "active_causes": group_preset.get("active_causes", []).duplicate(true),
                "recent_modifiers": [],
                "representative_character_id": group_preset.get("representative_character_id", "REP_%s_%s" % [country_id, group_id.to_upper()]),
            })

    for province_id_value in core_snapshot.get("provinces", {}).keys():
        var province_id := int(province_id_value)
        var province: Dictionary = core_snapshot.get("provinces", {}).get(province_id_value, {})
        var governor: Dictionary = governor_seed.get(str(province_id), _fallback_governor(province_id))
        if province.has("governor_name"):
            governor = {
                "character_id": province.get("governor_character_id", "GOV_%02d" % province_id),
                "name": province.get("governor_name", "지방관"),
                "governor_type": province.get("governor_type", "appointed_governor"),
                "personality": province.get("governor_personality", "pragmatic"),
                "loyalty": province.get("governor_loyalty", 60.0),
                "ambition": province.get("governor_ambition", 40.0),
                "administration": province.get("governor_administration", 50.0),
                "military": province.get("governor_military", 45.0),
            }
        var owner_id := String(province.get("owner", ""))
        var controller_id := String(province.get("controller", owner_id))
        governance.register_province({
            "province_id": str(province_id),
            "name": province.get("name", "Province %d" % province_id),
            "owner_faction_id": owner_id,
            "controller_faction_id": controller_id,
            "control_progress_hidden": 100.0 if owner_id == controller_id else 65.0,
            "governor_character_id": governor.get("character_id", "GOV_%02d" % province_id),
            "governor_name": governor.get("name", "지방관"),
            "governor_type": governor.get("governor_type", "appointed_governor"),
            "governor_personality": governor.get("personality", "pragmatic"),
            "governor_loyalty": float(governor.get("loyalty", 60.0)),
            "governor_ambition": float(governor.get("ambition", 40.0)),
            "governor_administration": float(governor.get("administration", 50.0)),
            "governor_military": float(governor.get("military", 45.0)),
            "population": int(province.get("population", 0)),
            "strategic_point_ids": _strategic_points(province_id, province),
        })


func _sync_from_core(core_snapshot: Dictionary) -> void:
    for country_id_value in core_snapshot.get("countries", {}).keys():
        var country_id := String(country_id_value)
        if not governance.factions.has(country_id):
            continue
        var source: Dictionary = core_snapshot.get("countries", {}).get(country_id_value, {})
        var faction: Dictionary = governance.factions[country_id]
        faction["treasury"] = int(source.get("treasury", faction.get("treasury", 0)))
        governance.factions[country_id] = faction

    for province_id_value in core_snapshot.get("provinces", {}).keys():
        var key := str(int(province_id_value))
        if not governance.provinces.has(key):
            continue
        var source: Dictionary = core_snapshot.get("provinces", {}).get(province_id_value, {})
        var province: Dictionary = governance.provinces[key]
        var old_controller := String(province.get("controller_faction_id", ""))
        var owner_id := String(source.get("owner", ""))
        var controller_id := String(source.get("controller", owner_id))
        province["owner_faction_id"] = owner_id
        province["controller_faction_id"] = controller_id
        province["population"] = int(source.get("population", province.get("population", 0)))
        governance.provinces[key] = province
        if old_controller != controller_id:
            governance.update_province_control(key, {
                "military_presence": 25.0 if controller_id == owner_id else -25.0,
                "local_support": 8.0,
                "occupation_abuse": 5.0 if controller_id != owner_id else 0.0,
            }, _governor_view(province), {"enemy_pressure": controller_id != owner_id})


func _on_new_game_started(snapshot: Dictionary) -> void:
    if not setup_complete:
        return
    _seed_governance(snapshot)
    _sync_from_core(snapshot)
    last_core_turn = int(snapshot.get("turn", 1))
    last_country_id = String(snapshot.get("player_country_id", ""))
    last_province_id = -1
    _save_governance(false)
    _refresh_all()


func _on_autosave_loaded(snapshot: Dictionary) -> void:
    if not setup_complete:
        return
    var gateway = _gateway()
    var envelope: Dictionary = gateway.governance_save_data() if gateway != null else {}
    if not _restore_governance(snapshot, envelope):
        _seed_governance(snapshot)
        _notify_base("통치 상태가 없는 이전 세이브입니다. 현재 코어 상태에서 통치 데이터를 새로 만들었습니다.", "warning")
    _sync_from_core(snapshot)
    last_core_turn = int(snapshot.get("turn", 1))
    last_country_id = String(snapshot.get("player_country_id", ""))
    last_province_id = -1
    _save_governance(false)
    _refresh_all()

func _on_core_snapshot(snapshot: Dictionary) -> void:
    if not setup_complete:
        return
    var core_turn := int(snapshot.get("turn", 1))
    if core_turn < last_core_turn:
        _seed_governance(snapshot)
    elif core_turn > last_core_turn:
        for _step in range(core_turn - last_core_turn):
            governance.advance_turn(_turn_contexts(snapshot))
    last_core_turn = core_turn
    _sync_from_core(snapshot)
    _save_governance(false)
    _refresh_all()


func _turn_contexts(snapshot: Dictionary) -> Dictionary:
    var group_contexts := {}
    var reform_contexts := {}
    var coalition_contexts := {}
    var statehood_contexts := {}

    for country_id_value in snapshot.get("countries", {}).keys():
        var country_id := String(country_id_value)
        var country: Dictionary = snapshot.get("countries", {}).get(country_id_value, {})
        var stability := float(country.get("stability", 50.0))
        var exhaustion := float(country.get("war_exhaustion", 0.0))
        var treasury := float(country.get("treasury", 0.0))
        var at_war := _country_at_war(country_id, snapshot)
        var per_group := {}
        for group_id_value in governance.political_groups.get(country_id, {}).keys():
            var group_id := String(group_id_value)
            var delta := (stability - 55.0) * 0.035
            var causes: Array[String] = []
            var effects := {}
            if treasury < 80.0:
                delta -= 1.2
                causes.append("국고 부족")
            if exhaustion > 35.0:
                delta -= minf(exhaustion / 30.0, 3.0)
                causes.append("전쟁 피로")
            if group_id == "local_populace" and float(country.get("tax_rate", 0.24)) > 0.26:
                effects["tax"] = -3.0
                causes.append("높은 세금")
            if group_id == "military":
                effects["pay"] = -2.0 if treasury < 120.0 else 0.7
            if group_id == "aristocracy" and _opposes_reform(country_id, group_id):
                effects["hereditary_rights"] = -2.5
            per_group[group_id] = {
                "base_satisfaction_delta": delta,
                "policy_effects": effects,
                "foreign_war": at_war,
                "central_army_deterrence": minf(float(_army_total(country_id, snapshot)) / 800.0, 18.0),
                "central_control_deterrence": maxf(0.0, (stability - 30.0) * 0.18),
                "causes": causes,
                "gradual_change": true,
            }
        group_contexts[country_id] = per_group
        reform_contexts[country_id] = {
            "major_war": at_war and exhaustion > 45.0,
            "treasury_crisis": treasury < 50.0,
            "low_central_control": stability < 40.0,
        }
        var origin_ids := _country_province_ids(country_id, snapshot)
        coalition_contexts[country_id] = {
            "foreign_war": at_war,
            "capital_control_weak": stability < 38.0,
            "central_army_absent": _army_total(country_id, snapshot) < 1000,
            "major_defeat": exhaustion > 70.0,
            "secret_network": _dangerous_group_count(country_id) >= 2,
            "private_army": _aristocracy_strong(country_id),
            "secured_province": not origin_ids.is_empty() and stability < 45.0,
            "origin_province_ids": origin_ids,
            "secret_meetings": _dangerous_group_count(country_id) >= 2,
            "private_army_growth": _aristocracy_strong(country_id),
            "rumors": stability < 45.0,
            "incompatible_group_pairs": [["aristocracy", "local_populace"]] if stability >= 25.0 else [],
        }

    for rebellion_id_value in governance.rebellions.keys():
        var rebellion_id := String(rebellion_id_value)
        var rebellion: Dictionary = governance.rebellions[rebellion_id]
        var population := 0
        var centers: Array[Dictionary] = []
        for province_id_value in rebellion.get("occupied_province_ids", []):
            var province_id := int(String(province_id_value))
            var source: Dictionary = snapshot.get("provinces", {}).get(province_id, {})
            population += int(source.get("population", 0))
            if not source.is_empty():
                centers.append({
                    "id": str(province_id),
                    "name": source.get("name", str(province_id)),
                    "historical_center": bool(source.get("capital", false)),
                    "leader_home": true,
                    "former_capital": bool(source.get("capital", false)),
                    "defense": float(source.get("fort", 0)) * 20.0,
                    "logistics": float(source.get("economy", 0)),
                })
        statehood_contexts[rebellion_id] = {
            "controlled_population": population,
            "parent_state_weak": _parent_weak(String(rebellion.get("parent_faction_id", "")), snapshot),
            "historical_candidates": _state_candidates(rebellion),
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
    _refresh_history()


func _refresh_badge() -> void:
    var risk_names := ["안정", "주의", "불안", "위험", "임박"]
    var highest := 0
    for group_id_value in governance.political_groups.get(_current_country_id(), {}).keys():
        var detail: Dictionary = governance.group_detail(_current_country_id(), String(group_id_value))
        var name := String(detail.get("rebellion_risk", {}).get("name", "안정"))
        highest = maxi(highest, risk_names.find(name))
    badge.text = risk_names[highest]
    badge.add_theme_color_override("font_color", _risk_color(risk_names[highest]))


func _refresh_overview() -> void:
    var country_id := _current_country_id()
    var faction: Dictionary = governance.factions.get(country_id, {})
    var government: Dictionary = governance.government_definition(String(faction.get("government_type", "")))
    var authority := EpochStageScale.stage_name(float(faction.get("authority_hidden", 0.0)), EpochStageScale.INFLUENCE)
    var legitimacy := EpochStageScale.stage_name(float(faction.get("legitimacy_hidden", 0.0)), EpochStageScale.INFLUENCE)
    var reform_line := "진행 중인 개혁 없음"
    var reform: Dictionary = faction.get("active_reform", {})
    if not reform.is_empty() and bool(reform.get("is_active", false)):
        var view: Dictionary = governance.reform_system.stage_view(reform)
        var target: Dictionary = governance.government_definition(String(reform.get("target_government_id", "")))
        reform_line = "%s · %s · %s" % [target.get("name", "새 체제"), view.get("stage_name", ""), view.get("progress_stage", {}).get("name", "")]
    dashboard_title.text = "%s · 국가 통치 현황" % _country_name(country_id)
    overview_text.text = "[font_size=26][color=#e2ca82]%s[/color][/font_size]\n\n기본 통치체제  [b]%s[/b]\n군주 권위  [b]%s[/b]\n정통성  [b]%s[/b]\n행정 역량  [b]%d[/b]\n통치 재정  [b]%d[/b]\n개혁 상태  [b]%s[/b]\n통치 시스템 턴  [b]%d[/b]\n\n[color=#d5b76d]운영 원칙[/color]\n• 국가는 하나의 기본 통치체제를 유지합니다.\n• 개혁은 준비 → 시행 → 정착의 3단계입니다.\n• 정치 집단의 태도는 턴마다 점진적으로 변합니다.\n• 공동반란은 복수 집단·공통 명분·국가 위기·거점을 모두 요구합니다." % [_country_name(country_id), government.get("name", faction.get("government_type", "미정")), authority, legitimacy, int(faction.get("administration_capacity", 0)), int(faction.get("treasury", 0)), reform_line, int(governance.turn)]


func _refresh_groups() -> void:
    for child in group_list.get_children():
        child.queue_free()
    var country_id := _current_country_id()
    var groups: Dictionary = governance.political_groups.get(country_id, {})
    if groups.is_empty():
        group_detail.text = "등록된 정치 집단이 없습니다."
        return
    if not groups.has(selected_group_id):
        selected_group_id = String(groups.keys()[0])
    for group_id_value in groups.keys():
        var group_id := String(group_id_value)
        var detail: Dictionary = governance.group_detail(country_id, group_id)
        var caption := "%s\n영향력 %s · 만족도 %s · 반란 %s" % [detail.get("name", group_id), detail.get("influence", {}).get("name", ""), detail.get("satisfaction", {}).get("name", ""), detail.get("rebellion_risk", {}).get("name", "")]
        group_list.add_child(_button(caption, _select_group.bind(group_id), "primary" if group_id == selected_group_id else "list", 62))
    _refresh_group_detail()


func _select_group(group_id: String) -> void:
    selected_group_id = group_id
    _refresh_groups()


func _refresh_group_detail() -> void:
    var detail: Dictionary = governance.group_detail(_current_country_id(), selected_group_id)
    if detail.is_empty():
        group_detail.text = ""
        return
    var demands := _join_array(detail.get("demands", []), "\n• ")
    var records := PackedStringArray()
    for item_value in detail.get("recent_modifiers", []):
        if item_value is Dictionary:
            var item: Dictionary = item_value
            records.append("• %s턴 · 만족도 %+.1f · 위험 %+.1f · %s" % [str(item.get("turn", "?")), float(item.get("satisfaction_delta", item.get("delta", 0.0))), float(item.get("risk_delta", 0.0)), _join_array(item.get("causes", []), ", ") if not item.get("causes", []).is_empty() else "특이사항 없음"])
    group_detail.text = "[font_size=24][color=#e0c77e]%s[/color][/font_size]\n\n영향력  [b]%s[/b]\n만족도  [b]%s[/b]\n반란 위험  [b]%s[/b]\n다음 단계 근접도  [b]%s[/b]\n추세  [b]%s[/b]\n개혁 태도  [b]%s[/b]\n\n[color=#d3b468]현재 요구[/color]\n• %s\n\n[color=#d3b468]최근 10턴 기록[/color]\n%s" % [detail.get("name", selected_group_id), detail.get("influence", {}).get("name", ""), detail.get("satisfaction", {}).get("name", ""), detail.get("rebellion_risk", {}).get("name", ""), detail.get("proximity", {}).get("name", ""), detail.get("trend", "유지"), _stance_name(String(detail.get("reform_stance", "neutral"))), demands if demands != "" else "요구 없음", "\n".join(records) if not records.is_empty() else "기록 없음"]


func _refresh_reform() -> void:
    var country_id := _current_country_id()
    var faction: Dictionary = governance.factions.get(country_id, {})
    var current: Dictionary = governance.government_definition(String(faction.get("government_type", "")))
    reform_selector.clear()
    for definition_value in governance.definitions.get("governments", {}).get("government_types", []):
        if definition_value is Dictionary:
            var definition: Dictionary = definition_value
            reform_selector.add_item(String(definition.get("name", definition.get("id", ""))))
            reform_selector.set_item_metadata(reform_selector.item_count - 1, String(definition.get("id", "")))
    var active_line := "진행 중인 개혁이 없습니다."
    var active: Dictionary = faction.get("active_reform", {})
    if not active.is_empty() and bool(active.get("is_active", false)):
        var view: Dictionary = governance.reform_system.stage_view(active)
        var target: Dictionary = governance.government_definition(String(active.get("target_government_id", "")))
        active_line = "[b]%s[/b] 전환\n현재 단계: [b]%s[/b]\n단계 진행: [b]%s[/b]\n단계 체류: [b]%d턴[/b]\n지지 집단: %s\n반대 집단: %s" % [target.get("name", "새 체제"), view.get("stage_name", ""), view.get("progress_stage", {}).get("name", ""), int(view.get("turns_in_stage", 0)), _join_array(active.get("support_group_ids", []), ", ") if not active.get("support_group_ids", []).is_empty() else "없음", _join_array(active.get("opposition_group_ids", []), ", ") if not active.get("opposition_group_ids", []).is_empty() else "없음"]
    reform_text.text = "[font_size=24][color=#dfc57a]통치체제 개혁[/color][/font_size]\n\n현재 체제  [b]%s[/b]\n\n%s\n\n[color=#9da9ad]개혁 시작 조건은 권위, 행정 역량, 재정, 기술과 수도 상태를 함께 검사합니다.[/color]" % [current.get("name", "미정"), active_line]


func _start_reform() -> void:
    if reform_selector.item_count == 0:
        return
    var country_id := _current_country_id()
    var target_id := String(reform_selector.get_item_metadata(reform_selector.selected))
    var result: Dictionary = governance.start_reform(country_id, target_id, {"capital_occupied": _capital_occupied(country_id), "succession_crisis": false})
    if bool(result.get("accepted", false)):
        _set_reform_stances(country_id, target_id)
        reform_status.text = "개혁을 시작했습니다."
        _notify_base(reform_status.text, "success")
        _save_governance(false)
        _refresh_all()
    else:
        var reasons: Array = result.get("reasons", [])
        reform_status.text = "개혁 시작 불가: %s" % (_join_array(reasons, ", ") if not reasons.is_empty() else String(result.get("reason", "조건 미충족")))
        _notify_base(reform_status.text, "warning")


func _set_reform_stances(country_id: String, target_id: String) -> void:
    var stances := {"aristocracy": "neutral", "military": "neutral", "bureaucracy": "neutral", "religious_estate": "neutral", "local_populace": "neutral"}
    if target_id in ["commandery_county", "autocratic_bureaucracy"]:
        stances["aristocracy"] = "oppose"
        stances["bureaucracy"] = "support"
        stances["local_populace"] = "support"
    elif target_id in ["feudal", "aristocratic_council"]:
        stances["aristocracy"] = "support"
        stances["bureaucracy"] = "oppose"
        stances["local_populace"] = "oppose"
    elif target_id == "military_governorate":
        stances["military"] = "support"
        stances["bureaucracy"] = "oppose"
        stances["local_populace"] = "oppose"
    for group_id_value in stances.keys():
        var group_id := String(group_id_value)
        if governance.political_groups.get(country_id, {}).has(group_id):
            var group: Dictionary = governance.political_groups[country_id][group_id]
            group["reform_stance"] = stances[group_id]
            group["active_causes"] = ["통치체제 개혁"] if stances[group_id] == "oppose" else []
            governance.political_groups[country_id][group_id] = group


func _respond_reform(response_id: String) -> void:
    var country_id := _current_country_id()
    var target_group := selected_group_id if _opposes_reform(country_id, selected_group_id) else ""
    var result: Dictionary = governance.respond_to_reform_opposition(country_id, response_id, target_group)
    if bool(result.get("accepted", false)):
        reform_status.text = "'%s' 대응을 적용했습니다." % _response_name(response_id)
        _notify_base(reform_status.text, "success")
        _save_governance(false)
        _refresh_all()
    else:
        reform_status.text = String(result.get("reason", "대응 실패"))
        _notify_base(reform_status.text, "warning")


func _refresh_rebellions() -> void:
    var country_id := _current_country_id()
    var lines := PackedStringArray(["[font_size=24][color=#dfc57a]반란 · 독립협상[/color][/font_size]", ""])
    var count := 0
    for value in governance.rebellions.values():
        if value is Dictionary:
            var rebellion: Dictionary = value
            if String(rebellion.get("parent_faction_id", "")) == country_id:
                count += 1
                lines.append("[b]%s[/b] · %s" % [rebellion.get("name", rebellion.get("rebellion_id", "")), _rebellion_status(String(rebellion.get("status", "active")))])
                lines.append("목표 %s · 병력 %d · 식량 %d · 생존 %d턴" % [rebellion.get("goal", ""), int(rebellion.get("troops", 0)), int(rebellion.get("food", 0)), int(rebellion.get("turns_survived", 0))])
                lines.append("점령지 %s · 국가 선포 진행 %d%%" % [_join_array(rebellion.get("occupied_province_ids", []), ", ") if not rebellion.get("occupied_province_ids", []).is_empty() else "없음", int(float(rebellion.get("statehood_progress", 0.0)))])
                if String(rebellion.get("declared_state_name", "")) != "":
                    lines.append("선포 국호 [b]%s[/b] · 수도 %s" % [rebellion.get("declared_state_name", ""), rebellion.get("capital_id", "")])
                lines.append("")
    if count == 0:
        lines.append("[color=#8e9da2]현재 활동 중인 반란 세력이 없습니다.[/color]")
        lines.append("공동반란은 복수 불만 집단, 강한 영향력, 공통 명분, 국가 위기, 거점을 모두 요구합니다.")
    lines.append("")
    lines.append("[color=#d3b468]진행 중인 독립 협상[/color]")
    var negotiation_count := 0
    for value in governance.negotiations.values():
        if value is Dictionary:
            var negotiation: Dictionary = value
            if String(negotiation.get("initiator_id", "")) == country_id or String(negotiation.get("counterpart_id", "")) == country_id:
                negotiation_count += 1
                lines.append("• %s · %s · %s" % [negotiation.get("negotiation_id", ""), _negotiation_stage(String(negotiation.get("stage", "opening"))), negotiation.get("status", "active")])
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
    province_text.text = "[font_size=24][color=#dfc57a]%s[/color][/font_size]\n\n정치적 소유국  [b]%s[/b]\n군사적 통제국  [b]%s[/b]\n통제율 단계  [b]%s[/b]\n지방 통치자  [b]%s[/b]\n통치자 유형  [b]%s[/b]\n충성도 경향  [b]%s[/b]\n야망 경향  [b]%s[/b]\n최근 판단  [b]%s[/b]\n\n[color=#d3b468]핵심 지점 %d개[/color]\n• %s\n\n[color=#9da9ad]중심 도시를 점령하더라도 군사 통제율과 통치자의 결정을 거쳐야 정치적 귀속이 확정됩니다.[/color]" % [province.get("name", str(province_id)), _country_name(String(province.get("owner_faction_id", ""))), _country_name(String(province.get("controller_faction_id", ""))), control_name, province.get("governor_name", province.get("governor_character_id", "")), _governor_type(String(province.get("governor_type", ""))), _trait_stage(float(province.get("governor_loyalty", 50.0))), _trait_stage(float(province.get("governor_ambition", 50.0))), _governor_decision(String(province.get("governor_decision", "hold"))), province.get("strategic_point_ids", []).size(), _join_array(province.get("strategic_point_ids", []), "\n• ")]


func _refresh_history() -> void:
    var lines := PackedStringArray(["[font_size=24][color=#dfc57a]통치 기록[/color][/font_size]", ""])
    var start := maxi(0, governance.alerts.size() - 40)
    for index in range(start, governance.alerts.size()):
        var entry: Dictionary = governance.alerts[index]
        lines.append("[color=#89979c]%s턴[/color] [b][%s][/b] %s" % [str(entry.get("turn", "?")), entry.get("category", "일반"), entry.get("message", "")])
    if governance.alerts.is_empty():
        lines.append("기록 없음")
    history_text.text = "\n".join(lines)


func _on_governance_changed(_snapshot: Dictionary) -> void:
    if setup_complete:
        _refresh_badge()
        if dashboard.visible:
            _refresh_all()


func _on_governance_alert(alert: Dictionary) -> void:
    if not setup_complete:
        return
    var category := "반란" if String(alert.get("category", "")) in ["rebellion", "politics"] else "중요"
    if base_ui.has_method("_add_log"):
        base_ui.call("_add_log", category, String(alert.get("message", "")), "important")
    _notify_base(String(alert.get("message", "")), "warning" if String(alert.get("importance", "")) == "danger" else "info")


func _on_rebellion_started(items: Array) -> void:
    _save_governance(false)
    _notify_base("%d개 정치 집단이 별도 반란 세력으로 봉기했습니다." % items.size(), "warning")


func _on_reform_changed(_faction_id: String, _state: Dictionary) -> void:
    _save_governance(false)


func _on_negotiation_changed(_id: String, _state: Dictionary) -> void:
    _save_governance(false)


func _save_governance(show_notice: bool) -> void:
    if governance == null:
        return
    var gateway = _gateway()
    if gateway == null:
        push_error("GovernanceDashboard: 통합 저장을 담당할 StrategyGateway가 없습니다.")
        return
    gateway.set_governance_save_data({
        "data_version": GOVERNANCE_DATA_VERSION,
        "core_turn": int(gateway.snapshot().get("turn", last_core_turn)),
        "player_country_id": _current_country_id(),
        "state": governance.snapshot(),
    })
    if show_notice:
        var result: Dictionary = gateway.save_autosave()
        if bool(result.get("ok", false)):
            _notify_base("코어와 통치 상태를 함께 저장했습니다.", "success")
        else:
            var message := "통합 저장 실패: %s" % str(result.get("error", "알 수 없는 오류"))
            push_error("GovernanceDashboard: %s" % message)
            _notify_base(message, "error")

func _gateway():
    return base_ui.get("gateway") if base_ui != null else null


func _current_country_id() -> String:
    if base_ui != null and String(base_ui.get("selected_country")) != "":
        return String(base_ui.get("selected_country"))
    var gateway = _gateway()
    return String(gateway.snapshot().get("player_country_id", "")) if gateway != null else ""


func _current_province_id() -> int:
    return int(base_ui.get("selected_province")) if base_ui != null else -1


func _country_name(country_id: String) -> String:
    var gateway = _gateway()
    return String(gateway.country(country_id).get("name", country_id)) if gateway != null else country_id


func _country_at_war(country_id: String, snapshot: Dictionary) -> bool:
    for value in snapshot.get("wars", []):
        if value is Dictionary:
            var war: Dictionary = value
            if String(war.get("attacker", "")) == country_id or String(war.get("defender", "")) == country_id:
                return true
    return false


func _army_total(country_id: String, snapshot: Dictionary) -> int:
    var total := 0
    for province_id_value in snapshot.get("provinces", {}).keys():
        var province: Dictionary = snapshot.get("provinces", {}).get(province_id_value, {})
        if String(province.get("owner", "")) == country_id:
            total += int(snapshot.get("armies", {}).get(int(province_id_value), 0))
    return total


func _country_province_ids(country_id: String, snapshot: Dictionary) -> Array:
    var result: Array = []
    for province_id_value in snapshot.get("provinces", {}).keys():
        if String(snapshot.get("provinces", {}).get(province_id_value, {}).get("owner", "")) == country_id:
            result.append(str(int(province_id_value)))
    return result


func _capital_occupied(country_id: String) -> bool:
    var gateway = _gateway()
    if gateway == null:
        return false
    var capital_id := int(gateway.country(country_id).get("capital_province", -1))
    return String(gateway.province(capital_id).get("controller", country_id)) != country_id


func _parent_weak(country_id: String, snapshot: Dictionary) -> bool:
    var country: Dictionary = snapshot.get("countries", {}).get(country_id, {})
    return float(country.get("stability", 50.0)) < 42.0 or float(country.get("war_exhaustion", 0.0)) > 60.0


func _state_candidates(rebellion: Dictionary) -> Array:
    var group_type := String(rebellion.get("group_type", ""))
    return [{"type": "historical_regional_state", "name": "동방 연맹", "available": group_type == "local_populace"}, {"type": "clan_or_tribal_state", "name": "대호족국", "available": group_type == "aristocracy"}, {"type": "restored_dynasty", "name": "복고 왕조", "available": group_type == "bureaucracy"}, {"type": "historical_capital_name", "name": "%s 정권" % rebellion.get("name", "신생"), "available": true}]


func _dangerous_group_count(country_id: String) -> int:
    var count := 0
    for group_id_value in governance.political_groups.get(country_id, {}).keys():
        var id := String(governance.group_detail(country_id, String(group_id_value)).get("rebellion_risk", {}).get("id", "stable"))
        if id in ["danger", "imminent"]:
            count += 1
    return count


func _aristocracy_strong(country_id: String) -> bool:
    return String(governance.group_detail(country_id, "aristocracy").get("influence", {}).get("id", "")) in ["strong", "overwhelming"]


func _opposes_reform(country_id: String, group_id: String) -> bool:
    return String(governance.political_groups.get(country_id, {}).get(group_id, {}).get("reform_stance", "neutral")) == "oppose"


func _governor_view(province: Dictionary) -> Dictionary:
    return {"name": province.get("governor_name", ""), "personality": province.get("governor_personality", "pragmatic"), "loyalty": province.get("governor_loyalty", 50.0), "ambition": province.get("governor_ambition", 50.0), "local_base": province.get("governor_administration", 50.0), "military": province.get("governor_military", 50.0)}


func _strategic_points(province_id: int, province: Dictionary) -> Array:
    var runtime_names: Array = province.get("strategic_point_names", [])
    if not runtime_names.is_empty():
        return runtime_names.duplicate(true)
    var name := String(province.get("name", "Province %d" % province_id))
    var result := ["%s 중심 도시" % name, "%s 관아" % name, "%s 시장" % name, "%s 도로 교차점" % name, "%s 농업 거점" % name]
    if int(province.get("fort", 0)) > 0:
        result.append("%s 요새" % name)
    elif String(province.get("terrain", "")) == "coast":
        result.append("%s 항구" % name)
    elif String(province.get("terrain", "")) == "hills":
        result.append("%s 산길" % name)
    else:
        result.append("%s 촌락" % name)
    return result


func _fallback_governor(province_id: int) -> Dictionary:
    var names := ["유진", "장휘", "서림", "고연", "탁무", "한도", "해윤", "문규", "노진"]
    return {"character_id": "GOV_%02d" % province_id, "name": names[(province_id - 1) % names.size()], "governor_type": "appointed_governor", "personality": "pragmatic", "loyalty": 58 + (province_id * 7) % 24, "ambition": 30 + (province_id * 11) % 45, "administration": 45 + (province_id * 9) % 35, "military": 38 + (province_id * 13) % 42}


func _map_government(value: String) -> String:
    if value in ["tribal_confederation", "aristocratic_council", "feudal", "military_governorate", "commandery_county", "imperial_bureaucracy"]:
        return value
    return {"monarchy": "feudal", "military_monarchy": "military_governorate", "republic": "aristocratic_council"}.get(value, "tribal_confederation")


func _technology_tags(level: int) -> Array:
    var result: Array = ["council_law", "land_grants"]
    if level >= 2:
        result.append_array(["frontier_command", "household_register", "land_survey", "central_law"])
    if level >= 3:
        result.append_array(["imperial_bureaucracy", "standardized_law", "national_census"])
    return result


func _default_influence(group_id: String, country: Dictionary) -> float:
    var government := String(country.get("government", ""))
    if group_id == "aristocracy": return 68.0 if government in ["monarchy", "military_monarchy"] else 55.0
    if group_id == "military": return 72.0 if government == "military_monarchy" else 52.0
    if group_id == "bureaucracy": return 66.0 if government == "republic" else 48.0
    if group_id == "religious_estate": return 42.0
    if group_id == "local_populace": return 64.0
    return 50.0


func _default_mobilization(group_id: String) -> float:
    return {"aristocracy": 62.0, "military": 72.0, "bureaucracy": 36.0, "religious_estate": 48.0, "local_populace": 58.0}.get(group_id, 45.0)


func _default_demands(group_id: String) -> Array:
    return {"aristocracy": ["세습권 보장", "사병 유지", "고위 관직"], "military": ["군권 보장", "봉급 지급", "전공에 따른 승진"], "bureaucracy": ["행정 안정", "명확한 임용·승진 기준", "법령 정비"], "religious_estate": ["의례 보장", "종교 재산 보호", "종교 지도자 지위"], "local_populace": ["감세", "부역 완화", "식량과 치안"]}.get(group_id, [])


func _join_array(values: Array, separator: String) -> String:
    var strings := PackedStringArray()
    for value in values:
        strings.append(str(value))
    return separator.join(strings)


func _risk_color(value: String) -> Color:
    return {"안정": Color("#78b990"), "주의": Color("#c2b46f"), "불안": Color("#d49b67"), "위험": Color("#dc796b"), "임박": Color("#ef5f5f")}.get(value, Color.WHITE)


func _stance_name(value: String) -> String:
    return {"support": "지지", "oppose": "반대", "neutral": "중립"}.get(value, value)


func _response_name(value: String) -> String:
    return {"negotiate": "협상", "bribe": "매수", "purge": "숙청", "suppress": "군사 진압"}.get(value, value)


func _governor_type(value: String) -> String:
    return {"appointed_governor": "중앙 임명 지방관", "hereditary_lord": "세습 영주·호족", "royal_feudal_lord": "왕족 봉건 영주", "military_governor": "군사 총독", "tribal_leader": "부족 지도자", "religious_leader": "종교 지도자"}.get(value, value)


func _governor_decision(value: String) -> String:
    return {"surrender": "항복", "conditional_surrender": "조건부 항복", "request_vassalage": "봉신 편입 요청", "seek_armistice": "휴전 모색", "flee": "도주", "resist": "끝까지 저항", "request_relief": "구원 요청", "hold": "현 위치 사수"}.get(value, value)


func _trait_stage(value: float) -> String:
    if value >= 80.0: return "매우 높음"
    if value >= 60.0: return "높음"
    if value >= 40.0: return "보통"
    if value >= 20.0: return "낮음"
    return "매우 낮음"


func _rebellion_status(value: String) -> String:
    return {"active": "반란 점령지", "declared_state": "정식 국가 선포", "defeated": "진압됨"}.get(value, value)


func _negotiation_stage(value: String) -> String:
    return {"opening": "협상 개시", "demands": "핵심 요구", "counteroffer": "수정안", "final_agreement": "최종 합의"}.get(value, value)


func _notify_base(message: String, kind: String) -> void:
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


func _label(value: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _button(value: String, callback: Callable, variant: String = "default", height: int = 40) -> Button:
    var button := Button.new()
    button.text = value
    button.custom_minimum_size.y = height
    button.pressed.connect(callback)
    if variant == "primary":
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#6f5935")
        style.border_color = Color("#d0b06a")
        style.set_border_width_all(1)
        style.set_corner_radius_all(6)
        button.add_theme_stylebox_override("normal", style)
    elif variant == "danger":
        var danger_style := StyleBoxFlat.new()
        danger_style.bg_color = Color("#573238")
        danger_style.border_color = Color("#bd6d69")
        danger_style.set_border_width_all(1)
        danger_style.set_corner_radius_all(6)
        button.add_theme_stylebox_override("normal", danger_style)
    elif variant == "list":
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    return button
