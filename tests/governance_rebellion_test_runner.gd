extends SceneTree

const GovernanceSessionScript = preload("res://src/governance/governance_session.gd")

var failures: Array[String] = []

func _initialize() -> void:
    var session = GovernanceSessionScript.new()
    _test_definition_loading(session)
    _test_province_control(session)
    _test_reform_flow(session)
    _test_group_stages_and_coalition(session)
    _test_rebellion_statehood(session)
    _test_negotiation_and_armistice(session)

    if failures.is_empty():
        print("[PASS] governance/rebellion test suite")
        quit(0)
    else:
        for failure in failures:
            push_error("[FAIL] %s" % failure)
        quit(1)

func _test_definition_loading(session) -> void:
    _check(not session.definitions.get("governments", {}).is_empty(), "통치체제 JSON을 불러와야 한다.")
    _check(session.government_definition("commandery_county").get("name", "") == "군현제", "군현제 정의가 존재해야 한다.")

func _test_province_control(session) -> void:
    session.register_province({
        "province_id": "P_TEST",
        "name": "시험군",
        "owner_faction_id": "F_OLD",
        "controller_faction_id": "F_NEW",
        "control_progress_hidden": 45.0,
        "governor_character_id": "C_GOV",
        "governor_type": "hereditary_lord",
        "strategic_point_ids": ["CITY", "FORT", "FORD", "MINE", "ROAD"],
    })
    var result = session.update_province_control("P_TEST", {
        "core_city_held": true,
        "major_forts_held": 1,
        "minor_points_held": 2,
        "supply_connected": true,
        "road_connected": true,
        "governor_cooperation": false,
        "active_resistance": true,
        "occupation_turns": 2,
        "occupation_policy": "relief",
    }, {
        "governor_type": "hereditary_lord",
        "loyalty": 55,
        "ambition": 70,
        "local_base": 80,
        "courage": 45,
    }, {
        "relief_probability": 10,
        "garrison_strength_ratio": 0.4,
        "foreign_escape_available": true,
    })
    _check(bool(result.get("accepted", false)), "프로빈스 통제 갱신이 승인되어야 한다.")
    _check(float(result.control.after) > 45.0, "중심 도시·보급·구휼은 통제율을 높여야 한다.")
    _check(String(result.governor_decision.get("decision", "")) in ["conditional_autonomy", "request_vassalage", "seek_armistice", "flee", "resist", "unconditional_surrender"], "통치자 결정을 반환해야 한다.")

func _test_reform_flow(session) -> void:
    session.register_faction({
        "faction_id": "F_TEST",
        "name": "시험국",
        "government_type": "aristocratic_council",
        "authority_hidden": 85.0,
        "legitimacy_hidden": 70.0,
        "administration_capacity": 90,
        "treasury": 5000,
        "technology_tags": ["household_register", "land_survey", "central_law", "imperial_bureaucracy", "standardized_law", "national_census"],
    })
    _register_default_groups(session, "F_TEST")
    var start = session.start_reform("F_TEST", "commandery_county", {})
    _check(bool(start.get("accepted", false)), "조건을 충족하면 군현제 개혁을 시작해야 한다.")
    _check(String(start.state.get("stage", "")) == "preparation", "개혁은 준비 단계에서 시작해야 한다.")

    var result = session.respond_to_reform_opposition("F_TEST", "negotiate", "aristocracy")
    _check(bool(result.get("accepted", false)), "협상 대응이 적용되어야 한다.")

    for index in range(24):
        session.advance_turn({
            "group_contexts": {"F_TEST": {}},
            "reform_contexts": {"F_TEST": {}},
            "coalition_contexts": {"F_TEST": {}},
        })
        if String(session.factions.F_TEST.get("government_type", "")) == "commandery_county":
            break
    _check(String(session.factions.F_TEST.get("government_type", "")) == "commandery_county", "충분한 진행 후 군현제가 정착해야 한다.")

func _test_group_stages_and_coalition(session) -> void:
    var rebellion_system = session.rebellion_system
    var groups: Array[Dictionary] = [
        {
            "group_id": "aristocracy",
            "group_type": "aristocracy",
            "influence_hidden": 82.0,
            "satisfaction_hidden": 12.0,
            "rebellion_risk_hidden": 75.0,
            "mobilization_capacity": 80.0,
            "active_causes": ["oppose_reform"],
        },
        {
            "group_id": "military",
            "group_type": "military",
            "influence_hidden": 65.0,
            "satisfaction_hidden": 18.0,
            "rebellion_risk_hidden": 70.0,
            "mobilization_capacity": 75.0,
            "active_causes": ["oppose_reform"],
        },
    ]
    var eligibility = rebellion_system.coalition_eligibility(groups, {
        "capital_control_weak": true,
        "major_defeat": true,
        "secured_fortress": true,
        "secret_meetings": true,
        "fund_transfers": true,
        "incompatible_group_pairs": [],
    })
    _check(bool(eligibility.get("eligible", false)), "복합 요건을 충족하면 공동반란이 가능해야 한다.")
    var by_id := {"aristocracy": groups[0], "military": groups[1]}
    var rebellions = rebellion_system.create_separate_rebellions(eligibility, by_id, ["P_A", "P_B"])
    _check(rebellions.size() == 2, "공동반란도 집단별 별도 반란 세력으로 생성되어야 한다.")
    _check(rebellions[0].rebellion_id != rebellions[1].rebellion_id, "각 반란은 독립 ID를 가져야 한다.")

