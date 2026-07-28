class_name GovernanceReformSystem
extends RefCounted

const STAGES := ["preparation", "implementation", "consolidation"]
const STAGE_NAMES := {
    "preparation": "준비",
    "implementation": "시행",
    "consolidation": "정착",
}

const RESPONSE_EFFECTS := {
    "negotiate": {"treasury": 0, "progress": -6.0, "opposition": -12.0, "legitimacy": 2.0, "corruption": 0.0},
    "bribe": {"treasury": -250, "progress": 4.0, "opposition": -20.0, "legitimacy": -1.0, "corruption": 8.0},
    "purge": {"treasury": -80, "progress": 10.0, "opposition": -28.0, "legitimacy": -12.0, "corruption": -2.0},
    "suppress": {"treasury": -180, "progress": 16.0, "opposition": -18.0, "legitimacy": -8.0, "corruption": 0.0},
}

func can_start_reform(faction: Dictionary, target_definition: Dictionary, world_context: Dictionary) -> Dictionary:
    var reasons: Array[String] = []
    var requirements: Dictionary = target_definition.get("reform_requirements", {})

    var authority_value := float(faction.get("authority_hidden", 0.0))
    var required_authority := _authority_min(String(requirements.get("authority_stage_min", "weak")))
    if authority_value < required_authority:
        reasons.append("군주 권위가 부족하다.")

    if int(faction.get("administration_capacity", 0)) < int(requirements.get("administration_capacity_min", 0)):
        reasons.append("행정 역량이 부족하다.")

    if int(faction.get("treasury", 0)) < int(requirements.get("treasury_min", 0)):
        reasons.append("개혁 준비 재정이 부족하다.")

    var technologies: Array = faction.get("technology_tags", [])
    for required_tag in requirements.get("technology_tags", []):
        if required_tag not in technologies:
            reasons.append("필수 제도·기술이 없다: %s" % String(required_tag))

    if bool(world_context.get("succession_crisis", false)):
        reasons.append("왕위 계승 분쟁 중에는 대개혁을 시작할 수 없다.")

    if bool(world_context.get("capital_occupied", false)):
        reasons.append("수도가 점령된 상태다.")

    if String(faction.get("reform_stage", "none")) != "none":
        reasons.append("이미 다른 개혁이 진행 중이다.")

    return {"allowed": reasons.is_empty(), "reasons": reasons}

func start_reform(faction: Dictionary, target_government_id: String, target_definition: Dictionary) -> Dictionary:
    var state := {
        "target_government_id": target_government_id,
        "stage": "preparation",
        "stage_progress_hidden": 0.0,
        "overall_progress_hidden": 0.0,
        "turns_in_stage": 0,
        "support_group_ids": [],
        "opposition_group_ids": [],
        "events": [],
        "compromises": [],
        "is_active": true,
        "failed": false,
        "completed": false,
    }
    var setup_cost := int(target_definition.get("reform_requirements", {}).get("treasury_min", 0)) / 5
    faction["treasury"] = maxi(0, int(faction.get("treasury", 0)) - setup_cost)
    faction["reform_target"] = target_government_id
    faction["reform_stage"] = "preparation"
    faction["reform_progress_hidden"] = 0.0
    state.events.append(_event("개혁 준비를 시작했다.", "important", {"treasury": -setup_cost}))
    return state

