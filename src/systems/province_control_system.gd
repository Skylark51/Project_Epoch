class_name ProvinceControlSystem
extends RefCounted

const CONTROL_FACTORS := {
    "core_city_held": 22.0,
    "major_fort_held": 10.0,
    "minor_point_held": 4.0,
    "supply_connected": 12.0,
    "road_connected": 6.0,
    "governor_cooperation": 15.0,
    "local_support_high": 12.0,
    "local_support_low": -12.0,
    "enemy_field_army_present": -18.0,
    "active_resistance": -15.0,
    "adjacent_friendly_majority": 8.0,
    "occupation_turn": 3.0,
    "pillage_policy": -12.0,
    "forced_labor_policy": -8.0,
    "relief_policy": 10.0,
}

const GOVERNOR_SURRENDER_BIAS := {
    "appointed_governor": 5.0,
    "hereditary_lord": -4.0,
    "royal_feudal_lord": -8.0,
    "military_governor": -12.0,
    "tribal_leader": -3.0,
    "religious_leader": 0.0,
    "military_administrator": 8.0,
}

func evaluate_control(province: Dictionary, context: Dictionary) -> Dictionary:
    var before := float(province.get("control_progress_hidden", 0.0))
    var delta := 0.0
    var reasons: Array[Dictionary] = []

    delta += _factor(context.get("core_city_held", false), "core_city_held", reasons, "중심 도시 장악")
    delta += float(context.get("major_forts_held", 0)) * CONTROL_FACTORS.major_fort_held
    if int(context.get("major_forts_held", 0)) > 0:
        reasons.append({"label": "주요 요새 장악", "value": float(context.get("major_forts_held", 0)) * CONTROL_FACTORS.major_fort_held})

    delta += float(context.get("minor_points_held", 0)) * CONTROL_FACTORS.minor_point_held
    if int(context.get("minor_points_held", 0)) > 0:
        reasons.append({"label": "전략 지점 장악", "value": float(context.get("minor_points_held", 0)) * CONTROL_FACTORS.minor_point_held})

    delta += _factor(context.get("supply_connected", false), "supply_connected", reasons, "보급망 연결")
    delta += _factor(context.get("road_connected", false), "road_connected", reasons, "도로 연결")
    delta += _factor(context.get("governor_cooperation", false), "governor_cooperation", reasons, "통치자 협조")
    delta += _factor(context.get("local_support_high", false), "local_support_high", reasons, "현지 지지")
    delta += _factor(context.get("local_support_low", false), "local_support_low", reasons, "현지 반감")
    delta += _factor(context.get("enemy_field_army_present", false), "enemy_field_army_present", reasons, "적 야전군 잔존")
    delta += _factor(context.get("active_resistance", false), "active_resistance", reasons, "저항 활동")
    delta += _factor(context.get("adjacent_friendly_majority", false), "adjacent_friendly_majority", reasons, "인접 우호 지역")

    var occupation_turns := mini(int(context.get("occupation_turns", 0)), 5)
    if occupation_turns > 0:
        var occupation_value := float(occupation_turns) * CONTROL_FACTORS.occupation_turn
        delta += occupation_value
        reasons.append({"label": "점령 유지", "value": occupation_value})

    var policy := String(context.get("occupation_policy", "neutral"))
    match policy:
        "pillage":
            delta += CONTROL_FACTORS.pillage_policy
            reasons.append({"label": "약탈 정책", "value": CONTROL_FACTORS.pillage_policy})
        "forced_labor":
            delta += CONTROL_FACTORS.forced_labor_policy
            reasons.append({"label": "강제노역", "value": CONTROL_FACTORS.forced_labor_policy})
        "relief":
            delta += CONTROL_FACTORS.relief_policy
            reasons.append({"label": "구휼 정책", "value": CONTROL_FACTORS.relief_policy})

    var per_turn_limit := float(context.get("per_turn_control_limit", 24.0))
    delta = clampf(delta, -per_turn_limit, per_turn_limit)
    var after := EpochStageScale.clamp_hidden(before + delta)
    var old_stage := EpochStageScale.stage(before, EpochStageScale.CONTROL)
    var new_stage := EpochStageScale.stage(after, EpochStageScale.CONTROL)

    return {
        "before": before,
        "after": after,
        "delta": delta,
        "stage_id": new_stage.get("id", "unsecured"),
        "stage_name": new_stage.get("name", "미확보"),
        "stage_changed": old_stage.get("id", "") != new_stage.get("id", ""),
        "proximity": EpochStageScale.proximity_to_next_stage(after, EpochStageScale.CONTROL),
        "reasons": reasons,
        "political_transfer_ready": after >= 75.0,
        "full_control": after >= 95.0,
    }