func _test_rebellion_statehood(session) -> void:
    var rebellion := {
        "rebellion_id": "REB_TEST",
        "name": "시험 반란군",
        "leader_character_id": "C_LEADER",
        "occupied_province_ids": ["P_A", "P_B"],
        "troops": 3000,
        "food": 2400,
        "support_hidden": 80.0,
        "legitimacy_claim": "restore_dynasty",
        "turns_survived": 6,
        "tax_capacity": true,
        "core_city_or_fortress": true,
        "foreign_recognition": true,
    }
    var result = session.rebellion_system.evaluate_statehood(rebellion, {
        "controlled_population": 60000,
        "parent_state_weak": true,
    })
    _check(bool(result.get("can_declare", false)), "국가 선포 요건을 충족하면 정식 국가가 될 수 있어야 한다.")
    var identity = session.rebellion_system.choose_state_identity(rebellion, [
        {"type": "historical_regional_state", "name": "진국", "available": true},
        {"type": "generated_name", "name": "시험국", "available": true},
    ], [
        {"id": "CITY_A", "name": "고도", "historical_center": true, "defense": 50, "logistics": 50},
        {"id": "CITY_B", "name": "산성", "historical_center": false, "defense": 90, "logistics": 20},
    ])
    _check(String(identity.get("state_name", "")) == "진국", "역사적 국호 후보를 우선 선택해야 한다.")
    _check(String(identity.get("capital_id", "")) == "CITY_A", "역사적 중심지를 수도로 우선해야 한다.")

func _test_negotiation_and_armistice(session) -> void:
    var negotiation = session.begin_negotiation("REB_TEST", "F_TEST", {"deadline_turns": 5})
    var negotiation_id := String(negotiation.get("negotiation_id", ""))
    var demand_list: Array[Dictionary] = [
        {"type": "state_name", "value": "진국"},
        {"type": "tax_rights", "scale": 0.8},
    ]
    var demands = session.propose_negotiation_demands(negotiation_id, "REB_TEST", demand_list, {
        "territory_share": 0.5,
        "troop_ratio": 0.8,
        "food_security": 0.8,
        "popular_support": 0.7,
        "legitimacy": 0.8,
    })
    _check(bool(demands.get("accepted", false)), "단계형 협상에서 요구안을 제출할 수 있어야 한다.")

    var armistice = session.propose_armistice(negotiation_id, "REB_TEST", {
        "duration_turns": 3,
        "scope_type": "province",
        "scope_ids": ["P_A"],
        "movement_policy": "rear_only",
        "reinforcement_allowed": false,
        "recruitment_allowed": true,
        "wall_repair_allowed": false,
        "supply_stockpiling_allowed": true,
        "prisoner_exchange": true,
        "auto_resume_war": true,
    })
    _check(bool(armistice.get("accepted", false)), "휴전 기간과 조건을 직접 제안할 수 있어야 한다.")
    var accepted = session.negotiation_system.accept_armistice(session.negotiations[negotiation_id], "F_TEST")
    _check(bool(accepted.get("accepted", false)), "상대가 휴전을 수락할 수 있어야 한다.")
    var breach = session.negotiation_system.check_armistice_action(accepted.armistice, {
        "type": "attack",
        "province_id": "P_A",
    }, session.turn)
    _check(bool(breach.get("breach", false)), "휴전 범위 내 공격은 위반이어야 한다.")

func _register_default_groups(session, faction_id: String) -> void:
    session.register_group(faction_id, {
        "group_id": "aristocracy",
        "group_type": "aristocracy",
        "name": "귀족",
        "influence_hidden": 65.0,
        "satisfaction_hidden": 55.0,
        "rebellion_risk_hidden": 15.0,
        "mobilization_capacity": 60.0,
        "reform_stance": "oppose",
        "interests": ["hereditary_rights", "private_armies"],
    })
    session.register_group(faction_id, {
        "group_id": "military",
        "group_type": "military",
        "name": "군부",
        "influence_hidden": 50.0,
        "satisfaction_hidden": 60.0,
        "rebellion_risk_hidden": 10.0,
        "mobilization_capacity": 55.0,
        "reform_stance": "neutral",
        "interests": ["command_rights", "pay"],
    })
    session.register_group(faction_id, {
        "group_id": "bureaucracy",
        "group_type": "bureaucracy",
        "name": "관료",
        "influence_hidden": 60.0,
        "satisfaction_hidden": 70.0,
        "rebellion_risk_hidden": 5.0,
        "mobilization_capacity": 30.0,
        "reform_stance": "support",
        "interests": ["office_structure", "law"],
    })

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
