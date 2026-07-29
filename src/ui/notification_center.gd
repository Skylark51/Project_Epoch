class_name NotificationCenter
extends Node

signal notification_added(notification: Dictionary, channels: Dictionary)
signal notification_updated(notification: Dictionary)
signal unread_count_changed(count: int, urgent_count: int)
signal navigation_requested(target: Dictionary)
signal pause_requested(paused: bool)
signal sound_requested(notification: Dictionary)

const SEVERITY_RANK := {
    "info": 0,
    "caution": 1,
    "warning": 2,
    "urgent": 3,
    "decision_required": 4
}
const DEFAULT_RULES := {
    "info": {"list": true},
    "caution": {"list": true, "map_icon": true},
    "warning": {"list": true, "banner": true, "sound": true},
    "urgent": {"list": true, "banner": true, "auto_pause": true, "modal": true},
    "decision_required": {"list": true, "banner": true, "modal": true}
}

var notifications: Array[Dictionary] = []
var rules: Dictionary = DEFAULT_RULES.duplicate(true)
var next_id := 1
var paused_by_notification := false


func configure(next_rules: Dictionary) -> void:
    rules = DEFAULT_RULES.duplicate(true)
    for kind in next_rules:
        rules[String(kind)] = _safe_rule(String(kind), next_rules[kind])


func add_notification(value: Dictionary) -> Dictionary:
    var item := _normalize(value)
    var fingerprint := _fingerprint(item)
    for existing in notifications:
        if String(existing.get("fingerprint", "")) == fingerprint and not bool(existing.get("resolved", false)):
            existing.repeat_count = int(existing.get("repeat_count", 1)) + 1
            existing.updated_at = Time.get_unix_time_from_system()
            existing.read = false
            notification_updated.emit(existing.duplicate(true))
            _emit_counts()
            return existing.duplicate(true)
    item.id = next_id
    next_id += 1
    item.fingerprint = fingerprint
    notifications.push_front(item)
    var channels := channels_for(item)
    notification_added.emit(item.duplicate(true), channels.duplicate(true))
    if bool(channels.get("sound", false)):
        sound_requested.emit(item.duplicate(true))
    if bool(channels.get("auto_pause", false)):
        paused_by_notification = true
        pause_requested.emit(true)
    _emit_counts()
    return item.duplicate(true)


func channels_for(item: Dictionary) -> Dictionary:
    var kind := String(item.get("kind", ""))
    var severity := String(item.get("severity", "info"))
    var rule: Dictionary = rules.get(kind, rules.get(severity, DEFAULT_RULES.info)).duplicate(true)
    return _safe_rule(severity, rule)


func all_notifications() -> Array[Dictionary]:
    return notifications.duplicate(true)


func grouped_notifications() -> Array[Dictionary]:
    return notifications.duplicate(true)


func crisis_cards() -> Array[Dictionary]:
    var grouped := {}
    for item in notifications:
        var city_id := String(item.get("city_id", ""))
        if city_id.is_empty() or int(SEVERITY_RANK.get(String(item.get("severity", "info")), 0)) < 1 or bool(item.get("resolved", false)):
            continue
        if not grouped.has(city_id):
            grouped[city_id] = {
                "city_id": city_id,
                "title": String(item.get("city_name", city_id)),
                "notifications": [],
                "severity": String(item.get("severity", "caution"))
            }
        grouped[city_id].notifications.append(item.duplicate(true))
        if int(SEVERITY_RANK.get(String(item.severity), 0)) > int(SEVERITY_RANK.get(String(grouped[city_id].severity), 0)):
            grouped[city_id].severity = item.severity
    var result: Array[Dictionary] = []
    for card in grouped.values():
        result.append(card)
    return result


func unread_count() -> int:
    var count := 0
    for item in notifications:
        if not bool(item.get("read", false)) and not bool(item.get("resolved", false)):
            count += 1
    return count


func urgent_unread_count() -> int:
    var count := 0
    for item in notifications:
        if not bool(item.get("read", false)) and not bool(item.get("resolved", false)) and String(item.get("severity", "")) in ["urgent", "decision_required"]:
            count += 1
    return count


