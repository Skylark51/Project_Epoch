class_name RebellionSystem
extends RefCounted

const GROUP_GOALS := {
    "aristocracy": {"goal": "restore_privileges", "movement_type": "aristocratic_revolt", "name": "귀족 반란군"},
    "military": {"goal": "seize_command", "movement_type": "military_junta", "name": "군부 반란군"},
    "bureaucracy": {"goal": "restore_old_order", "movement_type": "bureaucratic_opposition", "name": "관료 반대파"},
    "religious_estate": {"goal": "restore_religious_policy", "movement_type": "religious_revolt", "name": "종교 반란군"},
    "local_populace": {"goal": "tax_and_corvee_relief", "movement_type": "popular_revolt", "name": "지방민 반란군"},
}

const STATEHOOD_DEFAULTS := {
    "minimum_provinces": 2,
    "minimum_population": 25000,
    "minimum_survival_turns": 4,
    "minimum_troops": 1500,
    "minimum_food": 1200,
    "minimum_support_value": 55.0,
}

func update_group(group: Dictionary, context: Dictionary) -> Dictionary:
    var old_satisfaction := float(group.get("satisfaction_hidden", 50.0))
    var old_risk := float(group.get("rebellion_risk_hidden", 0.0))
    var satisfaction_delta := _satisfaction_delta(group, context)
    var new_satisfaction := EpochStageScale.clamp_hidden(old_satisfaction + satisfaction_delta)

    var influence := float(group.get("influence_hidden", 50.0))
    var mobilization := float(group.get("mobilization_capacity", 50.0))
    var trend_pressure := maxf(-satisfaction_delta, 0.0) * 1.5
    var crisis_pressure := _crisis_pressure(context)
    var alliance_pressure := float(context.get("allied_discontent_groups", 0)) * 5.0
    var central_deterrence := float(context.get("central_army_deterrence", 0.0))
    var control_deterrence := float(context.get("central_control_deterrence", 0.0))

    var target_risk := (
        (100.0 - new_satisfaction) * 0.45
        + influence * 0.20
        + mobilization * 0.15
        + trend_pressure
        + crisis_pressure
        + alliance_pressure
        - central_deterrence
        - control_deterrence
    )
    target_risk = EpochStageScale.clamp_hidden(target_risk)

    var smoothing := clampf(float(context.get("risk_smoothing", 0.28)), 0.05, 1.0)
    var new_risk := lerpf(old_risk, target_risk, smoothing)
    group.satisfaction_hidden = new_satisfaction
    group.rebellion_risk_hidden = EpochStageScale.clamp_hidden(new_risk)
    group.trend = EpochStageScale.direction(satisfaction_delta)
    group.recent_modifiers = _append_history(group.get("recent_modifiers", []), {
        "turn": int(context.get("turn", 0)),
        "satisfaction_delta": satisfaction_delta,
        "risk_delta": new_risk - old_risk,
        "causes": context.get("causes", []).duplicate(true),
    })

    var old_satisfaction_stage := EpochStageScale.stage(old_satisfaction, EpochStageScale.SATISFACTION)
    var new_satisfaction_stage := EpochStageScale.stage(new_satisfaction, EpochStageScale.SATISFACTION)
    var old_risk_stage := EpochStageScale.stage(old_risk, EpochStageScale.REBELLION_RISK)
    var new_risk_stage := EpochStageScale.stage(new_risk, EpochStageScale.REBELLION_RISK)

    return {
        "group": group,
        "satisfaction_stage": new_satisfaction_stage,
        "risk_stage": new_risk_stage,
        "proximity": EpochStageScale.proximity_to_next_stage(new_risk, EpochStageScale.REBELLION_RISK),
        "satisfaction_changed": old_satisfaction_stage.get("id", "") != new_satisfaction_stage.get("id", ""),
        "risk_changed": old_risk_stage.get("id", "") != new_risk_stage.get("id", ""),
        "notify": old_satisfaction_stage.get("id", "") != new_satisfaction_stage.get("id", "") or old_risk_stage.get("id", "") != new_risk_stage.get("id", ""),
    }

