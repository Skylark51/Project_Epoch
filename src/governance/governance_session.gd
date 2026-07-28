class_name GovernanceSession
extends RefCounted

signal governance_changed(snapshot: Dictionary)
signal governance_alert(alert: Dictionary)
signal reform_changed(faction_id: String, state: Dictionary)
signal rebellion_started(rebellions: Array)
signal negotiation_changed(negotiation_id: String, state: Dictionary)

const GOVERNMENT_PATH := "res://data/governance/government_types.json"
const GROUP_PATH := "res://data/governance/political_groups.json"
const CONTROL_PATH := "res://data/governance/province_control.json"
const REBELLION_PATH := "res://data/governance/rebellion_rules.json"

var stage_scale := EpochStageScale
var control_system := ProvinceControlSystem.new()
var reform_system := GovernanceReformSystem.new()
var rebellion_system := RebellionSystem.new()
var negotiation_system := NegotiationSystem.new()

var definitions: Dictionary = {}
var factions: Dictionary = {}
var provinces: Dictionary = {}
var political_groups: Dictionary = {}
var rebellions: Dictionary = {}
var negotiations: Dictionary = {}
var turn := 0
var alerts: Array[Dictionary] = []

func _init() -> void:
    definitions = {
        "governments": _load_json(GOVERNMENT_PATH),
        "groups": _load_json(GROUP_PATH),
        "control": _load_json(CONTROL_PATH),
        "rebellion": _load_json(REBELLION_PATH),
    }

func register_faction(faction: Dictionary) -> void:
    var id := String(faction.get("faction_id", faction.get("id", "")))
    if id == "":
        push_error("GovernanceSession: faction_id가 필요합니다.")
        return
    var state := faction.duplicate(true)
    state["faction_id"] = id
    state["government_type"] = String(state.get("government_type", "tribal_confederation"))
    state["authority_hidden"] = float(state.get("authority_hidden", 50.0))
    state["legitimacy_hidden"] = float(state.get("legitimacy_hidden", 50.0))
    state["corruption_hidden"] = float(state.get("corruption_hidden", 0.0))
    state["administration_capacity"] = int(state.get("administration_capacity", 25))
    state["reform_stage"] = String(state.get("reform_stage", "none"))
    state["active_reform"] = state.get("active_reform", {})
    factions[id] = state
    political_groups[id] = political_groups.get(id, {})
    _emit_snapshot()

func register_province(province: Dictionary) -> void:
    var id := String(province.get("province_id", province.get("id", "")))
    if id == "":
        push_error("GovernanceSession: province_id가 필요합니다.")
        return
    var state := province.duplicate(true)
    state["province_id"] = id
    state["control_progress_hidden"] = float(state.get("control_progress_hidden", 100.0))
    state["control_stage"] = EpochStageScale.stage_id(state.control_progress_hidden, EpochStageScale.CONTROL)
    state["governor_character_id"] = String(state.get("governor_character_id", ""))
    state["governor_type"] = String(state.get("governor_type", "appointed_governor"))
    state["strategic_point_ids"] = state.get("strategic_point_ids", []).duplicate(true)
    provinces[id] = state
    _emit_snapshot()

func register_group(faction_id: String, group: Dictionary) -> void:
    if not political_groups.has(faction_id):
        political_groups[faction_id] = {}
    var group_id := String(group.get("group_id", ""))
    if group_id == "":
        push_error("GovernanceSession: group_id가 필요합니다.")
        return
    var state := group.duplicate(true)
    state["group_id"] = group_id
    state["group_type"] = String(state.get("group_type", group_id))
    state["influence_hidden"] = float(state.get("influence_hidden", 50.0))
    state["satisfaction_hidden"] = float(state.get("satisfaction_hidden", 50.0))
    state["rebellion_risk_hidden"] = float(state.get("rebellion_risk_hidden", 0.0))
    state["mobilization_capacity"] = float(state.get("mobilization_capacity", 40.0))
    state["active_causes"] = state.get("active_causes", []).duplicate(true)
    state["recent_modifiers"] = state.get("recent_modifiers", []).duplicate(true)
    political_groups[faction_id][group_id] = state
    _emit_snapshot()

