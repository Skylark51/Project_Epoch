class_name ProvincialGovernance
extends RefCounted


const DATA_PATH := "res://data/governance/provincial_governance.json"
const NotificationCenter = preload("res://src/core/epoch_notification_center.gd")

const DEFAULT_RULES := {
    "governance_levels": {
        "direct": {"name": "직접 통치", "command_precision": 1.0, "administrative_cost": 6.0, "growth_stability": 1.0, "policy_speed": 1.0, "corruption_bias": -7.0, "rebellion_bias": -5.0, "tax_multiplier": 1.0},
        "delegated": {"name": "방침 위임", "command_precision": 0.76, "administrative_cost": 3.0, "growth_stability": 0.72, "policy_speed": 0.72, "corruption_bias": 5.0, "rebellion_bias": 3.0, "tax_multiplier": 0.91},
        "autonomous": {"name": "완전 자율", "command_precision": 0.48, "administrative_cost": 1.0, "growth_stability": 0.58, "policy_speed": 0.42, "corruption_bias": 11.0, "rebellion_bias": 8.0, "tax_multiplier": 0.78},
    },
    "assimilation_policies": {
        "status_quo": {"name": "현상 유지", "political_loyalty_delta": 0.25, "civic_integration_delta": 0.05, "cultural_assimilation_delta": 0.0, "happiness_delta": 0.18, "unrest_delta": -0.2},
        "gradual": {"name": "완만한 통합", "political_loyalty_delta": 0.48, "civic_integration_delta": 0.38, "cultural_assimilation_delta": 0.22, "happiness_delta": 0.05, "unrest_delta": -0.08},
        "active": {"name": "적극적 통합", "political_loyalty_delta": 0.7, "civic_integration_delta": 0.72, "cultural_assimilation_delta": 0.55, "happiness_delta": -0.28, "unrest_delta": 0.25},
    },
    "occupation_stages": {
        "immediate": {"name": "점령 직후", "tax_multiplier": 0.22, "production_multiplier": 0.38, "manpower_multiplier": 0.18, "resistance": 70.0, "security": 24.0, "administrative_cost": 7.0, "diplomatic_dispute": 100.0},
        "sustained": {"name": "지속 통제", "tax_multiplier": 0.46, "production_multiplier": 0.58, "manpower_multiplier": 0.42, "resistance": 48.0, "security": 46.0, "administrative_cost": 5.0, "diplomatic_dispute": 72.0},
        "de_facto": {"name": "사실상 편입", "tax_multiplier": 0.77, "production_multiplier": 0.82, "manpower_multiplier": 0.7, "resistance": 23.0, "security": 68.0, "administrative_cost": 3.0, "diplomatic_dispute": 42.0},
        "formal": {"name": "정상 편입", "tax_multiplier": 1.0, "production_multiplier": 1.0, "manpower_multiplier": 1.0, "resistance": 4.0, "security": 86.0, "administrative_cost": 0.0, "diplomatic_dispute": 8.0},
    },
    "government_profiles": {},
    "policy_minimum_turns": 3,
    "policy_cooldown_turns": 2,
    "formal_integration_turns": 10,
}


var rules: Dictionary = DEFAULT_RULES.duplicate(true)


func _init() -> void:
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return
    var loaded: Variant = JSON.parse_string(file.get_as_text())
    if loaded is Dictionary:
        rules = _merge(DEFAULT_RULES, loaded)


func initialize_state(state) -> void:
    if state == null:
        return
    if state.notifications is not Array:
        state.notifications = []
    if state.ui_preferences is not Dictionary:
        state.ui_preferences = {}

    for country_id_value in state.countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = state.countries[country_id_value]
        if not country.has("administration_capacity"):
            country["administration_capacity"] = 30
        if not country.has("authority_hidden"):
            country["authority_hidden"] = float(country.get("stability", 50.0))
        if not country.has("legitimacy_hidden"):
            country["legitimacy_hidden"] = float(country.get("stability", 50.0))
        state.countries[country_id] = country

    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id_value]
        _ensure_province(state, province_id, province)
        state.provinces[province_id] = province

    _recalculate_administration(state)