func pending_decisions() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for item in notifications:
        if String(item.get("severity", "")) == "decision_required" and not bool(item.get("resolved", false)):
            result.append(item.duplicate(true))
    return result


func mark_read(id: int) -> bool:
    var item := _find(id)
    if item.is_empty():
        return false
    item.read = true
    notification_updated.emit(item.duplicate(true))
    _emit_counts()
    return true


func mark_all_read() -> void:
    for item in notifications:
        item.read = true
    _emit_counts()


func resolve(id: int) -> bool:
    var item := _find(id)
    if item.is_empty():
        return false
    item.read = true
    item.resolved = true
    notification_updated.emit(item.duplicate(true))
    _release_pause_if_safe()
    _emit_counts()
    return true


func acknowledge(id: int) -> bool:
    var changed := mark_read(id)
    _release_pause_if_safe()
    return changed


func navigate(id: int) -> bool:
    var item := _find(id)
    if item.is_empty():
        return false
    item.read = true
    var target: Dictionary = item.get("target", {}).duplicate(true)
    if target.is_empty():
        if not String(item.get("city_id", "")).is_empty():
            target = {"type": "city", "id": String(item.city_id)}
        elif item.has("province_id"):
            target = {"type": "province", "id": item.province_id}
    navigation_requested.emit(target)
    _emit_counts()
    return true


func map_markers() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for item in notifications:
        if bool(item.get("resolved", false)) or not bool(channels_for(item).get("map_icon", false)):
            continue
        result.append({
            "notification_id": int(item.id),
            "severity": String(item.severity),
            "city_id": String(item.get("city_id", "")),
            "province_id": int(item.get("province_id", -1))
        })
    return result


func clear_for_new_game() -> void:
    notifications.clear()
    next_id = 1
    if paused_by_notification:
        paused_by_notification = false
        pause_requested.emit(false)
    _emit_counts()


func _normalize(value: Dictionary) -> Dictionary:
    var severity := String(value.get("severity", "info"))
    if severity not in SEVERITY_RANK:
        severity = "info"
    return {
        "id": 0,
        "kind": String(value.get("kind", "general")),
        "severity": severity,
        "title": String(value.get("title", "알림")),
        "message": String(value.get("message", "")),
        "city_id": String(value.get("city_id", "")),
        "city_name": String(value.get("city_name", "")),
        "province_id": int(value.get("province_id", -1)),
        "target": value.get("target", {}).duplicate(true),
        "turn_blocking": bool(value.get("turn_blocking", severity == "decision_required")),
        "auto_governed": bool(value.get("auto_governed", false)),
        "read": false,
        "resolved": false,
        "repeat_count": 1,
        "created_at": Time.get_unix_time_from_system(),
        "updated_at": Time.get_unix_time_from_system()
    }


func _fingerprint(item: Dictionary) -> String:
    return "%s|%s|%s|%s" % [
        String(item.kind),
        String(item.city_id),
        str(item.province_id),
        String(item.get("target", {}).get("id", ""))
    ]


func _safe_rule(kind: String, value: Dictionary) -> Dictionary:
    var rule := {}
    for channel in ["list", "banner", "map_icon", "sound", "auto_pause", "modal"]:
        if bool(value.get(channel, false)):
            rule[channel] = true
    if bool(rule.get("auto_pause", false)):
        rule.modal = true
    if kind in ["urgent", "decision_required"] and rule.is_empty():
        rule = {"list": true, "modal": true}
    return rule


func _find(id: int) -> Dictionary:
    for item in notifications:
        if int(item.get("id", -1)) == id:
            return item
    return {}


func _release_pause_if_safe() -> void:
    if not paused_by_notification:
        return
    for item in notifications:
        if not bool(item.get("read", false)) and String(item.get("severity", "")) == "urgent":
            return
    paused_by_notification = false
    pause_requested.emit(false)


func _emit_counts() -> void:
    unread_count_changed.emit(unread_count(), urgent_unread_count())
