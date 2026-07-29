extends SceneTree

const FoundationScript = preload("res://src/world/east_asia_world_foundation.gd")
var failures: Array[String] = []

class MockGovernance:
	extends RefCounted
	var factions := {}
	var provinces := {}
	var political_groups := {}
	func register_faction(faction: Dictionary) -> void:
		var id := String(faction.get("faction_id",""))
		factions[id] = faction
		political_groups[id] = {}
	func register_province(province: Dictionary) -> void:
		provinces[String(province.get("province_id",""))] = province
	func register_group(faction_id: String, group: Dictionary) -> void:
		political_groups[faction_id][String(group.get("group_id",""))] = group

func _initialize() -> void:
	var foundation = FoundationScript.new()
	var loaded: Dictionary = foundation.load_prototype()
	_check(bool(loaded.get("ok",false)), "동아시아 프로토타입 데이터 로드")
	if not bool(loaded.get("ok",false)):
		for error_value in loaded.get("errors",[loaded.get("error","unknown")]): push_error(String(error_value))
		_finish()
		return
	_test_catalog(foundation,loaded)
	_test_registration(foundation)
	_test_governments(foundation)
	_test_control(foundation)
	_test_rebellion(foundation)
	_finish()

func _test_catalog(foundation, loaded: Dictionary) -> void:
	var counts: Dictionary = loaded.counts
	_check(int(counts.regions) == 13,"지역 13개")
	_check(int(counts.countries) == 14,"국가·후보 14개")
	_check(int(counts.provinces) == 13,"프로빈스 13개")
	_check(int(counts.strategic_points) == 65,"핵심 지점 65개")
	_check(int(counts.characters) == 16,"인물 16명")
	_check(int(counts.political_groups) == 70,"정치 집단 70개")
	_check(int(counts.government_types) == 6,"통치체제 6종")
	_check(bool(foundation.loader.last_validation.ok),"교차 참조 검증")
	var province: Dictionary = foundation.loader.get_province("guknae_basin")
	var governor: Dictionary = foundation.loader.get_character(String(province.governor_character_id))
	_check(province.strategic_point_ids.size() == 5,"프로빈스 핵심 지점 5~8개")
	_check(not governor.is_empty() and bool(governor.is_fictional),"이름 있는 가상 통치자")
	_check(province.owner_faction_id == "goguryeo" and province.controller_faction_id == "goguryeo","소유권·군사 통제 분리")

func _test_registration(foundation) -> void:
	var mock := MockGovernance.new()
	var result: Dictionary = foundation.register_with_governance(mock)
	_check(bool(result.ok),"독립 등록 API")
	_check(mock.factions.size() == 14 and mock.provinces.size() == 13,"국가·프로빈스 전체 등록")
	for country_id in mock.factions.keys(): _check(mock.political_groups[country_id].size() == 5,"%s 정치 집단 5개" % country_id)

func _test_governments(foundation) -> void:
	var required := ["central_tax_efficiency","local_mobilization","command_transmission_speed","governor_autonomy","administrative_cost","private_army_allowance","local_rebellion_risk","central_army_upkeep","required_officials","reform_requirements","supporter_group_types","opponent_group_types"]
	for value in foundation.loader.dataset.government_types.government_types:
		var definition: Dictionary = value
		for field in required: _check(definition.has(field),"%s.%s" % [definition.id,field])
	var stages: Array = foundation.loader.dataset.government_types.reform_stages
	_check(stages.size() == 3,"개혁 3단계")
	for value in stages:
		var stage: Dictionary = value
		_check(stage.has("base_turns") and stage.has("base_cost") and not stage.progress_conditions.is_empty() and not stage.failure_results.is_empty(),"개혁 단계 턴·비용·조건·실패")

