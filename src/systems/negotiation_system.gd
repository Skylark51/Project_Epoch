class_name NegotiationSystem
extends RefCounted

const STAGES := ["opening", "demands", "counteroffer", "final_agreement"]
const STAGE_NAMES := {
    "opening": "협상 개시",
    "demands": "핵심 요구",
    "counteroffer": "수정안",
    "final_agreement": "최종 합의",
}

const OUTCOMES := [
    "independence",
    "vassalage",
    "autonomous_domain",
    "tribute_state",
    "territorial_compromise",
    "office_and_title",
    "joint_government",
    "armistice",
    "amnesty",
    "war_resumes",
]

func start_negotiation(initiator_id: String, counterpart_id: String, context: Dictionary) -> Dictionary:
    return {
        "negotiation_id": "NEG_%s_%s_%d" % [initiator_id, counterpart_id, int(context.get("turn", 0))],
        "initiator_id": initiator_id,
        "counterpart_id": counterpart_id,
        "stage": "opening",
        "round": 1,
        "deadline_turn": int(context.get("turn", 0)) + maxi(int(context.get("deadline_turns", 4)), 1),
        "meeting_place": String(context.get("meeting_place", "border_camp")),
        "demands": [],
        "counteroffers": [],
        "concessions": [],
        "armistice": {},
        "status": "active",
        "outcome": "",
        "history": [_entry("협상이 시작되었다.", "opening", {})],
    }

func propose_demands(negotiation: Dictionary, actor_id: String, demands: Array[Dictionary], leverage_context: Dictionary) -> Dictionary:
    if String(negotiation.get("status", "")) != "active":
        return {"accepted": false, "reason": "진행 중인 협상이 아니다."}
    if String(negotiation.get("stage", "opening")) not in ["opening", "demands", "counteroffer"]:
        return {"accepted": false, "reason": "현재 단계에서는 요구안을 제시할 수 없다."}

    var validated: Array[Dictionary] = []
    for demand in demands:
        var demand_type := String(demand.get("type", ""))
        if demand_type not in ["territory", "state_name", "ruler_title", "tribute", "military_rights", "foreign_policy", "tax_rights", "judicial_rights", "hostages", "prisoner_exchange"]:
            continue
        var item := demand.duplicate(true)
        item["actor_id"] = actor_id
        item["weight"] = demand_weight(item)
        validated.append(item)

    if validated.is_empty():
        return {"accepted": false, "reason": "유효한 요구가 없다."}

    if String(negotiation.get("stage", "opening")) == "opening":
        negotiation.stage = "demands"
    elif String(negotiation.get("stage", "")) == "demands" and not negotiation.demands.is_empty():
        negotiation.stage = "counteroffer"
        negotiation.counteroffers.append_array(validated)
    else:
        negotiation.demands.append_array(validated)

    if negotiation.demands.is_empty():
        negotiation.demands.append_array(validated)

    var leverage := calculate_leverage(leverage_context)
    negotiation.history.append(_entry("%s 측이 요구안을 제시했다." % actor_id, String(negotiation.stage), {"demands": validated, "leverage": leverage}))
    return {"accepted": true, "demands": validated, "leverage": leverage, "state": negotiation}

func calculate_leverage(context: Dictionary) -> float:
    var score := 0.0
    score += float(context.get("territory_share", 0.0)) * 24.0
    score += float(context.get("troop_ratio", 0.0)) * 12.0
    score += float(context.get("food_security", 0.0)) * 8.0
    score += float(context.get("popular_support", 0.0)) * 10.0
    score += float(context.get("foreign_backing", 0.0)) * 10.0
    score += 12.0 if bool(context.get("capital_control", false)) else 0.0
    score += 8.0 if bool(context.get("fortress_control", false)) else 0.0
    score += float(context.get("counterpart_war_pressure", 0.0)) * 12.0
    score -= float(context.get("internal_division", 0.0)) * 12.0
    score += float(context.get("legitimacy", 0.0)) * 10.0
    return clampf(score, 0.0, 100.0)

func demand_weight(demand: Dictionary) -> float:
    var demand_type := String(demand.get("type", ""))
    var base := {
        "territory": 18.0,
        "state_name": 7.0,
        "ruler_title": 8.0,
        "tribute": 10.0,
        "military_rights": 14.0,
        "foreign_policy": 16.0,
        "tax_rights": 15.0,
        "judicial_rights": 12.0,
        "hostages": 9.0,
        "prisoner_exchange": 5.0,
    }.get(demand_type, 10.0)
    var scale := float(demand.get("scale", 1.0))
    return maxf(float(base) * maxf(scale, 0.1), 1.0)

func evaluate_offer(negotiation: Dictionary, receiver_leverage: float, trust: float, exhaustion: float) -> Dictionary:
    var offered_weight := 0.0
    for demand in negotiation.get("demands", []):
        offered_weight += float(demand.get("weight", demand_weight(demand)))
    for demand in negotiation.get("counteroffers", []):
        offered_weight += float(demand.get("weight", demand_weight(demand))) * 0.75

    var acceptance_capacity := receiver_leverage * 0.55 + trust * 0.20 + exhaustion * 0.35
    var margin := acceptance_capacity - offered_weight
    var response := "reject"
    if margin >= 20.0:
        response = "accept"
    elif margin >= -10.0:
        response = "counteroffer"

    return {
        "response": response,
        "offered_weight": offered_weight,
        "acceptance_capacity": acceptance_capacity,
        "margin": margin,
    }

