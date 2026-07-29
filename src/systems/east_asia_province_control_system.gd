class_name EastAsiaProvinceControlSystem
extends RefCounted

const StageScale = preload("res://src/systems/stage_scale.gd")
const CONTROL_FACTORS := {
	"core_city_held":22.0,"major_fort_held":10.0,"minor_point_held":4.0,
	"supply_connected":12.0,"road_connected":6.0,"governor_cooperation":15.0,
	"enemy_field_army_present":-18.0,"active_resistance":-15.0,
	"occupation_turn":3.0,"pillage":-12.0,"forced_labor":-8.0,"relief":10.0,
}

func evaluate_world_control(province: Dictionary, factors: Dictionary) -> Dictionary:
	var before := float(province.get("control_progress_hidden", 0.0))
	var delta := 0.0
	var reasons: Array[Dictionary] = []
	delta += _boolean_factor(factors, "core_city_held", "core_city_held", "중심 도시 장악", reasons)
	var forts := int(factors.get("major_forts_held", 0))
	var minor_points := int(factors.get("minor_points_held", 0))
	delta += float(forts) * CONTROL_FACTORS.major_fort_held
	delta += float(minor_points) * CONTROL_FACTORS.minor_point_held
	if forts > 0: reasons.append({"label":"요새·관문 장악","value":float(forts) * CONTROL_FACTORS.major_fort_held})
	if minor_points > 0: reasons.append({"label":"기타 핵심 지점 장악","value":float(minor_points) * CONTROL_FACTORS.minor_point_held})
	delta += _boolean_factor(factors, "supply_connected", "supply_connected", "보급로 연결", reasons)
	delta += _boolean_factor(factors, "road_connected", "road_connected", "도로 연결", reasons)
	delta += _boolean_factor(factors, "governor_cooperation", "governor_cooperation", "지방 통치자 협조", reasons)
	delta += _boolean_factor(factors, "active_resistance", "active_resistance", "적극 저항", reasons)
	var garrison_ratio := clampf(float(factors.get("garrison_strength_ratio", 0.0)), 0.0, 1.5)
	var resident_support := clampf(float(factors.get("resident_support_hidden", 50.0)), 0.0, 100.0)
	var enemy_ratio := clampf(float(factors.get("enemy_remaining_strength_ratio", 0.0)), 0.0, 1.0)
	var adjacent_ratio := clampf(float(factors.get("adjacent_friendly_ratio", 0.0)), 0.0, 1.0)
	var field_value := garrison_ratio * 10.0 + (resident_support - 50.0) * 0.16 - enemy_ratio * 12.0 + adjacent_ratio * 8.0
	delta += field_value
	reasons.append({"label":"주둔군·주민 지지·적 잔존 병력·주변 프로빈스","value":field_value})
	var occupation_turns := mini(int(factors.get("occupation_turns", 0)), 5)
	if occupation_turns > 0:
		var occupation_value := float(occupation_turns) * CONTROL_FACTORS.occupation_turn
		delta += occupation_value
		reasons.append({"label":"점령 유지 기간","value":occupation_value})
	var policy := String(factors.get("occupation_policy", "neutral"))
	if CONTROL_FACTORS.has(policy):
		delta += float(CONTROL_FACTORS[policy])
		reasons.append({"label":"점령 정책: %s" % policy,"value":float(CONTROL_FACTORS[policy])})
	var limit := float(factors.get("per_turn_control_limit", 24.0))
	delta = clampf(delta, -limit, limit)
	var after: float = StageScale.clamp_hidden(before + delta)
	var old_stage: Dictionary = StageScale.stage(before, StageScale.CONTROL)
	var new_stage: Dictionary = StageScale.stage(after, StageScale.CONTROL)
	return {
		"before":before,"after":after,"delta":delta,
		"stage_id":new_stage.get("id","unsecured"),"stage_name":new_stage.get("name","미확보"),
		"stage_changed":old_stage.get("id","") != new_stage.get("id",""),
		"proximity":StageScale.proximity_to_next_stage(after, StageScale.CONTROL),
		"reasons":reasons,"political_transfer_ready":after >= 75.0,"full_control":after >= 95.0,
	}