func validate_governance_change(
    state,
    command: Dictionary
) -> Dictionary:
    var province_id := int(command.get("target_id", -1))
    var country_id := String(command.get("country_id", ""))
    if not state.provinces.has(province_id):
        return {"valid": false, "reason": "통치 대상 도시가 존재하지 않음"}
    var province: Dictionary = state.provinces[province_id]
    if String(province.get("owner_id", "")) != country_id:
        return {"valid": false, "reason": "정상 편입된 자국 도시에서만 통치 수준을 변경할 수 있음"}
    var level := String(command.get("payload", {}).get("governance_level", ""))
    if not rules.get("governance_levels", {}).has(level):
        return {"valid": false, "reason": "알 수 없는 통치 수준"}
    var allowed := allowed_levels(state, country_id)
    if level not in allowed:
        return {
            "valid": false,
            "reason": "%s 체제는 %s을(를) 허용하지 않음" % [
                government_appointment_mode(state, country_id),
                level_name(level),
            ],
        }
    return {"valid": true, "province_id": province_id, "level": level}


func validate_assimilation_policy(
    state,
    command: Dictionary
) -> Dictionary:
    var province_id := int(command.get("target_id", -1))
    var country_id := String(command.get("country_id", ""))
    if not state.provinces.has(province_id):
        return {"valid": false, "reason": "융화 정책 대상 도시가 존재하지 않음"}
    var province: Dictionary = state.provinces[province_id]
    if String(province.get("controller_id", "")) != country_id:
        return {"valid": false, "reason": "군사적으로 통제하지 않는 도시에는 정책을 지정할 수 없음"}
    var policy := String(command.get("payload", {}).get("policy", ""))
    if not rules.get("assimilation_policies", {}).has(policy):
        return {"valid": false, "reason": "알 수 없는 융화 정책"}
    if policy == String(province.get("assimilation_policy", "status_quo")):
        return {"valid": false, "reason": "이미 적용 중인 융화 정책"}
    var last_changed := int(province.get("assimilation_policy_changed_turn", 1))
    var minimum := int(rules.get("policy_minimum_turns", 3))
    if int(state.turn) - last_changed < minimum:
        return {
            "valid": false,
            "reason": "정책은 최소 %d턴 동안 유지해야 함" % minimum,
        }
    var cooldown_until := int(province.get("policy_cooldown_until", 1))
    if int(state.turn) < cooldown_until:
        return {
            "valid": false,
            "reason": "정책 재지정 대기 중 · %d턴부터 변경 가능" % cooldown_until,
        }
    return {"valid": true, "province_id": province_id, "policy": policy}


func prepare_local_command(state, command: Dictionary) -> Dictionary:
    var command_type := String(command.get("command_type", ""))
    if command_type not in ["recruit", "develop", "build_fort"]:
        return {"valid": true, "command": command.duplicate(true), "precision": 1.0}

    var province_id := int(command.get("target_id", command.get("source_id", -1)))
    if not state.provinces.has(province_id):
        return {"valid": true, "command": command.duplicate(true), "precision": 1.0}

    var province: Dictionary = state.provinces[province_id]
    var country_id := String(command.get("country_id", ""))
    if String(province.get("controller_id", "")) != country_id:
        return {"valid": true, "command": command.duplicate(true), "precision": 1.0}

    var stage := String(province.get("occupation_stage", "formal"))
    if stage == "immediate" and command_type == "recruit":
        return {
            "valid": false,
            "reason": "점령 직후에는 현지 징병 명령을 내릴 수 없음",
            "province_id": province_id,
        }
    if stage in ["immediate", "sustained"] and command_type in ["develop", "build_fort"]:
        return {
            "valid": false,
            "reason": "임시 점령 도시는 사실상 편입 전까지 직접 건설 명령이 제한됨",
            "province_id": province_id,
        }

    var level: Dictionary = rules.get("governance_levels", {}).get(
        String(province.get("governance_level", "direct")),
        rules.get("governance_levels", {}).get("direct", {})
    )
    var precision := clampf(float(level.get("command_precision", 1.0)), 0.1, 1.0)
    if command_type == "build_fort" and precision < 0.99:
        return {
            "valid": false,
            "reason": "요새 건설은 직접 통치에서만 정밀하게 지정할 수 있음",
            "province_id": province_id,
        }

    var normalized: Dictionary = command.duplicate(true)
    if command_type == "recruit":
        var requested := int(command.get("amount", 0))
        normalized["amount"] = maxi(1, floori(float(requested) * precision))
    var payload: Dictionary = normalized.get("payload", {}).duplicate(true)
    payload["governance_precision"] = precision
    normalized["payload"] = payload
    return {
        "valid": true,
        "command": normalized,
        "province_id": province_id,
        "precision": precision,
    }