func propose_armistice(negotiation: Dictionary, proposer_id: String, terms: Dictionary, current_turn: int) -> Dictionary:
    var validation := validate_armistice_terms(terms)
    if not bool(validation.get("valid", false)):
        return {"accepted": false, "reason": validation.get("reason", "휴전 조건이 유효하지 않다.")}

    var armistice := {
        "proposer_id": proposer_id,
        "start_turn": current_turn,
        "end_turn": current_turn + int(terms.get("duration_turns", 1)),
        "scope_type": String(terms.get("scope_type", "all_fronts")),
        "scope_ids": terms.get("scope_ids", []).duplicate(true),
        "movement_policy": String(terms.get("movement_policy", "limited")),
        "reinforcement_allowed": bool(terms.get("reinforcement_allowed", false)),
        "recruitment_allowed": bool(terms.get("recruitment_allowed", false)),
        "wall_repair_allowed": bool(terms.get("wall_repair_allowed", false)),
        "supply_stockpiling_allowed": bool(terms.get("supply_stockpiling_allowed", true)),
        "prisoner_exchange": bool(terms.get("prisoner_exchange", false)),
        "auto_resume_war": bool(terms.get("auto_resume_war", true)),
        "status": "proposed",
        "breached_by": "",
    }
    negotiation.armistice = armistice
    negotiation.history.append(_entry("%s 측이 %d턴 휴전을 제안했다." % [proposer_id, int(terms.get("duration_turns", 1))], String(negotiation.get("stage", "opening")), armistice))
    return {"accepted": true, "armistice": armistice, "state": negotiation}

func accept_armistice(negotiation: Dictionary, actor_id: String) -> Dictionary:
    if negotiation.get("armistice", {}).is_empty():
        return {"accepted": false, "reason": "제안된 휴전이 없다."}
    negotiation.armistice.status = "active"
    negotiation.armistice.accepted_by = actor_id
    negotiation.history.append(_entry("휴전이 발효되었다.", String(negotiation.get("stage", "opening")), negotiation.armistice))
    return {"accepted": true, "armistice": negotiation.armistice, "state": negotiation}

func validate_armistice_terms(terms: Dictionary) -> Dictionary:
    var duration := int(terms.get("duration_turns", 0))
    if duration < 1:
        return {"valid": false, "reason": "휴전 기간은 최소 1턴이어야 한다."}
    var scope_type := String(terms.get("scope_type", ""))
    if scope_type not in ["all_fronts", "front", "province", "siege", "prisoner_exchange", "negotiation_period"]:
        return {"valid": false, "reason": "알 수 없는 휴전 범위다."}
    if scope_type in ["front", "province", "siege"] and terms.get("scope_ids", []).is_empty():
        return {"valid": false, "reason": "부분 휴전은 적용 대상을 지정해야 한다."}
    var movement_policy := String(terms.get("movement_policy", "limited"))
    if movement_policy not in ["prohibited", "limited", "rear_only", "unrestricted"]:
        return {"valid": false, "reason": "알 수 없는 병력 이동 조건이다."}
    return {"valid": true}

func check_armistice_action(armistice: Dictionary, action: Dictionary, current_turn: int) -> Dictionary:
    if String(armistice.get("status", "")) != "active":
        return {"allowed": true, "breach": false}
    if current_turn > int(armistice.get("end_turn", current_turn)):
        return {"allowed": true, "breach": false, "expired": true}

    var action_type := String(action.get("type", ""))
    var scoped := _action_in_scope(armistice, action)
    if not scoped:
        return {"allowed": true, "breach": false}

    var breach := false
    match action_type:
        "attack", "siege_assault", "raid":
            breach = true
        "move":
            var policy := String(armistice.get("movement_policy", "limited"))
            if policy == "prohibited": breach = true
            elif policy == "rear_only" and bool(action.get("toward_front", false)): breach = true
            elif policy == "limited" and bool(action.get("crosses_front", false)): breach = true
        "reinforce":
            breach = not bool(armistice.get("reinforcement_allowed", false))
        "recruit":
            breach = not bool(armistice.get("recruitment_allowed", false))
        "repair_wall":
            breach = not bool(armistice.get("wall_repair_allowed", false))
        "stockpile_supply":
            breach = not bool(armistice.get("supply_stockpiling_allowed", true))

    return {
        "allowed": not breach,
        "breach": breach,
        "effects": {"legitimacy": -12, "infamy": 18, "trust": -20, "future_acceptance": -15} if breach else {},
    }

func finalize(negotiation: Dictionary, outcome: String, terms: Dictionary) -> Dictionary:
    if outcome not in OUTCOMES:
        return {"accepted": false, "reason": "알 수 없는 협상 결과다."}
    negotiation.stage = "final_agreement"
    negotiation.status = "completed" if outcome != "war_resumes" else "collapsed"
    negotiation.outcome = outcome
    negotiation.final_terms = terms.duplicate(true)
    negotiation.history.append(_entry("협상이 '%s' 결과로 종료되었다." % outcome, "final_agreement", terms))
    return {"accepted": true, "state": negotiation, "outcome": outcome, "terms": terms}

func _action_in_scope(armistice: Dictionary, action: Dictionary) -> bool:
    var scope_type := String(armistice.get("scope_type", "all_fronts"))
    if scope_type == "all_fronts" or scope_type == "negotiation_period":
        return true
    var scope_ids: Array = armistice.get("scope_ids", [])
    match scope_type:
        "province": return action.get("province_id", "") in scope_ids
        "front": return action.get("front_id", "") in scope_ids
        "siege": return action.get("settlement_id", "") in scope_ids
        "prisoner_exchange": return String(action.get("type", "")) == "prisoner_exchange"
    return false

func _entry(message: String, stage: String, data: Dictionary) -> Dictionary:
    return {"message": message, "stage": stage, "stage_name": STAGE_NAMES.get(stage, stage), "data": data.duplicate(true)}