func advance_turn(reform: Dictionary, faction: Dictionary, groups: Array[Dictionary], world_context: Dictionary) -> Dictionary:
    if not bool(reform.get("is_active", false)):
        return {"state": reform, "events": []}

    var stage := String(reform.get("stage", "preparation"))
    var base_progress := _base_progress(stage)
    var support := 0.0
    var opposition := 0.0
    var support_ids: Array[String] = []
    var opposition_ids: Array[String] = []

    for group in groups:
        var influence := float(group.get("influence_hidden", 50.0))
        var satisfaction := float(group.get("satisfaction_hidden", 50.0))
        var stance := String(group.get("reform_stance", "neutral"))
        match stance:
            "support":
                support += influence * (0.5 + satisfaction / 200.0)
                support_ids.append(String(group.get("group_id", "")))
            "oppose":
                opposition += influence * (1.0 + (100.0 - satisfaction) / 150.0)
                opposition_ids.append(String(group.get("group_id", "")))

    var administration_bonus := float(faction.get("administration_capacity", 0)) * 0.08
    var authority_bonus := float(faction.get("authority_hidden", 0.0)) * 0.05
    var crisis_penalty := _crisis_penalty(world_context)
    var progress_delta := base_progress + administration_bonus + authority_bonus + support * 0.05 - opposition * 0.07 - crisis_penalty
    progress_delta = clampf(progress_delta, -12.0, 30.0)

    var old_progress := float(reform.get("stage_progress_hidden", 0.0))
    var new_progress := clampf(old_progress + progress_delta, 0.0, 100.0)
    reform.stage_progress_hidden = new_progress
    reform.turns_in_stage = int(reform.get("turns_in_stage", 0)) + 1
    reform.support_group_ids = support_ids
    reform.opposition_group_ids = opposition_ids
    reform.overall_progress_hidden = _overall_progress(stage, new_progress)

    var events: Array[Dictionary] = []
    if progress_delta < 0.0:
        events.append(_event("개혁이 반발과 혼란으로 후퇴했다.", "warning", {"progress": progress_delta}))
    elif progress_delta >= 18.0:
        events.append(_event("개혁이 빠르게 진전되고 있다.", "important", {"progress": progress_delta}))

    if opposition >= 120.0 and stage != "preparation":
        events.append(_event("강한 반대 집단이 공동 행동을 준비한다.", "danger", {"opposition": opposition}))

    if new_progress >= 100.0:
        var stage_result := _complete_stage(reform, faction, opposition, world_context)
        events.append_array(stage_result.events)

    reform.events.append_array(events)
    return {
        "state": reform,
        "events": events,
        "progress_delta": progress_delta,
        "support_score": support,
        "opposition_score": opposition,
    }

func apply_response(reform: Dictionary, faction: Dictionary, groups: Array[Dictionary], response_id: String, target_group_id: String = "") -> Dictionary:
    if not RESPONSE_EFFECTS.has(response_id):
        return {"accepted": false, "reason": "알 수 없는 대응 방식이다."}

    var effect: Dictionary = RESPONSE_EFFECTS[response_id]
    var treasury_after := int(faction.get("treasury", 0)) + int(effect.treasury)
    if treasury_after < 0:
        return {"accepted": false, "reason": "대응에 필요한 재정이 부족하다."}

    faction.treasury = treasury_after
    faction.legitimacy_hidden = EpochStageScale.clamp_hidden(float(faction.get("legitimacy_hidden", 50.0)) + float(effect.legitimacy))
    faction.corruption_hidden = EpochStageScale.clamp_hidden(float(faction.get("corruption_hidden", 0.0)) + float(effect.corruption))
    reform.stage_progress_hidden = EpochStageScale.clamp_hidden(float(reform.get("stage_progress_hidden", 0.0)) + float(effect.progress))

    for group in groups:
        if target_group_id != "" and String(group.get("group_id", "")) != target_group_id:
            continue
        if String(group.get("reform_stance", "neutral")) == "oppose":
            group.satisfaction_hidden = EpochStageScale.clamp_hidden(float(group.get("satisfaction_hidden", 50.0)) - float(effect.opposition))
            group.recent_modifiers = _append_history(group.get("recent_modifiers", []), {
                "source": "reform_response_%s" % response_id,
                "delta": -float(effect.opposition),
            })

    var event := _event("개혁 반발에 '%s' 방식으로 대응했다." % response_id, "important", effect)
    reform.events.append(event)
    return {"accepted": true, "event": event, "state": reform}