func apply_development_precision(state, province_id: int, precision: float) -> void:
    if not state.provinces.has(province_id) or is_equal_approx(precision, 1.0):
        return
    var province: Dictionary = state.provinces[province_id]
    var correction := 2.0 * (clampf(precision, 0.1, 1.0) - 1.0)
    province["economy"] = maxf(0.0, float(province.get("economy", 0.0)) + correction)
    province["last_development_precision"] = precision
    state.provinces[province_id] = province

func execute_governance_change(state, command: Dictionary) -> Dictionary:
    var check := validate_governance_change(state, command)
    if not bool(check.get("valid", false)):
        return check
    var province_id := int(check.get("province_id", -1))
    var province: Dictionary = state.provinces[province_id]
    var previous_level := String(province.get("governance_level", "direct"))
    province["governance_level"] = String(check.get("level", "direct"))
    province["governance_turns"] = 0
    province["governor_appointment_mode"] = government_appointment_mode(
        state,
        String(command.get("country_id", ""))
    )
    if previous_level != String(check.get("level", "direct")):
        province["happiness"] = clampf(
            float(province.get("happiness", 60.0)) - 1.0,
            0.0,
            100.0
        )
    state.provinces[province_id] = province
    _recalculate_administration(state)
    return {
        "valid": true,
        "type": "change_governance",
        "province_id": province_id,
        "level": province["governance_level"],
    }


func execute_assimilation_policy(state, command: Dictionary) -> Dictionary:
    var check := validate_assimilation_policy(state, command)
    if not bool(check.get("valid", false)):
        return check
    var province_id := int(check.get("province_id", -1))
    var province: Dictionary = state.provinces[province_id]
    var previous_change := int(province.get("assimilation_policy_changed_turn", 1))
    var recent_change := int(state.turn) - previous_change < 6
    province["assimilation_policy"] = String(check.get("policy", "status_quo"))
    province["assimilation_policy_changed_turn"] = int(state.turn)
    province["policy_cooldown_until"] = int(state.turn) + int(
        rules.get("policy_cooldown_turns", 2)
    )
    if recent_change:
        province["happiness"] = clampf(
            float(province.get("happiness", 60.0)) - 4.0,
            0.0,
            100.0
        )
        province["local_stability"] = clampf(
            float(province.get("local_stability", 60.0)) - 3.0,
            0.0,
            100.0
        )
        province["unrest"] = clampf(
            float(province.get("unrest", 0.0)) + 4.0,
            0.0,
            100.0
        )
    state.provinces[province_id] = province
    return {
        "valid": true,
        "type": "set_assimilation_policy",
        "province_id": province_id,
        "policy": province["assimilation_policy"],
        "change_penalty": recent_change,
    }


func advance_turn(state) -> Array:
    initialize_state(state)
    var logs: Array = []
    _recalculate_administration(state)

    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id]
        var stage_before := String(province.get("occupation_stage", "formal"))
        _advance_occupation(state, province_id, province)
        _advance_assimilation(state, province)
        _apply_local_governance(state, province)
        _evaluate_risks(state, province_id, province)
        state.provinces[province_id] = province

        var stage_after := String(province.get("occupation_stage", "formal"))
        if stage_after != stage_before:
            logs.append({
                "type": "occupation_stage",
                "province_id": province_id,
                "stage": stage_after,
            })
            NotificationCenter.add(
                state,
                "important" if stage_after in ["immediate", "formal"] else "caution",
                "%s · %s" % [
                    String(province.get("name", "도시")),
                    occupation_stage_name(stage_after),
                ],
                _occupation_message(stage_after),
                "occupation:%d:%s" % [province_id, stage_after],
                {"type": "focus_province", "province_id": province_id},
                {"province_id": province_id, "country_id": province.get("controller_id", "")}
            )

    return logs