func start_reform(faction_id: String, target_government_id: String, context: Dictionary = {}) -> Dictionary:
    if not factions.has(faction_id):
        return {"accepted": false, "reason": "국가를 찾을 수 없다."}
    var target := government_definition(target_government_id)
    if target.is_empty():
        return {"accepted": false, "reason": "통치체제 정의를 찾을 수 없다."}
    var faction: Dictionary = factions[faction_id]
    var validation := reform_system.can_start_reform(faction, target, context)
    if not bool(validation.get("allowed", false)):
        return {"accepted": false, "reasons": validation.get("reasons", [])}
    faction.active_reform = reform_system.start_reform(faction, target_government_id, target)
    factions[faction_id] = faction
    reform_changed.emit(faction_id, faction.active_reform.duplicate(true))
    _emit_snapshot()
    return {"accepted": true, "state": faction.active_reform.duplicate(true)}

func respond_to_reform_opposition(faction_id: String, response_id: String, target_group_id: String = "") -> Dictionary:
    if not factions.has(faction_id):
        return {"accepted": false, "reason": "국가를 찾을 수 없다."}
    var faction: Dictionary = factions[faction_id]
    if faction.get("active_reform", {}).is_empty():
        return {"accepted": false, "reason": "진행 중인 개혁이 없다."}
    var groups := _group_array(faction_id)
    var result := reform_system.apply_response(faction.active_reform, faction, groups, response_id, target_group_id)
    _write_group_array(faction_id, groups)
    factions[faction_id] = faction
    if bool(result.get("accepted", false)):
        _add_alert({"category": "reform", "importance": "important", "message": result.event.message, "faction_id": faction_id})
        reform_changed.emit(faction_id, faction.active_reform.duplicate(true))
        _emit_snapshot()
    return result

func update_province_control(province_id: String, context: Dictionary, governor: Dictionary = {}, war_context: Dictionary = {}) -> Dictionary:
    if not provinces.has(province_id):
        return {"accepted": false, "reason": "프로빈스를 찾을 수 없다."}
    var province: Dictionary = provinces[province_id]
    var result := control_system.evaluate_control(province, context)
    province.control_progress_hidden = float(result.after)
    province.control_stage = String(result.stage_id)
    provinces[province_id] = province

    var decision := {}
    if not governor.is_empty():
        decision = control_system.decide_governor_response(governor, province, war_context)
        province.governor_decision = decision.decision
        province.governor_decision_explanation = decision.explanation
        provinces[province_id] = province

    if bool(result.get("stage_changed", false)):
        _add_alert({
            "category": "province_control",
            "importance": "important",
            "message": "%s의 통제 상태가 '%s' 단계로 변했다." % [String(province.get("name", province_id)), String(result.stage_name)],
            "province_id": province_id,
        })
    _emit_snapshot()
    return {"accepted": true, "control": result, "governor_decision": decision}

func begin_negotiation(initiator_id: String, counterpart_id: String, context: Dictionary = {}) -> Dictionary:
    context["turn"] = turn
    var state := negotiation_system.start_negotiation(initiator_id, counterpart_id, context)
    negotiations[state.negotiation_id] = state
    negotiation_changed.emit(state.negotiation_id, state.duplicate(true))
    _emit_snapshot()
    return state.duplicate(true)

func propose_negotiation_demands(negotiation_id: String, actor_id: String, demands: Array[Dictionary], leverage_context: Dictionary) -> Dictionary:
    if not negotiations.has(negotiation_id):
        return {"accepted": false, "reason": "협상을 찾을 수 없다."}
    var state: Dictionary = negotiations[negotiation_id]
    var result := negotiation_system.propose_demands(state, actor_id, demands, leverage_context)
    negotiations[negotiation_id] = state
    if bool(result.get("accepted", false)):
        negotiation_changed.emit(negotiation_id, state.duplicate(true))
        _emit_snapshot()
    return result