func coalition_eligibility(groups: Array[Dictionary], context: Dictionary) -> Dictionary:
    var discontent_groups: Array[String] = []
    var strong_groups: Array[String] = []
    var shared_causes: Dictionary = {}
    var compatible := true

    for group in groups:
        var group_id := String(group.get("group_id", ""))
        var satisfaction := float(group.get("satisfaction_hidden", 50.0))
        var influence := float(group.get("influence_hidden", 50.0))
        if satisfaction < 40.0:
            discontent_groups.append(group_id)
            for cause in group.get("active_causes", []):
                shared_causes[String(cause)] = int(shared_causes.get(String(cause), 0)) + 1
        if influence >= 60.0:
            strong_groups.append(group_id)

    var shared_cause_count := 0
    for count in shared_causes.values():
        if int(count) >= 2:
            shared_cause_count += 1

    for conflict in context.get("incompatible_group_pairs", []):
        if conflict is Array and conflict.size() >= 2:
            if String(conflict[0]) in discontent_groups and String(conflict[1]) in discontent_groups:
                compatible = false
                break

    var crisis_met := false
    for key in ["capital_control_weak", "central_army_absent", "major_defeat", "succession_crisis", "famine", "epidemic", "major_disaster", "foreign_war"]:
        if bool(context.get(key, false)):
            crisis_met = true
            break

    var asset_met := false
    for key in ["secured_province", "secured_fortress", "secret_network", "private_army", "foreign_backing"]:
        if bool(context.get(key, false)):
            asset_met = true
            break

    var eligible := (
        discontent_groups.size() >= 2
        and strong_groups.size() >= 1
        and shared_cause_count >= 1
        and crisis_met
        and asset_met
        and compatible
    )

    var missing: Array[String] = []
    if discontent_groups.size() < 2: missing.append("불만 집단이 둘 이상 필요하다.")
    if strong_groups.is_empty(): missing.append("영향력이 강한 집단이 필요하다.")
    if shared_cause_count < 1: missing.append("공통 반대 명분이 필요하다.")
    if not crisis_met: missing.append("중앙정부가 흔들리는 위기 상황이 필요하다.")
    if not asset_met: missing.append("반란을 시작할 거점·병력·연락망이 필요하다.")
    if not compatible: missing.append("집단들의 핵심 요구가 서로 충돌한다.")

    return {
        "eligible": eligible,
        "groups": discontent_groups,
        "strong_groups": strong_groups,
        "shared_causes": shared_causes,
        "missing": missing,
        "warning_signs": _warning_signs(context),
    }