func decide_governor_response(governor: Dictionary, province: Dictionary, war: Dictionary) -> Dictionary:
	var control := float(province.get("control_progress_hidden", 0.0))
	var loyalty := _hidden(governor, "loyalty_hidden", "loyalty", 50.0)
	var ambition := _hidden(governor, "ambition_hidden", "ambition", 50.0)
	var local_base := _hidden(governor, "local_base_hidden", "local_base", 50.0)
	var surrender_tendency := _hidden(governor, "surrender_tendency_hidden", "surrender_tendency", 50.0)
	var betrayal_risk := _hidden(governor, "betrayal_risk_hidden", "betrayal_risk", 0.0)
	var military := float(governor.get("military", 50.0))
	var administration := float(governor.get("administration", 50.0))
	var defending_legitimacy := float(war.get("defending_legitimacy_hidden", 50.0))
	var attacker_legitimacy := float(war.get("attacker_legitimacy_hidden", 50.0))
	var relief := float(war.get("relief_probability", 0.0))
	var garrison := float(war.get("garrison_strength_ratio", 0.5))
	var outlook := clampf(float(war.get("battle_outlook", 0.0)), -1.0, 1.0)
	var coup_pressure := float(war.get("coup_pressure", 0.0))
	var scores := {
		"unconditional_surrender":control * 0.52 + surrender_tendency * 0.30 + (100.0 - loyalty) * 0.18 - relief * 0.18,
		"conditional_autonomy":control * 0.30 + ambition * 0.28 + local_base * 0.30 + administration * 0.12,
		"request_vassalage":control * 0.25 + ambition * 0.35 + local_base * 0.20 + attacker_legitimacy * 0.20,
		"seek_armistice":control * 0.28 + administration * 0.22 + (100.0 - relief) * 0.22 + (1.0 - outlook) * 14.0,
		"flee":control * 0.32 + (100.0 - loyalty) * 0.25 + ambition * 0.18 + betrayal_risk * 0.25,
		"resist":loyalty * 0.27 + military * 0.24 + local_base * 0.18 + defending_legitimacy * 0.14 + relief * 0.12 + garrison * 10.0 + outlook * 10.0,
		"request_foreign_aid":loyalty * 0.16 + military * 0.18 + relief * 0.30 + defending_legitimacy * 0.16 + local_base * 0.10,
		"replaced_by_coup":coup_pressure * 0.70 + betrayal_risk * 0.20 + (100.0 - local_base) * 0.10,
	}
	var traits: Array = governor.get("personality_traits", [])
	if "defiant" in traits or "resolute" in traits: scores.resist += 14.0
	if "cautious" in traits: scores.seek_armistice += 9.0
	if "pragmatic" in traits or "conciliatory" in traits: scores.conditional_autonomy += 9.0
	if "ambitious" in traits or "warlord" in traits: scores.request_vassalage += 8.0
	if not bool(war.get("foreign_escape_available", false)): scores.flee = -INF
	if not bool(war.get("foreign_aid_available", false)): scores.request_foreign_aid = -INF
	if coup_pressure < 55.0: scores.replaced_by_coup -= 45.0
	if control < 55.0:
		scores.unconditional_surrender -= 35.0
		scores.conditional_autonomy -= 25.0
		scores.request_vassalage -= 20.0
	var decision := "resist"
	var winning_score := -INF
	for decision_value in scores.keys():
		var candidate := String(decision_value)
		if float(scores[candidate]) > winning_score:
			winning_score = float(scores[candidate])
			decision = candidate
	return {"decision":decision,"explanation":_decision_explanation(decision),"scores":scores,"winning_score":winning_score}

func political_transfer_allowed(control_result: Dictionary, governor_decision: String, peace_terms: Dictionary = {}) -> bool:
	if bool(peace_terms.get("transfer_province", false)): return true
	if not bool(control_result.get("political_transfer_ready", false)): return false
	return governor_decision in ["unconditional_surrender","conditional_autonomy","request_vassalage","replaced_by_coup"]

func _boolean_factor(context: Dictionary, context_key: String, factor_key: String, label: String, reasons: Array[Dictionary]) -> float:
	if not bool(context.get(context_key, false)): return 0.0
	var value := float(CONTROL_FACTORS.get(factor_key, 0.0))
	reasons.append({"label":label,"value":value})
	return value

func _hidden(source: Dictionary, hidden_key: String, legacy_key: String, fallback: float) -> float:
	return float(source[hidden_key]) if source.has(hidden_key) else float(source.get(legacy_key, fallback))

func _decision_explanation(decision: String) -> String:
	var labels := {
		"unconditional_surrender":"군사 통제와 구원 가능성을 고려해 무조건 항복한다.",
		"conditional_autonomy":"현지 기반과 지위를 보존하는 자치 조건 항복을 제안한다.",
		"request_vassalage":"직접 편입 대신 봉신 편입을 요청한다.",
		"seek_armistice":"전황을 재정비하기 위한 휴전을 요청한다.",
		"flee":"가문과 잔존 병력을 보존하기 위해 도주한다.",
		"resist":"충성도·군사력·현지 기반을 믿고 항전한다.",
		"request_foreign_aid":"외국 원군을 요청하며 항전을 지속한다.",
		"replaced_by_coup":"내부 쿠데타로 통치자가 교체된다.",
	}
	return String(labels.get(decision, "통치자가 전황에 따라 결정을 내린다."))