func propose_armistice(negotiation_id: String, actor_id: String, terms: Dictionary) -> Dictionary:
    if not negotiations.has(negotiation_id):
        return {"accepted": false, "reason": "협상을 찾을 수 없다."}
    var state: Dictionary = negotiations[negotiation_id]
    var result := negotiation_system.propose_armistice(state, actor_id, terms, turn)
    negotiations[negotiation_id] = state
    if bool(result.get("accepted", false)):
        negotiation_changed.emit(negotiation_id, state.duplicate(true))
        _emit_snapshot()
    return result

func advance_turn(contexts: Dictionary = {}) -> Dictionary:
    turn += 1
    var turn_events: Array[Dictionary] = []

    for faction_id_value in factions.keys():
        var faction_id := String(faction_id_value)
        var faction: Dictionary = factions[faction_id]
        var group_contexts: Dictionary = contexts.get("group_contexts", {}).get(faction_id, {})
        var groups := _group_array(faction_id)

        for group in groups:
            var group_id := String(group.get("group_id", ""))
            var context: Dictionary = group_contexts.get(group_id, {}).duplicate(true)
            context["turn"] = turn
            var update := rebellion_system.update_group(group, context)
            if bool(update.get("notify", false)):
                var message := "%s: 만족도 %s · 반란 위험 %s" % [
                    String(group.get("name", group_id)),
                    String(update.satisfaction_stage.get("name", "")),
                    String(update.risk_stage.get("name", "")),
                ]
                _add_alert({"category": "politics", "importance": "important", "message": message, "faction_id": faction_id, "group_id": group_id})

        _write_group_array(faction_id, groups)

        if not faction.get("active_reform", {}).is_empty() and bool(faction.active_reform.get("is_active", false)):
            var reform_context: Dictionary = contexts.get("reform_contexts", {}).get(faction_id, {})
            var reform_result := reform_system.advance_turn(faction.active_reform, faction, groups, reform_context)
            for event in reform_result.get("events", []):
                turn_events.append(event)
                _add_alert({"category": "reform", "importance": event.importance, "message": event.message, "faction_id": faction_id})
            reform_changed.emit(faction_id, faction.active_reform.duplicate(true))

        var coalition_context: Dictionary = contexts.get("coalition_contexts", {}).get(faction_id, {})
        var coalition := rebellion_system.coalition_eligibility(groups, coalition_context)
        if bool(coalition.get("eligible", false)):
            var existing_for_faction := false
            for rebellion in rebellions.values():
                if String(rebellion.get("parent_faction_id", "")) == faction_id and String(rebellion.get("status", "active")) == "active":
                    existing_for_faction = true
                    break
            if not existing_for_faction:
                var origins: Array = coalition_context.get("origin_province_ids", [])
                var new_rebellions := rebellion_system.create_separate_rebellions(coalition, political_groups[faction_id], origins)
                for rebellion in new_rebellions:
                    rebellion.parent_faction_id = faction_id
                    rebellion.status = "active"
                    rebellions[rebellion.rebellion_id] = rebellion
                if not new_rebellions.is_empty():
                    rebellion_started.emit(new_rebellions.duplicate(true))
                    _add_alert({"category": "rebellion", "importance": "danger", "message": "%d개 정치 집단이 각자 반란을 일으켰다." % new_rebellions.size(), "faction_id": faction_id})

        factions[faction_id] = faction

    for rebellion_id_value in rebellions.keys():
        var rebellion_id := String(rebellion_id_value)
        var rebellion: Dictionary = rebellions[rebellion_id]
        if String(rebellion.get("status", "active")) != "active":
            continue
        rebellion.turns_survived = int(rebellion.get("turns_survived", 0)) + 1
        var state_context: Dictionary = contexts.get("statehood_contexts", {}).get(rebellion_id, {})
        var evaluation := rebellion_system.evaluate_statehood(rebellion, state_context)
        rebellion.statehood_progress = float(evaluation.progress)
        if bool(evaluation.get("can_declare", false)) and String(rebellion.get("declared_faction_id", "")) == "":
            var identity := rebellion_system.choose_state_identity(
                rebellion,
                state_context.get("historical_candidates", []),
                state_context.get("controlled_centers", [])
            )
            rebellion.declared_faction_id = "F_%s" % rebellion_id
            rebellion.declared_state_name = identity.state_name
            rebellion.capital_id = identity.capital_id
            rebellion.status = "declared_state"
            _add_alert({"category": "rebellion", "importance": "danger", "message": "%s이(가) 정식 국가를 선포했다." % identity.state_name, "rebellion_id": rebellion_id})
        rebellions[rebellion_id] = rebellion

    _trim_alerts()
    _emit_snapshot()
    return {"turn": turn, "events": turn_events, "snapshot": snapshot()}

