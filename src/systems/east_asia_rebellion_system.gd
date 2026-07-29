class_name EastAsiaRebellionSystem
extends RefCounted

const StageScale = preload("res://src/systems/stage_scale.gd")
const GROUP_GOALS := {
	"aristocracy":{"goal":"restore_privileges","movement_type":"aristocratic_revolt","name":"귀족 반란군"},
	"military":{"goal":"seize_command","movement_type":"military_junta","name":"군부 반란군"},
	"bureaucracy":{"goal":"restore_old_order","movement_type":"bureaucratic_opposition","name":"관료 반대파"},
	"religious_estate":{"goal":"restore_religious_policy","movement_type":"religious_revolt","name":"종교 반란군"},
	"local_populace":{"goal":"tax_and_corvee_relief","movement_type":"popular_revolt","name":"지방민 반란군"},
}

func coalition_eligibility_with_rules(groups: Array[Dictionary], context: Dictionary, rules: Dictionary) -> Dictionary:
	var config: Dictionary = rules.get("coalition_rebellion", rules)
	var discontent: Array[String] = []
	var strong: Array[String] = []
	var shared_causes := {}
	var mobilization := 0.0
	for group in groups:
		var group_id := String(group.get("group_id", ""))
		if float(group.get("satisfaction_hidden", 50.0)) <= float(config.get("discontent_satisfaction_max", 39.0)):
			discontent.append(group_id)
			mobilization += float(group.get("mobilization_capacity", 0.0))
			for cause_value in group.get("active_causes", []):
				var cause := String(cause_value)
				shared_causes[cause] = int(shared_causes.get(cause, 0)) + 1
		if float(group.get("influence_hidden", 50.0)) >= float(config.get("strong_influence_min", 60.0)):
			strong.append(group_id)
	var shared_count := 0
	for count_value in shared_causes.values():
		if int(count_value) >= 2: shared_count += 1
	var crisis_met := _any_context_flag(context, config.get("required_crises_any", []))
	var category_count := 0
	for keys_value in config.get("asset_categories", {}).values():
		if _any_context_flag(context, keys_value): category_count += 1
	var compatible := true
	for pair_value in context.get("incompatible_group_pairs", []):
		if pair_value is Array and pair_value.size() >= 2 and String(pair_value[0]) in discontent and String(pair_value[1]) in discontent:
			compatible = false
	var missing: Array[String] = []
	if discontent.size() < int(config.get("minimum_discontent_groups", 2)): missing.append("둘 이상의 불만 집단")
	if strong.size() < int(config.get("minimum_strong_groups", 1)): missing.append("강한 영향력 집단")
	if shared_count < int(config.get("required_shared_causes", 1)): missing.append("공통 반대 명분")
	if not crisis_met: missing.append("국가적 위기")
	if category_count < int(config.get("minimum_asset_categories", 1)): missing.append("병력·거점·연락망")
	if mobilization < float(config.get("minimum_combined_mobilization", 0.0)): missing.append("동원 역량")
	if bool(config.get("compatibility_required", true)) and not compatible: missing.append("요구 양립 가능성")
	return {"eligible":missing.is_empty(),"groups":discontent,"strong_groups":strong,"shared_causes":shared_causes,"missing":missing,"faction_id":String(context.get("faction_id","")),"coalition_id":String(context.get("coalition_id","COALITION_%s" % String(context.get("faction_id","UNKNOWN")).to_upper()))}