func create_separate_rebellions(coalition: Dictionary, groups_by_id: Dictionary, origin_provinces: Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var group_ids: Array = coalition.get("groups", [])
    for index in range(group_ids.size()):
        var group_id := String(group_ids[index])
        if not groups_by_id.has(group_id):
            continue
        var group: Dictionary = groups_by_id[group_id]
        var group_type := String(group.get("group_type", group_id))
        var defaults: Dictionary = GROUP_GOALS.get(group_type, {
            "goal": "oppose_government",
            "movement_type": "regional_revolt",
            "name": "지역 반란군",
        })
        var province_id := String(origin_provinces[index % maxi(origin_provinces.size(), 1)]) if not origin_provinces.is_empty() else ""
        result.append({
            "rebellion_id": "REB_%s_%d" % [group_id.to_upper(), index + 1],
            "name": String(defaults.get("name", "지역 반란군")),
            "group_id": group_id,
            "group_type": group_type,
            "movement_type": String(defaults.get("movement_type", "regional_revolt")),
            "goal": String(defaults.get("goal", "oppose_government")),
            "leader_character_id": String(group.get("representative_character_id", "")),
            "occupied_province_ids": [province_id] if province_id != "" else [],
            "controlled_settlement_ids": [],
            "troops": maxi(int(group.get("mobilization_capacity", 0)) * 20, 200),
            "food": maxi(int(group.get("mobilization_capacity", 0)) * 12, 100),
            "support_hidden": float(group.get("rebellion_risk_hidden", 50.0)),
            "legitimacy_claim": String(group.get("legitimacy_claim", defaults.get("goal", "oppose_government"))),
            "turns_survived": 0,
            "tax_capacity": false,
            "core_city_or_fortress": false,
            "foreign_recognition": false,
            "declared_faction_id": "",
            "statehood_progress": 0.0,
            "allied_rebellion_ids": [],
            "rival_rebellion_ids": [],
        })

    for rebellion in result:
        for other in result:
            if rebellion.rebellion_id == other.rebellion_id:
                continue
            rebellion.allied_rebellion_ids.append(other.rebellion_id)
    return result

func evaluate_statehood(rebellion: Dictionary, world_context: Dictionary, requirements: Dictionary = {}) -> Dictionary:
    var rules: Dictionary = STATEHOOD_DEFAULTS.duplicate(true)
    for key in requirements:
        rules[key] = requirements[key]

    var population := int(world_context.get("controlled_population", 0))
    var occupied_provinces: Array = rebellion.get("occupied_province_ids", [])
    var province_count: int = occupied_provinces.size()
    var score := 0.0
    var missing: Array[String] = []

    score += minf(float(province_count) / maxf(float(rules.minimum_provinces), 1.0), 1.0) * 15.0
    score += minf(float(population) / maxf(float(rules.minimum_population), 1.0), 1.0) * 15.0
    score += minf(float(rebellion.get("turns_survived", 0)) / maxf(float(rules.minimum_survival_turns), 1.0), 1.0) * 10.0
    score += minf(float(rebellion.get("troops", 0)) / maxf(float(rules.minimum_troops), 1.0), 1.0) * 10.0
    score += minf(float(rebellion.get("food", 0)) / maxf(float(rules.minimum_food), 1.0), 1.0) * 10.0
    score += minf(float(rebellion.get("support_hidden", 0.0)) / maxf(float(rules.minimum_support_value), 1.0), 1.0) * 10.0

    if String(rebellion.get("leader_character_id", "")) != "": score += 10.0
    else: missing.append("이름 있는 지도자")
    if bool(rebellion.get("core_city_or_fortress", false)): score += 8.0
    else: missing.append("중심 도시 또는 핵심 요새")
    if String(rebellion.get("legitimacy_claim", "")) != "": score += 5.0
    else: missing.append("정치적 명분")
    if bool(rebellion.get("tax_capacity", false)): score += 7.0
    else: missing.append("행정·세금 징수 능력")

    if bool(rebellion.get("foreign_recognition", false)): score += 7.5
    if bool(world_context.get("parent_state_weak", false)): score += 7.5

    if province_count < int(rules.minimum_provinces): missing.append("필요 프로빈스 수")
    if population < int(rules.minimum_population): missing.append("필요 인구")
    if int(rebellion.get("turns_survived", 0)) < int(rules.minimum_survival_turns): missing.append("최소 생존 턴")
    if int(rebellion.get("troops", 0)) < int(rules.minimum_troops): missing.append("병력")
    if int(rebellion.get("food", 0)) < int(rules.minimum_food): missing.append("식량")
    if float(rebellion.get("support_hidden", 0.0)) < float(rules.minimum_support_value): missing.append("주민·집단 지지")

    var can_declare := missing.is_empty()
    rebellion.statehood_progress = clampf(score, 0.0, 100.0)
    return {
        "can_declare": can_declare,
        "progress": rebellion.statehood_progress,
        "missing": missing,
        "proximity": EpochStageScale.stage(score, EpochStageScale.PROXIMITY),
    }

func choose_state_identity(rebellion: Dictionary, historical_candidates: Array, controlled_centers: Array) -> Dictionary:
    var state_name := ""
    var name_source := "generated_name"

    var priority := ["historical_regional_state", "clan_or_tribal_state", "restored_dynasty", "historical_capital_name", "generated_name"]
    for source in priority:
        for candidate_value in historical_candidates:
            if candidate_value is not Dictionary:
                continue
            var candidate: Dictionary = candidate_value
            if String(candidate.get("type", "")) == source and bool(candidate.get("available", true)):
                state_name = String(candidate.get("name", ""))
                name_source = source
                break
        if state_name != "":
            break

    if state_name == "":
        state_name = "%s 정권" % String(rebellion.get("name", "신생"))

    var capital_id := ""
    var capital_name := ""
    var best_score := -INF
    for center_value in controlled_centers:
        if center_value is not Dictionary:
            continue
        var center: Dictionary = center_value
        var center_score := 0.0
        if bool(center.get("historical_center", false)): center_score += 50.0
        if bool(center.get("leader_home", false)): center_score += 40.0
        if bool(center.get("former_capital", false)): center_score += 35.0
        center_score += float(center.get("defense", 0.0)) * 0.20
        center_score += float(center.get("logistics", 0.0)) * 0.20
        if center_score > best_score:
            best_score = center_score
            capital_id = String(center.get("id", ""))
            capital_name = String(center.get("name", capital_id))

    return {
        "state_name": state_name,
        "name_source": name_source,
        "capital_id": capital_id,
        "capital_name": capital_name,
    }

func _satisfaction_delta(group: Dictionary, context: Dictionary) -> float:
    var delta := float(context.get("base_satisfaction_delta", 0.0))
    var interests: Array = group.get("interests", [])
    var policy_effects: Dictionary = context.get("policy_effects", {})
    for interest in interests:
        delta += float(policy_effects.get(String(interest), 0.0))
    if bool(context.get("gradual_change", true)):
        delta = clampf(delta, -12.0, 12.0)
    return delta

func _crisis_pressure(context: Dictionary) -> float:
    var pressure := 0.0
    if bool(context.get("major_defeat", false)): pressure += 12.0
    if bool(context.get("succession_crisis", false)): pressure += 14.0
    if bool(context.get("famine", false)): pressure += 10.0
    if bool(context.get("epidemic", false)): pressure += 8.0
    if bool(context.get("major_disaster", false)): pressure += 7.0
    if bool(context.get("foreign_war", false)): pressure += 5.0
    if bool(context.get("capital_control_weak", false)): pressure += 10.0
    return pressure

func _warning_signs(context: Dictionary) -> Array[String]:
    var result: Array[String] = []
    var labels := {
        "secret_meetings": "비밀 회합",
        "fund_transfers": "수상한 자금 이동",
        "private_army_growth": "사병 증원",
        "rumors": "유언비어 확산",
        "order_refusal": "지방 명령 불복",
        "gate_closure": "성문 폐쇄",
        "tax_refusal": "세금·군량 납부 거부",
        "weapon_stockpile": "무기·식량 비축",
    }
    for key in labels:
        if bool(context.get(key, false)):
            result.append(String(labels[key]))
    return result

func _append_history(history_value: Variant, entry: Dictionary) -> Array:
    var history: Array = history_value.duplicate(true) if history_value is Array else []
    history.append(entry)
    while history.size() > 10:
        history.pop_front()
    return history