func apply_economic_effects(state) -> Array:
    var logs: Array = []
    var economy_config: Dictionary = state.balance.get("economy", {})
    var occupied_standard := float(
        economy_config.get("occupied_income_multiplier", 0.2)
    )

    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id]
        var owner_id := String(province.get("owner_id", ""))
        var controller_id := String(province.get("controller_id", owner_id))
        if not state.countries.has(owner_id) or not state.countries.has(controller_id):
            continue

        var owner: Dictionary = state.countries[owner_id]
        var base_income := float(province.get("economy", 0.0)) \
            * float(province.get("tax_efficiency", 1.0)) \
            * float(owner.get("tax_rate", 0.2)) \
            * (0.5 + float(owner.get("stability", 50.0)) / 200.0)
        var standard_income := base_income
        if owner_id != controller_id:
            standard_income *= occupied_standard

        var desired_income := base_income \
            * float(province.get("occupation_tax_multiplier", 1.0)) \
            * float(province.get("governance_tax_multiplier", 1.0))
        if owner_id == controller_id:
            owner["treasury"] = snappedf(
                float(owner.get("treasury", 0.0)) + desired_income - standard_income,
                0.01
            )
            state.countries[owner_id] = owner
        else:
            owner["treasury"] = snappedf(
                maxf(0.0, float(owner.get("treasury", 0.0)) - standard_income),
                0.01
            )
            var controller: Dictionary = state.countries[controller_id]
            controller["treasury"] = snappedf(
                float(controller.get("treasury", 0.0)) + desired_income,
                0.01
            )
            state.countries[owner_id] = owner
            state.countries[controller_id] = controller

        logs.append({
            "type": "governance_income",
            "province_id": province_id,
            "recipient_id": controller_id,
            "income": desired_income,
        })
    return logs


func apply_manpower_effects(state) -> Array:
    var logs: Array = []
    var economy_config: Dictionary = state.balance.get("economy", {})
    var recovery_rate := float(
        economy_config.get("manpower_recovery_rate", 0.01)
    )
    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id]
        var owner_id := String(province.get("owner_id", ""))
        var controller_id := String(province.get("controller_id", owner_id))
        if not state.countries.has(owner_id) or not state.countries.has(controller_id):
            continue

        var standard := int(float(province.get("manpower", 0)) * recovery_rate)
        var desired := int(float(standard) * float(
            province.get("occupation_manpower_multiplier", 1.0)
        ))
        if owner_id == controller_id:
            var owner: Dictionary = state.countries[owner_id]
            owner["manpower"] = int(owner.get("manpower", 0)) + desired - standard
            state.countries[owner_id] = owner
        else:
            var owner: Dictionary = state.countries[owner_id]
            owner["manpower"] = maxi(0, int(owner.get("manpower", 0)) - standard)
            var controller: Dictionary = state.countries[controller_id]
            controller["manpower"] = int(controller.get("manpower", 0)) + desired
            state.countries[owner_id] = owner
            state.countries[controller_id] = controller
        logs.append({
            "type": "governance_manpower",
            "province_id": province_id,
            "recipient_id": controller_id,
            "recovered": desired,
        })
    return logs


func apply_growth_effects(state) -> Array:
    var logs: Array = []
    var economy_config: Dictionary = state.balance.get("economy", {})
    var population_rate := float(economy_config.get("population_growth", 0.001))
    var economy_rate := float(economy_config.get("economy_growth", 0.001))
    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id]
        var growth_multiplier := float(province.get("governance_growth_multiplier", 1.0)) \
            * float(province.get("occupation_production_multiplier", 1.0))
        var adjustment := growth_multiplier - 1.0
        if is_zero_approx(adjustment):
            continue
        province["population"] = maxi(
            1,
            int(float(province.get("population", 0)) * (1.0 + population_rate * adjustment))
        )
        province["economy"] = maxf(
            0.0,
            snappedf(
                float(province.get("economy", 0.0)) \
                    * (1.0 + economy_rate * adjustment),
                0.001
            )
        )
        state.provinces[province_id] = province
        logs.append({"type": "governance_growth", "province_id": province_id})
    return logs