func stage_view(reform: Dictionary) -> Dictionary:
    var stage := String(reform.get("stage", "none"))
    var progress := float(reform.get("stage_progress_hidden", 0.0))
    return {
        "stage_id": stage,
        "stage_name": STAGE_NAMES.get(stage, "개혁 없음"),
        "progress_stage": EpochStageScale.stage(progress, EpochStageScale.PROXIMITY),
        "proximity": EpochStageScale.proximity_to_next_stage(progress, [
            {"id": "start", "name": "시작", "min": 0},
            {"id": "complete", "name": "단계 완료", "min": 100},
        ]),
        "turns_in_stage": int(reform.get("turns_in_stage", 0)),
        "completed": bool(reform.get("completed", false)),
        "failed": bool(reform.get("failed", false)),
    }

func _complete_stage(reform: Dictionary, faction: Dictionary, opposition: float, world_context: Dictionary) -> Dictionary:
    var events: Array[Dictionary] = []
    var current := String(reform.get("stage", "preparation"))
    var index := STAGES.find(current)

    if current == "consolidation":
        var failure_pressure := opposition + _crisis_penalty(world_context) * 4.0
        if failure_pressure >= 180.0:
            reform.failed = true
            reform.is_active = false
            faction.reform_stage = "none"
            faction.reform_progress_hidden = 0.0
            faction.dual_system = true
            events.append(_event("정착에 실패해 명목 제도와 실제 지방 통치가 분리되었다.", "danger", {}))
        else:
            reform.completed = true
            reform.is_active = false
            faction.government_type = String(reform.get("target_government_id", faction.get("government_type", "")))
            faction.reform_stage = "none"
            faction.reform_progress_hidden = 100.0
            faction.dual_system = false
            events.append(_event("새 통치체제가 정착했다.", "important", {"government_type": faction.government_type}))
        return {"events": events}

    reform.stage = STAGES[index + 1]
    reform.stage_progress_hidden = 0.0
    reform.turns_in_stage = 0
    faction.reform_stage = reform.stage
    faction.reform_progress_hidden = _overall_progress(reform.stage, 0.0)
    events.append(_event("개혁이 '%s' 단계로 넘어갔다." % STAGE_NAMES[reform.stage], "important", {}))
    return {"events": events}

func _base_progress(stage: String) -> float:
    match stage:
        "preparation": return 10.0
        "implementation": return 8.0
        "consolidation": return 7.0
    return 0.0

func _overall_progress(stage: String, stage_progress: float) -> float:
    var index := maxi(STAGES.find(stage), 0)
    return clampf((float(index) * 100.0 + stage_progress) / 3.0, 0.0, 100.0)

func _crisis_penalty(context: Dictionary) -> float:
    var penalty := 0.0
    if bool(context.get("major_war", false)): penalty += 6.0
    if bool(context.get("famine", false)): penalty += 5.0
    if bool(context.get("epidemic", false)): penalty += 5.0
    if bool(context.get("major_disaster", false)): penalty += 4.0
    if bool(context.get("succession_crisis", false)): penalty += 10.0
    if bool(context.get("treasury_crisis", false)): penalty += 6.0
    if bool(context.get("low_central_control", false)): penalty += 7.0
    return penalty

func _authority_min(stage_id: String) -> float:
    match stage_id:
        "weak": return 20.0
        "ordinary": return 40.0
        "strong": return 60.0
        "overwhelming": return 80.0
    return 0.0

func _append_history(history_value: Variant, entry: Dictionary) -> Array:
    var history: Array = history_value.duplicate(true) if history_value is Array else []
    history.append(entry)
    while history.size() > 10:
        history.pop_front()
    return history

func _event(message: String, importance: String, effects: Dictionary) -> Dictionary:
    return {"message": message, "importance": importance, "effects": effects.duplicate(true)}
