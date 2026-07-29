class_name UIShellPreferences
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://ui_shell_preferences.json"
const ITEM_IDS := [
    "date", "treasury", "food", "war_status", "total_population",
    "average_happiness", "average_stability", "administrative_power",
    "legitimacy", "military_power", "influence_growth",
    "rebellion_risk_cities", "occupied_provinces", "vassal_loyalty",
    "research_progress"
]
const REQUIRED_IDS := ["date", "treasury", "food", "war_status"]
const DISPLAY_MODES := ["detail", "compact"]
const CHANNELS := ["list", "banner", "map_icon", "sound", "auto_pause", "modal"]
const SEVERITIES := ["info", "caution", "warning", "urgent", "decision_required"]
const EVENT_KINDS := {
    "construction_complete": {"label": "건설 완료", "severity": "info"},
    "trade_income": {"label": "교역 수익", "severity": "info"},
    "food_decline": {"label": "식량 감소", "severity": "caution"},
    "happiness_decline": {"label": "행복도 악화", "severity": "caution"},
    "rebellion_risk": {"label": "반란 위험 급증", "severity": "warning"},
    "enemy_approach": {"label": "적군 접근", "severity": "warning"},
    "city_fall": {"label": "도시 함락", "severity": "urgent"},
    "rebellion": {"label": "반란 발생", "severity": "urgent"},
    "capital_siege": {"label": "수도 포위", "severity": "urgent"},
    "peace_offer": {"label": "평화 제안", "severity": "decision_required"},
    "succession": {"label": "후계자 결정", "severity": "decision_required"},
    "ultimatum": {"label": "최후통첩", "severity": "decision_required"}
}

var path := DEFAULT_PATH
var data: Dictionary = {}
var last_error := ""


func _init(custom_path := DEFAULT_PATH) -> void:
    path = custom_path
    data = defaults()


static func defaults() -> Dictionary:
    return {
        "schema_version": SCHEMA_VERSION,
        "top_bar": {
            "order": ITEM_IDS.duplicate(),
            "visible": REQUIRED_IDS.duplicate(),
            "display_mode": "detail"
        },
        "input": {
            "edge_pan_enabled": false,
            "edge_pan_margin": 12,
            "keyboard_pan_speed": 34.0
        },
        "notifications": {
            "rules": {
                "info": {"list": true},
                "caution": {"list": true, "map_icon": true},
                "warning": {"list": true, "banner": true, "sound": true},
                "urgent": {"list": true, "banner": true, "auto_pause": true, "modal": true},
                "decision_required": {"list": true, "banner": true, "modal": true}
            }
        }
    }


func load_preferences() -> Dictionary:
    last_error = ""
    if not FileAccess.file_exists(path):
        data = defaults()
        return data.duplicate(true)
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        last_error = "UI 설정 파일을 열 수 없습니다: %s" % path
        data = defaults()
        return data.duplicate(true)
    var parser := JSON.new()
    var parse_error := parser.parse(file.get_as_text())
    var parsed = parser.data if parse_error == OK else null
    if parsed is not Dictionary:
        last_error = "UI 설정 JSON이 손상되어 기본값으로 복구했습니다."
        data = defaults()
        return data.duplicate(true)
    data = sanitize(parsed)
    return data.duplicate(true)


func save_preferences() -> bool:
    data = sanitize(data)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        last_error = "UI 설정을 저장할 수 없습니다: %s" % path
        push_error(last_error)
        return false
    file.store_string(JSON.stringify(data, "\t"))
    last_error = ""
    return true


func replace(next_data: Dictionary, persist := true) -> Dictionary:
    data = sanitize(next_data)
    if persist:
        save_preferences()
    return data.duplicate(true)


func top_bar() -> Dictionary:
    return data.get("top_bar", defaults().top_bar).duplicate(true)


func input_settings() -> Dictionary:
    return data.get("input", defaults().input).duplicate(true)


func notification_rules() -> Dictionary:
    return data.get("notifications", {}).get("rules", defaults().notifications.rules).duplicate(true)


func set_top_bar(order: Array, visible: Array, display_mode: String) -> void:
    data.top_bar = {
        "order": order.duplicate(),
        "visible": visible.duplicate(),
        "display_mode": display_mode
    }
    save_preferences()


func set_edge_pan_enabled(enabled: bool) -> void:
    data.input.edge_pan_enabled = enabled
    save_preferences()


func set_notification_rule(kind: String, rule: Dictionary) -> void:
    if not data.notifications.has("rules"):
        data.notifications.rules = {}
    data.notifications.rules[kind] = _sanitize_rule(kind, rule)
    save_preferences()


static func sanitize(value: Dictionary) -> Dictionary:
    var result := defaults()
    var source_bar: Dictionary = value.get("top_bar", {})
    var order: Array = []
    for id_value in source_bar.get("order", []):
        var id := String(id_value)
        if id in ITEM_IDS and id not in order:
            order.append(id)
    for id in ITEM_IDS:
        if id not in order:
            order.append(id)
    var visible: Array = []
    for id_value in source_bar.get("visible", []):
        var id := String(id_value)
        if id in ITEM_IDS and id not in visible:
            visible.append(id)
    for id in REQUIRED_IDS:
        if id not in visible:
            visible.append(id)
    var mode := String(source_bar.get("display_mode", "detail"))
    if mode not in DISPLAY_MODES:
        mode = "detail"
    result.top_bar = {"order": order, "visible": visible, "display_mode": mode}

    var source_input: Dictionary = value.get("input", {})
    result.input.edge_pan_enabled = bool(source_input.get("edge_pan_enabled", false))
    result.input.edge_pan_margin = clampi(int(source_input.get("edge_pan_margin", 12)), 4, 48)
    result.input.keyboard_pan_speed = clampf(float(source_input.get("keyboard_pan_speed", 34.0)), 8.0, 120.0)

    var source_rules: Dictionary = value.get("notifications", {}).get("rules", {})
    for kind in source_rules:
        result.notifications.rules[String(kind)] = _sanitize_rule(String(kind), source_rules[kind])
    return result


static func _sanitize_rule(kind: String, value: Dictionary) -> Dictionary:
    var rule := {}
    for channel in CHANNELS:
        if bool(value.get(channel, false)):
            rule[channel] = true
    if bool(rule.get("auto_pause", false)):
        rule.modal = true
    if kind in ["urgent", "decision_required"] and rule.is_empty():
        rule = {"list": true, "modal": true}
    return rule