func allowed_levels(state, country_id: String) -> Array:
    var country: Dictionary = state.countries.get(country_id, {})
    var government_id := String(country.get("government_id", ""))
    var profile: Dictionary = rules.get("government_profiles", {}).get(
        government_id,
        {}
    )
    var result: Array = profile.get("allowed_levels", []).duplicate(true)
    if result.is_empty():
        result = ["direct", "delegated", "autonomous"]
    return result


func government_appointment_mode(state, country_id: String) -> String:
    var country: Dictionary = state.countries.get(country_id, {})
    var government_id := String(country.get("government_id", ""))
    var profile: Dictionary = rules.get("government_profiles", {}).get(
        government_id,
        {}
    )
    return String(profile.get("appointment_mode", "중앙 임명"))


func level_name(level: String) -> String:
    return String(rules.get("governance_levels", {}).get(level, {}).get("name", level))


func policy_name(policy: String) -> String:
    return String(rules.get("assimilation_policies", {}).get(policy, {}).get("name", policy))


func occupation_stage_name(stage: String) -> String:
    return String(rules.get("occupation_stages", {}).get(stage, {}).get("name", stage))


func _ensure_province(state, province_id: int, province: Dictionary) -> void:
    var owner_id := String(province.get("owner_id", ""))
    var controller_id := String(province.get("controller_id", owner_id))
    var occupied := owner_id != controller_id
    var default_stage := "immediate" if occupied else "formal"
    var starting_happiness := clampf(
        100.0 - float(province.get("unrest", 30.0)),
        0.0,
        100.0
    )
    var owner: Dictionary = state.countries.get(owner_id, {})
    var native_culture := 100.0 if not occupied else 20.0

    _set_default(province, "governance_level", "direct")
    _set_default(province, "governance_turns", 0)
    _set_default(province, "governor_appointment_mode", government_appointment_mode(state, owner_id))
    _set_default(province, "happiness", starting_happiness)
    _set_default(province, "local_stability", float(owner.get("stability", 55.0)))
    _set_default(province, "political_loyalty", 100.0 if not occupied else 35.0)
    _set_default(province, "civic_integration", 100.0 if not occupied else 0.0)
    _set_default(province, "cultural_assimilation", native_culture)
    _set_default(province, "assimilation_policy", "status_quo")
    _set_default(province, "assimilation_policy_changed_turn", int(state.turn) - 3)
    _set_default(province, "policy_cooldown_until", int(state.turn))
    _set_default(province, "occupation_stage", default_stage)
    _set_default(province, "occupation_turns", 0)
    _set_default(province, "occupation_origin_owner_id", owner_id if occupied else "")
    _set_default(province, "resistance", 0.0 if not occupied else 70.0)
    _set_default(province, "security", 86.0 if not occupied else 24.0)
    _set_default(province, "diplomatic_dispute", 8.0 if not occupied else 100.0)
    _set_default(province, "corruption_risk", 0.0)
    _set_default(province, "rebellion_risk", float(province.get("unrest", 0.0)))
    _set_default(province, "risk_stage", "stable")
    _set_default(province, "risk_factors", [])


func _advance_occupation(state, province_id: int, province: Dictionary) -> void:
    var owner_id := String(province.get("owner_id", ""))
    var controller_id := String(province.get("controller_id", owner_id))
    var occupied := owner_id != controller_id
    if not occupied:
        province["occupation_stage"] = "formal"
        province["occupation_turns"] = 0
        _apply_occupation_values(province, "formal")
        return

    if String(province.get("occupation_origin_owner_id", "")).is_empty():
        province["occupation_origin_owner_id"] = owner_id
        province["occupation_turns"] = 0
        province["political_loyalty"] = minf(
            float(province.get("political_loyalty", 35.0)),
            35.0
        )
        province["civic_integration"] = minf(
            float(province.get("civic_integration", 0.0)),
            8.0
        )

    province["occupation_turns"] = int(province.get("occupation_turns", 0)) + 1
    var occupation_turns := int(province["occupation_turns"])
    var garrison := _garrison_strength(state, province_id, controller_id)
    var security_support := clampf(float(garrison) / 900.0, 0.0, 1.0)
    var integration := minf(
        float(province.get("political_loyalty", 0.0)),
        float(province.get("civic_integration", 0.0))
    )
    var stage := "immediate"
    if occupation_turns >= int(rules.get("formal_integration_turns", 10)) \
            and integration >= 58.0 and security_support >= 0.45:
        stage = "formal"
        province["owner_id"] = controller_id
        province["occupation_origin_owner_id"] = owner_id
        province["occupation_turns"] = 0
    elif occupation_turns >= 6 and integration >= 35.0:
        stage = "de_facto"
    elif occupation_turns >= 3:
        stage = "sustained"

    province["occupation_stage"] = stage
    _apply_occupation_values(province, stage)