func _test_control(foundation) -> void:
	var province: Dictionary = foundation.loader.get_province("han_river_basin")
	province.control_progress_hidden = 50.0
	var control: Dictionary = foundation.province_control.evaluate_world_control(province,{"core_city_held":true,"major_forts_held":1,"minor_points_held":2,"garrison_strength_ratio":0.8,"supply_connected":true,"road_connected":true,"resident_support_hidden":72,"governor_cooperation":true,"enemy_remaining_strength_ratio":0.1,"adjacent_friendly_ratio":0.67,"occupation_turns":3,"occupation_policy":"relief"})
	_check(float(control.after) > 50.0 and String(control.stage_id) in ["advantage","de_facto","full_control"],"통제율 요인·단계 계산")
	var yielding := {"personality_traits":["cautious"],"loyalty_hidden":18,"ambition_hidden":35,"administration":58,"military":22,"local_base_hidden":20,"surrender_tendency_hidden":92,"betrayal_risk_hidden":30}
	var decision: Dictionary = foundation.province_control.decide_governor_response(yielding,{"control_progress_hidden":98},{"defending_legitimacy_hidden":25,"attacker_legitimacy_hidden":80,"relief_probability":5,"garrison_strength_ratio":0.1,"battle_outlook":-0.9})
	_check(String(decision.decision) in ["unconditional_surrender","conditional_autonomy","seek_armistice"],"항복·휴전 결정")
	yielding.personality_traits = ["defiant","resolute"]
	yielding.loyalty_hidden = 92
	yielding.military = 88
	yielding.local_base_hidden = 85
	yielding.surrender_tendency_hidden = 8
	decision = foundation.province_control.decide_governor_response(yielding,{"control_progress_hidden":62},{"defending_legitimacy_hidden":82,"relief_probability":78,"garrison_strength_ratio":1.1,"battle_outlook":0.4,"foreign_aid_available":true})
	_check(String(decision.decision) in ["resist","request_foreign_aid"],"항전·원군 결정")

func _test_rebellion(foundation) -> void:
	var groups: Array[Dictionary] = [
		{"group_id":"test.aristocracy","group_type":"aristocracy","influence_hidden":82,"satisfaction_hidden":14,"rebellion_risk_hidden":78,"mobilization_capacity":70,"active_causes":["oppose_reform"],"representative_character_id":"char_gog_jumonghae"},
		{"group_id":"test.military","group_type":"military","influence_hidden":67,"satisfaction_hidden":18,"rebellion_risk_hidden":72,"mobilization_capacity":65,"active_causes":["oppose_reform"],"representative_character_id":"char_gog_yeonmujin"},
	]
	var context := {"faction_id":"goguryeo","capital_control_weak":true,"secured_fortress":true,"private_army":true,"incompatible_group_pairs":[]}
	var coalition: Dictionary = foundation.coalition_eligibility("goguryeo",groups,context)
	_check(bool(coalition.eligible),"공동반란 복합 조건")
	var incompatible: Dictionary = context.duplicate(true)
	incompatible.incompatible_group_pairs = [["test.aristocracy","test.military"]]
	_check(not bool(foundation.coalition_eligibility("goguryeo",groups,incompatible).eligible),"요구 비양립 차단")
	var rebels: Array[Dictionary] = foundation.create_coalition_rebellions(coalition,{"test.aristocracy":groups[0],"test.military":groups[1]},["guknae_basin","pyongyang_basin"])
	_check(rebels.size() == 2 and rebels[0].rebellion_id != rebels[1].rebellion_id,"집단별 별도 반란 생성")
	_check(bool(rebels[0].is_separate_faction) and rebels[0].coalition_alliance_id == rebels[1].coalition_alliance_id,"별도 세력·공동 적 동맹")
	var rebel_state := {"name":"시험 반란군","leader_character_id":"char_gog_jumonghae","occupied_province_ids":["guknae_basin","pyongyang_basin"],"troops":2200,"food":1700,"support_hidden":68,"legitimacy_claim":"restore_dynasty","turns_survived":5,"tax_capacity":true,"core_city_or_fortress":true}
	_check(bool(foundation.evaluate_rebel_statehood(rebel_state,{"controlled_population":99000}).can_declare),"반란국가 선포 조건")
	rebel_state.tax_capacity = false
	_check(not bool(foundation.evaluate_rebel_statehood(rebel_state,{"controlled_population":99000}).can_declare),"조건 전 반란 점령지 유지")
	var identity: Dictionary = foundation.choose_rebel_state_identity(rebel_state,["sp_guknae_city","sp_pyongyang_city"],{"controlled_region_ids":["northern_korea"],"culture_ids":["goguryeo","yemaek"]})
	_check(identity.state_name == "고구려","역사 국호 우선순위")
	_check(identity.capital_id == "sp_guknae_city","수도 후보 종합 점수")

func _check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("[PASS] East Asia world foundation test suite")
		quit(0)
	else:
		for failure in failures: push_error("[FAIL] %s" % failure)
		quit(1)