func government_definition(government_id: String) -> Dictionary:
    for definition in definitions.get("governments", {}).get("government_types", []):
        if String(definition.get("id", "")) == government_id:
            return definition.duplicate(true)
    return {}

func group_detail(faction_id: String, group_id: String) -> Dictionary:
    if not political_groups.has(faction_id) or not political_groups[faction_id].has(group_id):
        return {}
    var group: Dictionary = political_groups[faction_id][group_id]
    var influence := float(group.get("influence_hidden", 50.0))
    var satisfaction := float(group.get("satisfaction_hidden", 50.0))
    var risk := float(group.get("rebellion_risk_hidden", 0.0))
    return {
        "group_id": group_id,
        "name": group.get("name", group_id),
        "influence": EpochStageScale.stage(influence, EpochStageScale.INFLUENCE),
        "satisfaction": EpochStageScale.stage(satisfaction, EpochStageScale.SATISFACTION),
        "rebellion_risk": EpochStageScale.stage(risk, EpochStageScale.REBELLION_RISK),
        "proximity": EpochStageScale.proximity_to_next_stage(risk, EpochStageScale.REBELLION_RISK),
        "trend": group.get("trend", "유지"),
        "demands": group.get("demands", []).duplicate(true),
        "reform_stance": group.get("reform_stance", "neutral"),
        "recent_modifiers": group.get("recent_modifiers", []).duplicate(true),
    }

func snapshot() -> Dictionary:
    return {
        "turn": turn,
        "factions": factions.duplicate(true),
        "provinces": provinces.duplicate(true),
        "political_groups": political_groups.duplicate(true),
        "rebellions": rebellions.duplicate(true),
        "negotiations": negotiations.duplicate(true),
        "alerts": alerts.duplicate(true),
    }

func _group_array(faction_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for group in political_groups.get(faction_id, {}).values():
        result.append(group)
    return result

func _write_group_array(faction_id: String, groups: Array[Dictionary]) -> void:
    if not political_groups.has(faction_id):
        political_groups[faction_id] = {}
    for group in groups:
        political_groups[faction_id][String(group.get("group_id", ""))] = group

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("GovernanceSession: 정의 파일을 찾을 수 없습니다: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("GovernanceSession: 정의 파일을 열 수 없습니다: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is not Dictionary:
        push_error("GovernanceSession: JSON 형식이 잘못되었습니다: %s" % path)
        return {}
    return parsed

func _add_alert(alert: Dictionary) -> void:
    var entry := alert.duplicate(true)
    entry["turn"] = turn
    alerts.append(entry)
    governance_alert.emit(entry.duplicate(true))

func _trim_alerts() -> void:
    while alerts.size() > 120:
        alerts.pop_front()

func _emit_snapshot() -> void:
    governance_changed.emit(snapshot())
