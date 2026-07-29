#!/usr/bin/env python3
"""Build Project Epoch's offline East Asia tile layers from Natural Earth GeoJSON."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, deque
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "data" / "maps" / "world_map_config.json"
CITIES_PATH = ROOT / "data" / "maps" / "cities.json"
OUTPUT_DIR = ROOT / "data" / "maps" / "generated"
SCREENSHOT_DIR = ROOT / "docs" / "screenshots"

TERRAIN_IDS = {
    "deep_ocean": 0,
    "ocean": 1,
    "shallow_sea": 2,
    "coast": 3,
    "plains": 4,
    "grassland": 5,
    "forest": 6,
    "hill": 7,
    "mountain": 8,
    "desert": 9,
    "steppe": 10,
    "wetland": 11,
    "river": 12,
    "lake": 13,
}

TERRAIN_COLORS = {
    0: (20, 53, 72),
    1: (28, 78, 103),
    2: (54, 112, 133),
    3: (178, 166, 112),
    4: (157, 157, 103),
    5: (111, 139, 85),
    6: (56, 103, 71),
    7: (119, 104, 76),
    8: (102, 91, 82),
    9: (183, 157, 94),
    10: (137, 142, 83),
    11: (72, 119, 96),
    12: (59, 123, 153),
    13: (47, 105, 135),
}

# This ordering is stable on disk. The runtime maps it to the scenario's numeric IDs
# through each province's source_province_id.
PROVINCE_ANCHORS = {
    "guknae_basin": (126.18, 41.14),
    "pyongyang_basin": (125.76, 39.04),
    "han_river_basin": (126.98, 37.57),
    "yeongsan_basin": (126.70, 35.02),
    "daegaya_basin": (128.27, 35.73),
    "gyeongju_basin": (129.22, 35.86),
    "aragaya_basin": (128.41, 35.27),
    "guya_basin": (128.88, 35.23),
    "liaodong_corridor": (123.20, 41.27),
    "qingzhou_corridor": (118.48, 36.70),
    "tsukushi_plain": (130.40, 33.59),
    "kibi_plain": (133.93, 34.66),
    "yamato_basin": (135.80, 34.50),
}

# Real-coordinate minimum representation points. These are not hand-drawn country
# polygons; they only keep documented islands from disappearing during downsampling.
ISLAND_PRESERVATION_POINTS = [
    ("jeju", 126.53, 33.38),
    ("ulleungdo", 130.90, 37.50),
    ("dokdo", 131.87, 37.24),
    ("tsushima", 129.30, 34.40),
    ("iki", 129.69, 33.79),
    ("okinawa", 127.68, 26.21),
    ("amami", 129.49, 28.38),
    ("miyako", 125.28, 24.77),
    ("ishigaki", 124.16, 24.34),
    ("hainan", 109.75, 19.20),
    ("taiwan", 121.00, 23.70),
    ("rebun", 141.04, 45.38),
]


class LambertConformalConic:
    def __init__(self, config: dict, bounds: dict, width: int, height: int):
        self.lon0 = math.radians(config["central_meridian"])
        self.lat0 = math.radians(config["latitude_of_origin"])
        phi1 = math.radians(config["standard_parallel_1"])
        phi2 = math.radians(config["standard_parallel_2"])
        self.n = math.log(math.cos(phi1) / math.cos(phi2)) / math.log(
            math.tan(math.pi / 4 + phi2 / 2) / math.tan(math.pi / 4 + phi1 / 2)
        )
        self.f = (
            math.cos(phi1)
            * math.pow(math.tan(math.pi / 4 + phi1 / 2), self.n)
            / self.n
        )
        self.rho0 = self.f / math.pow(math.tan(math.pi / 4 + self.lat0 / 2), self.n)
        self.width = width
        self.height = height
        boundary = []
        for i in range(401):
            t = i / 400
            lon = bounds["west"] + (bounds["east"] - bounds["west"]) * t
            lat = bounds["south"] + (bounds["north"] - bounds["south"]) * t
            boundary.extend(
                [
                    self.project_raw(lon, bounds["south"]),
                    self.project_raw(lon, bounds["north"]),
                    self.project_raw(bounds["west"], lat),
                    self.project_raw(bounds["east"], lat),
                ]
            )
        self.min_x = min(p[0] for p in boundary)
        self.max_x = max(p[0] for p in boundary)
        self.min_y = min(p[1] for p in boundary)
        self.max_y = max(p[1] for p in boundary)

    def project_raw(self, lon: float, lat: float) -> tuple[float, float]:
        phi = math.radians(max(-89.999, min(89.999, lat)))
        lam = math.radians(lon)
        rho = self.f / math.pow(math.tan(math.pi / 4 + phi / 2), self.n)
        theta = self.n * (lam - self.lon0)
        return rho * math.sin(theta), self.rho0 - rho * math.cos(theta)

    def tile(self, lon: float, lat: float) -> tuple[float, float]:
        x, y = self.project_raw(lon, lat)
        col = (x - self.min_x) / (self.max_x - self.min_x) * self.width
        row = (self.max_y - y) / (self.max_y - self.min_y) * self.height
        return col, row

    def lonlat(self, col: float, row: float) -> tuple[float, float]:
        x = self.min_x + col / self.width * (self.max_x - self.min_x)
        y = self.max_y - row / self.height * (self.max_y - self.min_y)
        rho_sign = 1.0 if self.n >= 0 else -1.0
        rho = rho_sign * math.hypot(x, self.rho0 - y)
        theta = math.atan2(rho_sign * x, rho_sign * (self.rho0 - y))
        phi = 2 * math.atan(math.pow(self.f / rho, 1 / self.n)) - math.pi / 2
        lam = self.lon0 + theta / self.n
        return math.degrees(lam), math.degrees(phi)

    def metadata(self) -> dict:
        return {
            "projected_bounds": {
                "min_x": self.min_x,
                "max_x": self.max_x,
                "min_y": self.min_y,
                "max_y": self.max_y,
            }
        }


def geometries(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    for feature in data.get("features", []):
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        coordinates = geometry.get("coordinates", [])
        if kind == "Polygon":
            yield coordinates
        elif kind == "MultiPolygon":
            yield from coordinates


def ring_bbox(ring) -> tuple[float, float, float, float]:
    xs = [float(point[0]) for point in ring]
    ys = [float(point[1]) for point in ring]
    return min(xs), min(ys), max(xs), max(ys)


def intersects(box, bounds) -> bool:
    return not (
        box[2] < bounds["west"]
        or box[0] > bounds["east"]
        or box[3] < bounds["south"]
        or box[1] > bounds["north"]
    )


def rasterize_geojson(
    path: Path,
    projection: LambertConformalConic,
    bounds: dict,
    width: int,
    height: int,
    supersampling: int,
) -> Image.Image:
    image = Image.new("L", (width * supersampling, height * supersampling), 0)
    draw = ImageDraw.Draw(image)
    for polygon in geometries(path):
        if not polygon or not polygon[0] or not intersects(ring_bbox(polygon[0]), bounds):
            continue
        for ring_index, ring in enumerate(polygon):
            points = [
                (
                    projection.tile(float(point[0]), float(point[1]))[0] * supersampling,
                    projection.tile(float(point[0]), float(point[1]))[1] * supersampling,
                )
                for point in ring
            ]
            if len(points) >= 3:
                draw.polygon(points, fill=255 if ring_index == 0 else 0)
    return image


def preserve_islands(land: list[bool], projection: LambertConformalConic, width: int, height: int):
    preserved = []
    for island_id, lon, lat in ISLAND_PRESERVATION_POINTS:
        x, y = projection.tile(lon, lat)
        col = max(0, min(width - 1, int(x)))
        row = max(0, min(height - 1, int(y)))
        nearby = False
        for yy in range(max(0, row - 1), min(height, row + 2)):
            for xx in range(max(0, col - 1), min(width, col + 2)):
                nearby = nearby or land[yy * width + xx]
        if not nearby:
            land[row * width + col] = True
            preserved.append({"id": island_id, "longitude": lon, "latitude": lat, "x": col, "y": row})
    return preserved


def clean_single_cell_holes(land: list[bool], width: int, height: int) -> None:
    fill = []
    for row in range(1, height - 1):
        for col in range(1, width - 1):
            index = row * width + col
            if land[index]:
                continue
            neighbors = sum(
                land[(row + dy) * width + col + dx]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
                if dx or dy
            )
            if neighbors >= 7:
                fill.append(index)
    for index in fill:
        land[index] = True


def is_land_neighbor(land, width, height, col, row, target_land: bool) -> bool:
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if not dx and not dy:
                continue
            x, y = col + dx, row + dy
            if 0 <= x < width and 0 <= y < height and land[y * width + x] == target_land:
                return True
    return False


def _hash_noise(x: int, y: int) -> float:
    value = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return float(value & 0xFFFF) / 65535.0


def _smooth_noise(lon: float, lat: float, scale: float = 0.34) -> float:
    x = lon * scale
    y = lat * scale
    x0 = math.floor(x)
    y0 = math.floor(y)
    tx = x - x0
    ty = y - y0
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    top = _hash_noise(x0, y0) * (1.0 - tx) + _hash_noise(x0 + 1, y0) * tx
    bottom = _hash_noise(x0, y0 + 1) * (1.0 - tx) + _hash_noise(x0 + 1, y0 + 1) * tx
    return top * (1.0 - ty) + bottom * ty


def terrain_for_land(lon: float, lat: float) -> int:
    # Coastline is data-driven. This replaceable biome approximation avoids
    # per-tile striping by blending deterministic low-frequency patches.
    noise = _smooth_noise(lon, lat)
    if lon < 101.5 and lat > 28:
        return TERRAIN_IDS["mountain"] if lat < 36.5 + noise * 3.0 else TERRAIN_IDS["desert"]
    if lon < 108.5 and lat > 38.0 + noise * 2.0:
        return TERRAIN_IDS["desert"] if noise < 0.62 else TERRAIN_IDS["steppe"]
    if lat > 44.0 + noise * 2.5 and lon < 128:
        return TERRAIN_IDS["steppe"] if noise < 0.58 else TERRAIN_IDS["grassland"]
    if 107 < lon < 123 and 29 < lat < 41.5:
        return TERRAIN_IDS["plains"] if noise < 0.72 else TERRAIN_IDS["grassland"]
    if 124 < lon < 131.5 and 34 < lat < 43:
        mountain_edge = 127.8 + (noise - 0.5) * 1.2
        return TERRAIN_IDS["mountain"] if lon > mountain_edge else TERRAIN_IDS["grassland"]
    if 129 < lon < 146 and 30 < lat < 46:
        if lat > 41.2:
            return TERRAIN_IDS["forest"]
        return TERRAIN_IDS["mountain"] if noise > 0.38 else TERRAIN_IDS["forest"]
    if lat < 31 and lon > 104:
        return TERRAIN_IDS["forest"] if noise < 0.64 else TERRAIN_IDS["hill"]
    if lon < 110 and lat < 36:
        return TERRAIN_IDS["hill"] if noise < 0.55 else TERRAIN_IDS["mountain"]
    return TERRAIN_IDS["grassland"]

def classify_terrain(
    land: list[bool],
    lake_coverage: Image.Image,
    projection: LambertConformalConic,
    width: int,
    height: int,
) -> bytearray:
    terrain = bytearray(width * height)
    water_distance = [-1] * (width * height)
    queue = deque()
    for row in range(height):
        for col in range(width):
            index = row * width + col
            if land[index]:
                lon, lat = projection.lonlat(col + 0.5, row + 0.5)
                terrain[index] = terrain_for_land(lon, lat)
                if is_land_neighbor(land, width, height, col, row, False):
                    terrain[index] = TERRAIN_IDS["coast"]
            elif is_land_neighbor(land, width, height, col, row, True):
                water_distance[index] = 0
                queue.append(index)
    while queue:
        index = queue.popleft()
        row, col = divmod(index, width)
        if water_distance[index] >= 13:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x, y = col + dx, row + dy
            if 0 <= x < width and 0 <= y < height:
                next_index = y * width + x
                if not land[next_index] and water_distance[next_index] == -1:
                    water_distance[next_index] = water_distance[index] + 1
                    queue.append(next_index)
    lake_pixels = lake_coverage.load()
    for row in range(height):
        for col in range(width):
            index = row * width + col
            if land[index] and lake_pixels[col, row] >= 96:
                terrain[index] = TERRAIN_IDS["lake"]
            elif not land[index]:
                distance = water_distance[index]
                terrain[index] = (
                    TERRAIN_IDS["shallow_sea"]
                    if 0 <= distance <= 3
                    else TERRAIN_IDS["ocean"]
                    if 0 <= distance <= 12
                    else TERRAIN_IDS["deep_ocean"]
                )
    return terrain


def assign_provinces(
    land: list[bool], projection: LambertConformalConic, width: int, height: int
) -> tuple[bytearray, list[str], dict]:
    source_ids = [""] + list(PROVINCE_ANCHORS)
    anchor_tiles = {key: projection.tile(*value) for key, value in PROVINCE_ANCHORS.items()}
    result = bytearray(width * height)
    for row in range(height):
        for col in range(width):
            index = row * width + col
            if not land[index]:
                continue
            lon, lat = projection.lonlat(col + 0.5, row + 0.5)
            if 124.0 <= lon <= 131.5 and 33.0 <= lat <= 43.8:
                candidates = source_ids[1:9]
            elif 119.0 <= lon <= 125.3 and 38.0 <= lat <= 43.5:
                candidates = ["liaodong_corridor"]
            elif 114.0 <= lon <= 122.5 and 32.0 <= lat <= 39.5:
                candidates = ["qingzhou_corridor"]
            elif 128.0 <= lon <= 143.5 and 30.0 <= lat <= 46.5:
                candidates = source_ids[11:14]
            else:
                continue
            best = min(
                candidates,
                key=lambda key: (anchor_tiles[key][0] - col) ** 2
                + (anchor_tiles[key][1] - row) ** 2,
            )
            result[index] = source_ids.index(best)
    anchors = {
        key: {
            "longitude": lon,
            "latitude": lat,
            "map_x": projection.tile(lon, lat)[0],
            "map_y": projection.tile(lon, lat)[1],
        }
        for key, (lon, lat) in PROVINCE_ANCHORS.items()
    }
    return result, source_ids, anchors


def update_cities(projection: LambertConformalConic, width: int, height: int) -> list[dict]:
    data = json.loads(CITIES_PATH.read_text(encoding="utf-8"))
    cities = []
    for source in data["cities"]:
        city = dict(source)
        x, y = projection.tile(city["longitude"], city["latitude"])
        city["mapX"] = round(x, 4)
        city["mapY"] = round(y, 4)
        city["inBounds"] = 0 <= x < width and 0 <= y < height
        cities.append(city)
    data["projection"] = "lambert_conformal_conic"
    data["map_id"] = "east_asia_640x480"
    data["cities"] = cities
    CITIES_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return cities


def make_overview(
    terrain: bytearray,
    cities: list[dict],
    width: int,
    height: int,
    scale: int = 1,
) -> Image.Image:
    image = Image.new("RGB", (width, height))
    image.putdata([TERRAIN_COLORS[value] for value in terrain])
    if scale == 1:
        return image
    image = image.resize((width * scale, height * scale), Image.Resampling.NEAREST)
    draw = ImageDraw.Draw(image)
    for city in cities:
        if not city["enabled"] or not city["inBounds"]:
            continue
        x = int(city["mapX"] * scale)
        y = int(city["mapY"] * scale)
        radius = 3 if city["type"] == "major_city" else 2
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(244, 213, 138), outline=(28, 30, 31))
    return image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(config_path: Path) -> dict:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    width = int(config["width"])
    height = int(config["height"])
    ss = int(config["supersampling"])
    chunk_size = int(config["chunk_size"])
    bounds = config["bounds"]
    projection = LambertConformalConic(config["projection"], bounds, width, height)
    land_path = ROOT / config["sources"]["land"].replace("res://", "")
    lakes_path = ROOT / config["sources"]["lakes"].replace("res://", "")
    land_high = rasterize_geojson(land_path, projection, bounds, width, height, ss)
    lakes_high = rasterize_geojson(lakes_path, projection, bounds, width, height, ss)
    land_coverage = land_high.resize((width, height), Image.Resampling.BOX)
    lake_coverage = lakes_high.resize((width, height), Image.Resampling.BOX)
    pixels = land_coverage.load()
    land = [pixels[col, row] >= 96 for row in range(height) for col in range(width)]
    clean_single_cell_holes(land, width, height)
    preserved = preserve_islands(land, projection, width, height)
    terrain = classify_terrain(land, lake_coverage, projection, width, height)
    province, province_sources, province_anchors = assign_provinces(
        land, projection, width, height
    )
    cities = update_cities(projection, width, height)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    terrain_path = OUTPUT_DIR / "east_asia_terrain.bin"
    province_path = OUTPUT_DIR / "east_asia_provinces.bin"
    overview_path = OUTPUT_DIR / "east_asia_overview.png"
    terrain_path.write_bytes(terrain)
    province_path.write_bytes(province)
    make_overview(terrain, cities, width, height).save(overview_path)
    make_overview(terrain, cities, width, height, 3).save(
        SCREENSHOT_DIR / "east_asia_world_map.png"
    )

    terrain_counts = Counter(terrain)
    manifest = {
        "schema_version": 1,
        "data_version": "east_asia_map_v1",
        "map_id": config["map_id"],
        "width": width,
        "height": height,
        "tile_count": width * height,
        "chunk_size": chunk_size,
        "chunk_columns": math.ceil(width / chunk_size),
        "chunk_rows": math.ceil(height / chunk_size),
        "chunk_count": math.ceil(width / chunk_size) * math.ceil(height / chunk_size),
        "tile_size": int(config["tile_size"]),
        "projection": config["projection"] | projection.metadata(),
        "bounds": bounds,
        "terrain_ids": TERRAIN_IDS,
        "terrain_counts": {
            name: terrain_counts[value] for name, value in TERRAIN_IDS.items()
        },
        "terrain_file": "res://data/maps/generated/east_asia_terrain.bin",
        "province_file": "res://data/maps/generated/east_asia_provinces.bin",
        "overview_file": "res://data/maps/generated/east_asia_overview.png",
        "cities_file": "res://data/maps/cities.json",
        "province_sources": province_sources,
        "province_anchors": province_anchors,
        "minimum_islands_added": preserved,
        "source_sha256": {
            land_path.name: sha256(land_path),
            lakes_path.name: sha256(lakes_path),
        },
    }
    manifest_path = OUTPUT_DIR / "east_asia_world_map_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Generated {width}x{height} ({width * height:,} tiles), "
        f"{manifest['chunk_columns']}x{manifest['chunk_rows']} "
        f"({manifest['chunk_count']:,} chunks)"
    )
    print(f"Land tiles: {sum(land):,}; water tiles: {width * height - sum(land):,}")
    print(f"Minimum-island additions: {len(preserved)}")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=CONFIG_PATH)
    args = parser.parse_args()
    build(args.config.resolve())


if __name__ == "__main__":
    main()
