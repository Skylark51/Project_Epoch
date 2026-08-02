class_name EpochNotificationCenter
extends RefCounted


## Owns persisted player-facing notifications.  Simulation systems provide a
## stable deduplication key; this class keeps repeated turn warnings in one
## actionable record instead of producing a toast, log, and alert every turn.

const LIMIT := 180


static func add(
    state,
    severity: String,
    title: String,
    message: String,
    deduplication_key: String,
    action: Dictionary = {},
    context: Dictionary = {}
) -> Dictionary:
    if state.notifications is not Array:
        state.notifications = []

    for index in range(state.notifications.size() - 1, -1, -1):
        var previous: Dictionary = state.notifications[index]
        if String(previous.get("deduplication_key", "")) != deduplication_key:
            continue
        if int(state.turn) - int(previous.get("last_turn", 0)) > 1:
            break

        previous["last_turn"] = int(state.turn)
        previous["count"] = int(previous.get("count", 1)) + 1
        previous["severity"] = severity
        previous["title"] = title
        previous["message"] = message
        previous["action"] = action.duplicate(true)
        previous["context"] = context.duplicate(true)
        state.notifications[index] = previous
        return previous.duplicate(true)

    var next_id := int(state.metadata.get("notification_next_id", 1))
    state.metadata["notification_next_id"] = next_id + 1
    var notification := {
        "id": next_id,
        "turn": int(state.turn),
        "last_turn": int(state.turn),
        "severity": severity,
        "title": title,
        "message": message,
        "deduplication_key": deduplication_key,
        "count": 1,
        "read": false,
        "action": action.duplicate(true),
        "context": context.duplicate(true),
    }
    state.notifications.append(notification)
    while state.notifications.size() > LIMIT:
        state.notifications.pop_front()
    return notification.duplicate(true)


static func mark_read(state, notification_id: int) -> bool:
    for index in range(state.notifications.size()):
        var notification: Dictionary = state.notifications[index]
        if int(notification.get("id", -1)) != notification_id:
            continue
        notification["read"] = true
        state.notifications[index] = notification
        return true
    return false


static func unread_count(state, minimum_severity: String = "info") -> int:
    var severity_order := {
        "info": 0,
        "caution": 1,
        "important": 2,
        "emergency": 3,
    }
    var threshold := int(severity_order.get(minimum_severity, 0))
    var count := 0
    for value in state.notifications:
        if value is not Dictionary:
            continue
        var notification: Dictionary = value
        if bool(notification.get("read", false)):
            continue
        if int(severity_order.get(String(notification.get("severity", "info")), 0)) >= threshold:
            count += 1
    return count