func decide_governor_response(governor: Dictionary, province: Dictionary, war: Dictionary) -> Dictionary:
    var control := float(province.get("control_progress_hidden", 0.0))
    var loyalty := float(governor.get("loyalty", 50.0))
    var ambition := float(governor.get("ambition", 50.0))
    var local_base := float(governor.get("local_base", 50.0))
    var courage := float(governor.get("courage", 50.0))
    var surrender_bias := float(GOVERNOR_SURRENDER_BIAS.get(String(governor.get("governor_type", "appointed_governor")), 0.0))
    var relief_expected := float(war.get("relief_probability", 0.0))
    var garrison_ratio := float(war.get("garrison_strength_ratio", 1.0))
    var foreign_escape := bool(war.get("foreign_escape_available", false))
    var coup_pressure := float(war.get("coup_pressure", 0.0))

    var surrender_score := control * 0.65 + (100.0 - courage) * 0.25 + surrender_bias - relief_expected * 0.20
    var resistance_score := loyalty * 0.35 + courage * 0.30 + local_base * 0.20 + garrison_ratio * 10.0
    var autonomy_score := ambition * 0.35 + local_base * 0.25 + control * 0.20

    var decision := "resist"
    var explanation := "통치자가 충성과 현지 기반을 믿고 저항을 지속한다."

    if coup_pressure >= 75.0:
        decision = "replaced_by_coup"
        explanation = "현지 세력이 통치자를 교체하고 별도의 결정을 내렸다."
    elif control >= 95.0 and surrender_score >= resistance_score + 15.0:
        decision = "unconditional_surrender"
        explanation = "군사 통제와 보급 붕괴로 무조건 항복을 선택했다."
    elif control >= 75.0 and autonomy_score >= 65.0:
        decision = "conditional_autonomy"
        explanation = "통치권과 가문 지위를 보장받는 조건으로 항복을 제안했다."
    elif control >= 65.0 and ambition >= 65.0:
        decision = "request_vassalage"
        explanation = "직접 편입보다 봉신 지위를 통해 권력을 보존하려 한다."
    elif control >= 55.0 and relief_expected < 30.0:
        decision = "seek_armistice"
        explanation = "구원 가능성이 낮아 시간을 벌기 위한 휴전을 요청했다."
    elif foreign_escape and control >= 60.0 and loyalty < 45.0:
        decision = "flee"
        explanation = "통치자가 병력과 가문을 보존하기 위해 외국 또는 후방으로 도주했다."
    elif relief_expected >= 60.0:
        decision = "request_foreign_aid"
        explanation = "구원군 도착 가능성을 믿고 외부 지원을 요청했다."

    return {
        "decision": decision,
        "explanation": explanation,
        "surrender_score": surrender_score,
        "resistance_score": resistance_score,
        "autonomy_score": autonomy_score,
    }

func political_transfer_allowed(control_result: Dictionary, governor_decision: String, peace_terms: Dictionary = {}) -> bool:
    if bool(peace_terms.get("transfer_province", false)):
        return true
    if not bool(control_result.get("political_transfer_ready", false)):
        return false
    return governor_decision in ["unconditional_surrender", "conditional_autonomy", "request_vassalage", "replaced_by_coup"]

func _factor(enabled: Variant, key: String, reasons: Array[Dictionary], label: String) -> float:
    if not bool(enabled):
        return 0.0
    var value := float(CONTROL_FACTORS.get(key, 0.0))
    reasons.append({"label": label, "value": value})
    return value
