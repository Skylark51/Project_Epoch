class_name MapProjection
extends RefCounted

var width := 640
var height := 480
var lon0 := deg_to_rad(111.5)
var lat0 := deg_to_rad(35.0)
var orientation_clockwise_radians := 0.0
var n := 0.0
var f := 0.0
var rho0 := 0.0
var min_x := 0.0
var max_x := 1.0
var min_y := 0.0
var max_y := 1.0

func configure(manifest: Dictionary) -> void:
	width = int(manifest.get("width", 640))
	height = int(manifest.get("height", 480))
	var config: Dictionary = manifest.get("projection", {})
	lon0 = deg_to_rad(float(config.get("central_meridian", 111.5)))
	lat0 = deg_to_rad(float(config.get("latitude_of_origin", 35.0)))
	orientation_clockwise_radians = deg_to_rad(
		float(config.get("orientation_clockwise_degrees", 0.0))
	)
	var phi1 := deg_to_rad(float(config.get("standard_parallel_1", 25.0)))
	var phi2 := deg_to_rad(float(config.get("standard_parallel_2", 47.0)))
	n = log(cos(phi1) / cos(phi2)) / log(tan(PI * 0.25 + phi2 * 0.5) / tan(PI * 0.25 + phi1 * 0.5))
	f = cos(phi1) * pow(tan(PI * 0.25 + phi1 * 0.5), n) / n
	rho0 = f / pow(tan(PI * 0.25 + lat0 * 0.5), n)
	var bounds: Dictionary = config.get("projected_bounds", {})
	min_x = float(bounds.get("min_x", 0.0))
	max_x = float(bounds.get("max_x", 1.0))
	min_y = float(bounds.get("min_y", 0.0))
	max_y = float(bounds.get("max_y", 1.0))

func lonlat_to_tile(longitude: float, latitude: float) -> Vector2:
	var oriented_raw := _oriented_raw(_lcc_raw(longitude, latitude))
	return Vector2(
		(oriented_raw.x - min_x) / (max_x - min_x) * width,
		(max_y - oriented_raw.y) / (max_y - min_y) * height
	)


func tile_to_lonlat(tile: Vector2) -> Vector2:
	var oriented_raw := Vector2(
		min_x + tile.x / float(width) * (max_x - min_x),
		max_y - tile.y / float(height) * (max_y - min_y)
	)
	var raw := _unoriented_raw(oriented_raw)
	var rho_sign := 1.0 if n >= 0.0 else -1.0
	var rho := rho_sign * Vector2(raw.x, rho0 - raw.y).length()
	var theta := atan2(rho_sign * raw.x, rho_sign * (rho0 - raw.y))
	var phi := 2.0 * atan(pow(f / rho, 1.0 / n)) - PI * 0.5
	var lam := lon0 + theta / n
	return Vector2(rad_to_deg(lam), rad_to_deg(phi))


func _lcc_raw(longitude: float, latitude: float) -> Vector2:
	var phi := deg_to_rad(clampf(latitude, -89.999, 89.999))
	var lam := deg_to_rad(longitude)
	var rho := f / pow(tan(PI * 0.25 + phi * 0.5), n)
	var theta := n * (lam - lon0)
	return Vector2(rho * sin(theta), rho0 - rho * cos(theta))


func _oriented_raw(raw: Vector2) -> Vector2:
	if is_zero_approx(orientation_clockwise_radians):
		return raw
	var cosine := cos(orientation_clockwise_radians)
	var sine := sin(orientation_clockwise_radians)
	return Vector2(
		cosine * raw.x + sine * raw.y,
		-sine * raw.x + cosine * raw.y
	)


func _unoriented_raw(oriented_raw: Vector2) -> Vector2:
	if is_zero_approx(orientation_clockwise_radians):
		return oriented_raw
	var cosine := cos(orientation_clockwise_radians)
	var sine := sin(orientation_clockwise_radians)
	return Vector2(
		cosine * oriented_raw.x - sine * oriented_raw.y,
		sine * oriented_raw.x + cosine * oriented_raw.y
	)
