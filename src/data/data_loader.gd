extends RefCounted

static func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"_error": "파일을 열 수 없습니다: %s" % path}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		return {"_error": "%s:%d %s" % [path, json.get_error_line(), json.get_error_message()]}
	return json.data

static func load_array(path: String, key: String) -> Array:
	var value: Variant = load_json(path)
	if value is Array:
		return value
	if value is Dictionary and value.has(key) and value[key] is Array:
		return value[key]
	return []

static func load_dictionary(path: String) -> Dictionary:
	var value: Variant = load_json(path)
	return value if value is Dictionary else {}