func create_separate_rebellions_from_coalition(coalition: Dictionary, groups_by_id: Dictionary, origin_provinces: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var group_ids: Array = coalition.get("groups", [])
	var source_id := String(coalition.get("faction_id", "UNKNOWN")).to_upper()
	var alliance_id := String(coalition.get("coalition_id", "COALITION_%s" % source_id))
	for index in range(group_ids.size()):
		var group_id := String(group_ids[index])
		if not groups_by_id.has(group_id): continue
		var group: Dictionary = groups_by_id[group_id]
		var group_type := String(group.get("group_type", group_id))
		var defaults: Dictionary = GROUP_GOALS.get(group_type, {"goal":"oppose_government","movement_type":"regional_revolt","name":"지역 반란군"})
		var province_id := String(origin_provinces[index % origin_provinces.size()]) if not origin_provinces.is_empty() else ""
		result.append({
			"rebellion_id":"REB_%s_%s_%d" % [source_id, group_type.to_upper(), index + 1],
			"name":defaults.name,"group_id":group_id,"group_type":group_type,
			"movement_type":defaults.movement_type,"goal":defaults.goal,
			"leader_character_id":String(group.get("representative_character_id","")),
			"occupied_province_ids":[province_id] if province_id != "" else [],
			"controlled_settlement_ids":[],"troops":maxi(int(group.get("mobilization_capacity",0)) * 20,200),
			"food":maxi(int(group.get("mobilization_capacity",0)) * 12,100),
			"support_hidden":float(group.get("rebellion_risk_hidden",50.0)),
			"legitimacy_claim":String(group.get("legitimacy_claim",defaults.goal)),
			"turns_survived":0,"tax_capacity":false,"core_city_or_fortress":false,
			"declared_faction_id":"","statehood_progress":0.0,
			"parent_faction_id":String(coalition.get("faction_id","")),
			"coalition_alliance_id":alliance_id,"is_separate_faction":true,
			"diplomacy_status":"allied_against_parent","allied_rebellion_ids":[],"rival_rebellion_ids":[],
		})
	for rebellion in result:
		for other in result:
			if rebellion.rebellion_id != other.rebellion_id: rebellion.allied_rebellion_ids.append(other.rebellion_id)
	return result

func evaluate_statehood_with_rules(rebellion: Dictionary, world_context: Dictionary, rules: Dictionary) -> Dictionary:
	var config: Dictionary = rules.get("statehood_requirements", rules)
	var missing: Array[String] = []
	if rebellion.get("occupied_province_ids", []).size() < int(config.get("minimum_provinces",2)): missing.append("필요 프로빈스 수")
	if int(world_context.get("controlled_population",0)) < int(config.get("minimum_population",25000)): missing.append("필요 인구")
	if int(rebellion.get("turns_survived",0)) < int(config.get("minimum_survival_turns",4)): missing.append("최소 생존 턴")
	if int(rebellion.get("troops",0)) < int(config.get("minimum_troops",1500)): missing.append("병력")
	if int(rebellion.get("food",0)) < int(config.get("minimum_food",1200)): missing.append("식량")
	if float(rebellion.get("support_hidden",0.0)) < float(config.get("minimum_support_value",55.0)): missing.append("주민 지지")
	if bool(config.get("requires_named_leader",true)) and String(rebellion.get("leader_character_id","")) == "": missing.append("이름 있는 지도자")
	if bool(config.get("requires_core_city_or_fortress",true)) and not bool(rebellion.get("core_city_or_fortress",false)): missing.append("중심 도시 또는 핵심 요새")
	if bool(config.get("requires_legitimacy_claim",true)) and String(rebellion.get("legitimacy_claim","")) == "": missing.append("정치적 명분")
	if bool(config.get("requires_tax_capacity",true)) and not bool(rebellion.get("tax_capacity",false)): missing.append("행정·세금 능력")
	var completed := 10 - missing.size()
	var progress := clampf(float(completed) * 10.0,0.0,100.0)
	return {"can_declare":missing.is_empty(),"progress":progress,"missing":missing,"proximity":StageScale.stage(progress,StageScale.PROXIMITY)}

func choose_state_identity_from_catalog(rebellion: Dictionary, identity_data: Dictionary, controlled_points: Array, context: Dictionary = {}) -> Dictionary:
	var regions: Array = context.get("controlled_region_ids", [])
	var cultures: Array = context.get("culture_ids", [])
	var state_name := ""
	var name_source := "generated_name"
	var name_score := -INF
	for source_value in identity_data.get("name_priority", []):
		var source := String(source_value)
		for candidate_value in identity_data.get("state_name_candidates", []):
			if candidate_value is not Dictionary: continue
			var candidate: Dictionary = candidate_value
			if String(candidate.get("type","")) != source or not bool(candidate.get("available",true)): continue
			if not _candidate_matches(candidate.get("region_ids",[]),regions) or not _candidate_matches(candidate.get("culture_ids",[]),cultures): continue
			if float(candidate.get("priority_score",0.0)) > name_score:
				state_name = String(candidate.get("name",""))
				name_source = source
				name_score = float(candidate.get("priority_score",0.0))
		if state_name != "": break
	if state_name == "": state_name = "%s 정권" % String(rebellion.get("name","신생"))
	var controlled := {}
	for point_value in controlled_points: controlled[String(point_value)] = true
	var capital_id := ""
	var capital_name := ""
	var capital_score := -INF
	for candidate_value in identity_data.get("capital_candidates", []):
		if candidate_value is not Dictionary: continue
		var candidate: Dictionary = candidate_value
		var point_id := String(candidate.get("point_id",""))
		if not controlled.has(point_id): continue
		var score := float(candidate.get("historical_center_score",0.0)) * 0.30 + float(candidate.get("leader_home_score",0.0)) * 0.20 + float(candidate.get("former_capital_score",0.0)) * 0.15 + float(candidate.get("defense_score",0.0)) * 0.12 + float(candidate.get("transport_score",0.0)) * 0.08 + float(candidate.get("food_score",0.0)) * 0.07 + float(candidate.get("administration_score",0.0)) * 0.08
		if point_id == String(context.get("leader_home_point_id","")): score += 20.0
		if score > capital_score:
			capital_score = score
			capital_id = point_id
			capital_name = String(candidate.get("name",point_id))
	return {"state_name":state_name,"name_source":name_source,"name_priority_score":name_score,"capital_id":capital_id,"capital_name":capital_name,"capital_score":capital_score}

func _any_context_flag(context: Dictionary, keys: Array) -> bool:
	for key_value in keys:
		if bool(context.get(String(key_value),false)): return true
	return false

func _candidate_matches(candidate_values: Array, actual_values: Array) -> bool:
	if candidate_values.is_empty() or actual_values.is_empty(): return true
	for value in candidate_values:
		if value in actual_values: return true
	return false
