# East Asia geography source

The generated game map uses **Natural Earth 1:10m physical vector data**.

- Source project: Natural Earth (`https://www.naturalearthdata.com/`)
- Upstream repository: `https://github.com/nvkelso/natural-earth-vector`
- Original files:
  - `ne_10m_land.geojson`
  - `ne_10m_lakes.geojson`
- Downloaded from the upstream repository's `geojson/` directory.
- License page: `https://www.naturalearthdata.com/about/terms-of-use/`
- License: Natural Earth data is in the public domain. Natural Earth asks that users
  credit the project where practical.
- Runtime dependency: none. The source GeoJSON and generated binary tile layers are
  stored in this repository, so the game does not contact a map API.

## Processing

`scripts/generate_east_asia_map.py` clips the source to 73°E–150°E and
15°N–55°N, projects coordinates with a Lambert conformal conic projection,
rasterizes land and lakes at 4× resolution, and downsamples occupancy to the
configured 640×480 tile grid. It classifies shoreline cells separately and
preserves named small islands at their real WGS84 coordinates when the source
polygon would otherwise vanish at tile resolution.

The generated runtime layers are row-major byte arrays. One terrain byte and one
province-source byte are stored per tile. A 16×16 chunk therefore covers 256
tiles and the renderer only uploads/draws chunks intersecting the camera.