func _advance_assimilation(state, province: Dictionary) -> void:
    var policy_id := String(province.get("assimilation_policy", "status_quo"))
    var policy: Dictionary = rules.get("assimilation_policies", {}).get(
        policy_id,
        rules.get("assimilation_policies", {}).get("status_quo", {})
    )
    var level: Dictionary = rules.get("governance_levels", {}).get(
        String(province.get("governance_level", "direct")),
        rules.get("governance_levels", {}).get("direct", {})
    )
    var speed := float(level.get("policy_speed", 1.0))
    var occupied := String(province.get("owner_id", "")) != String(
        province.get("controller_id", "")
    )
    if not occupied and String(province.get("occupation_origin_owner_id", "")).is_empty():
        speed *= 0.25

    province["political_loyalty"] = clampf(
        float(province.get("political_loyalty", 50.0)) \
            + float(policy.get("political_loyalty_delta", 0.0)) * speed,
        0.0,
        100.0
    )
    province["civic_integration"] = clampf(
        float(province.get("civic_integration", 0.0)) \
            + float(policy.get("civic_integration_delta", 0.0)) * speed,
        0.0,
        100.0
    )
    province["cultural_assimilation"] = clampf(
        float(province.get("cultural_assimilation", 0.0)) \
            + float(policy.get("cultural_assimilation_delta", 0.0)) * speed,
        0.0,
        100.0
    )
    province["happiness"] = clampf(
        float(province.get("happiness", 60.0)) \
            + float(policy.get("happiness_delta", 0.0)),
        0.0,
        100.0
    )
    province["unrest"] = clampf(
        float(province.get("unrest", 0.0)) \
            + float(policy.get("unrest_delta", 0.0)),
        0.0,
        100.0
    )


func _apply_local_governance(state, province: Dictionary) -> void:
    var level_id := String(province.get("governance_level", "direct"))
    var level: Dictionary = rules.get("governance_levels", {}).get(
        level_id,
        rules.get("governance_levels", {}).get("direct", {})
    )
    province["governance_turns"] = int(province.get("governance_turns", 0)) + 1
    var controller_id := String(province.get("controller_id", ""))
    var country: Dictionary = state.countries.get(controller_id, {})
    var pressure := float(country.get("administrative_pressure", 0.0))
    var stability_delta := (
        float(level.get("growth_stability", 1.0)) - 0.55
    ) * 0.45 - pressure * 0.018
    province["local_stability"] = clampf(
        float(province.get("local_stability", 55.0)) + stability_delta,
        0.0,
        100.0
    )
    province["happiness"] = clampf(
        float(province.get("happiness", 55.0)) + stability_delta * 0.35,
        0.0,
        100.0
    )
    province["governance_tax_multiplier"] = float(level.get("tax_multiplier", 1.0))
    province["governance_growth_multiplier"] = 0.78 + float(
        level.get("growth_stability", 1.0)
    ) * 0.32
    province["command_precision"] = float(level.get("command_precision", 1.0))


func _evaluate_risks(state, province_id: int, province: Dictionary) -> void:
    var controller_id := String(province.get("controller_id", ""))
    var country: Dictionary = state.countries.get(controller_id, {})
    var level: Dictionary = rules.get("governance_levels", {}).get(
        String(province.get("governance_level", "direct")),
        rules.get("governance_levels", {}).get("direct", {})
    )
    var distance := _capital_distance(state, controller_id, province_id)
    var delegated_turns := int(province.get("governance_turns", 0)) \
        if String(province.get("governance_level", "direct")) != "direct" else 0
    var happiness := float(province.get("happiness", 55.0))
    var stability := float(province.get("local_stability", 55.0))
    var unrest := float(province.get("unrest", 0.0))
    var administration := float(country.get("administration_capacity", 30.0))
    var pressure := float(country.get("administrative_pressure", 0.0))
    var occupation := String(province.get("occupation_stage", "formal")) != "formal"
    var culture_gap := 100.0 - float(province.get("cultural_assimilation", 100.0))
    var garrison := _garrison_strength(state, province_id, controller_id)
    var garrison_shortage := clampf((800.0 - float(garrison)) / 16.0, 0.0, 50.0)

    var factors := [
        _factor("수도 거리", distance * 2.2),
        _factor("장기 위임", minf(float(delegated_turns) * 0.7, 18.0)),
        _factor("낮은 행복도", maxf(0.0, 50.0 - happiness) * 0.46),
        _factor("낮은 안정도", maxf(0.0, 50.0 - stability) * 0.42),
        _factor("높은 불안도", unrest * 0.28),
        _factor("약한 중앙 행정", maxf(0.0, 50.0 - administration) * 0.22 + pressure * 0.28),
        _factor("점령 상태", 15.0 if occupation else 0.0),
        _factor("문화·충성도 차이", culture_gap * 0.16),
        _factor("주둔군 부족", garrison_shortage),
    ]
    var total := 0.0
    for factor_value in factors:
        var factor: Dictionary = factor_value
        total += float(factor.get("value", 0.0))
    var corruption := clampf(
        5.0 + total * 0.56 + float(level.get("corruption_bias", 0.0)),
        0.0,
        100.0
    )
    var rebellion := clampf(
        total + float(level.get("rebellion_bias", 0.0)),
        0.0,
        100.0
    )
    province["corruption_risk"] = corruption
    province["rebellion_risk"] = rebellion
    province["revolt_risk"] = rebellion
    province["risk_factors"] = factors
    var stage := _risk_stage(rebellion)
    province["risk_stage"] = stage

    if stage == "stable":
        return
    var severity := "caution"
    if stage == "danger":
        severity = "important"
    elif stage == "imminent":
        severity = "emergency"
    NotificationCenter.add(
        state,
        severity,
        "%s · 반란 %s" % [
            String(province.get("name", "도시")),
            risk_stage_name(stage),
        ],
        _risk_message(factors),
        "revolt:%d:%s" % [province_id, stage],
        {"type": "focus_province", "province_id": province_id},
        {"province_id": province_id, "country_id": controller_id}
    )


func _recalculate_administration(state) -> void:
    var loads: Dictionary = {}
    for country_id_value in state.countries.keys():
        loads[String(country_id_value)] = 0.0
    for province_value in state.provinces.values():
        if province_value is not Dictionary:
            continue
        var province: Dictionary = province_value
        var controller_id := String(province.get("controller_id", ""))
        if not loads.has(controller_id):
            continue
        var level: Dictionary = rules.get("governance_levels", {}).get(
            String(province.get("governance_level", "direct")),
            rules.get("governance_levels", {}).get("direct", {})
        )
        var occupation: Dictionary = rules.get("occupation_stages", {}).get(
            String(province.get("occupation_stage", "formal")),
            rules.get("occupation_stages", {}).get("formal", {})
        )
        loads[controller_id] = float(loads[controller_id]) \
            + float(level.get("administrative_cost", 0.0)) \
            + float(occupation.get("administrative_cost", 0.0))

    for country_id_value in state.countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = state.countries[country_id_value]
        var profile: Dictionary = rules.get("government_profiles", {}).get(
            String(country.get("government_id", "")),
            {}
        )
        var capacity := maxf(
            1.0,
            float(country.get("administration_capacity", 30.0)) \
                * (1.0 + float(profile.get("administrative_modifier", 0.0)))
        )
        var load := float(loads.get(country_id, 0.0))
        country["administrative_load"] = snappedf(load, 0.1)
        country["administrative_capacity_effective"] = snappedf(capacity, 0.1)
        country["administrative_pressure"] = clampf(
            maxf(0.0, load - capacity) / capacity * 100.0,
            0.0,
            100.0
        )
        state.countries[country_id] = country


func _apply_occupation_values(province: Dictionary, stage: String) -> void:
    var values: Dictionary = rules.get("occupation_stages", {}).get(
        stage,
        rules.get("occupation_stages", {}).get("formal", {})
    )
    province["occupation_tax_multiplier"] = float(values.get("tax_multiplier", 1.0))
    province["occupation_production_multiplier"] = float(
        values.get("production_multiplier", 1.0)
    )
    province["occupation_manpower_multiplier"] = float(
        values.get("manpower_multiplier", 1.0)
    )
    province["resistance"] = float(values.get("resistance", 0.0))
    province["security"] = float(values.get("security", 86.0))
    province["diplomatic_dispute"] = float(values.get("diplomatic_dispute", 0.0))


func _garrison_strength(state, province_id: int, country_id: String) -> int:
    var total := 0
    for army_value in state.armies.values():
        if army_value is not Dictionary:
            continue
        var army: Dictionary = army_value
        if int(army.get("province_id", -1)) != province_id:
            continue
        if String(army.get("owner_id", "")) != country_id:
            continue
        total += int(army.get("soldiers", 0))
    return total


func _capital_distance(state, country_id: String, province_id: int) -> int:
    var country: Dictionary = state.countries.get(country_id, {})
    var capital_id := int(country.get("capital_province_id", -1))
    if capital_id == province_id:
        return 0
    if not state.provinces.has(capital_id):
        return 6
    var queue: Array = [capital_id]
    var distances := {capital_id: 0}
    while not queue.is_empty():
        var current_id := int(queue.pop_front())
        var next_distance := int(distances[current_id]) + 1
        for neighbor_value in state.provinces[current_id].get("neighbors", []):
            var neighbor_id := int(neighbor_value)
            if distances.has(neighbor_id) or not state.provinces.has(neighbor_id):
                continue
            if neighbor_id == province_id:
                return next_distance
            distances[neighbor_id] = next_distance
            queue.append(neighbor_id)
    return 8


func _factor(name: String, value: float) -> Dictionary:
    return {"name": name, "value": snappedf(maxf(0.0, value), 0.1)}


func _risk_stage(value: float) -> String:
    if value >= 70.0:
        return "imminent"
    if value >= 50.0:
        return "danger"
    if value >= 30.0:
        return "caution"
    return "stable"


func risk_stage_name(stage: String) -> String:
    return {
        "stable": "안정",
        "caution": "주의",
        "danger": "위험",
        "imminent": "임박",
    }.get(stage, stage)


func _risk_message(factors: Array) -> String:
    var ranked := factors.duplicate(true)
    ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a.get("value", 0.0)) > float(b.get("value", 0.0))
    )
    var causes := PackedStringArray()
    for factor_value in ranked:
        var factor: Dictionary = factor_value
        if float(factor.get("value", 0.0)) <= 0.0:
            continue
        causes.append("%s %.1f" % [factor.get("name", "요인"), factor.get("value", 0.0)])
        if causes.size() == 3:
            break
    return "주요 원인: %s. 주둔군 보강·행정 부담 완화·완만한 통합 정책을 검토하세요." % ", ".join(causes)


func _occupation_message(stage: String) -> String:
    return {
        "immediate": "세수와 생산이 제한되고 저항이 높습니다. 주둔군과 치안을 확보하세요.",
        "sustained": "지속 통제 중입니다. 통합 정책과 주둔군이 편입 속도를 결정합니다.",
        "de_facto": "일반 운영이 가능해졌지만 외교적 분쟁과 저항이 남아 있습니다.",
        "formal": "정상 편입되어 거리와 관계없이 직접 명령이 즉시 적용됩니다.",
    }.get(stage, "점령 상태가 변경되었습니다.")


func _set_default(target: Dictionary, key: String, value: Variant) -> void:
    if not target.has(key):
        target[key] = value


func _merge(base: Dictionary, override: Dictionary) -> Dictionary:
    var result := base.duplicate(true)
    for key_value in override.keys():
        var key := String(key_value)
        var override_value: Variant = override[key_value]
        if override_value is Dictionary and result.get(key, null) is Dictionary:
            result[key] = _merge(result[key], override_value)
        else:
            result[key] = override_value
    return result
