class_name MapView
extends RefCounted
## The static map decor laid on the ground so the playfield reads — the lanes, the river,
## and the jungle camps — kept out of the match presenter so `main.gd` stays the driver and
## this stays the map painter.
##
## Every shape is read straight from MapData, the one geometry source the sim, the bots, and
## the tests already share, so the drawn map cannot drift from the simulated one. Pure
## presentation: flat coloured strips and discs lifted a hair above the ground to clear
## z-fighting, drawn once when the scene is built.

## The lift above the ground (y = 0) every flat decor piece sits at, so a painted strip does
## not z-fight the ground plane it lies on.
const DECOR_Y := 2.0

## Lanes: a trampled dirt path of this width tracing each lane corridor, drawn with the
## shared path shader (PATH_SHADER — dappled worn earth, edges frayed into the grass) so a
## lane reads as a footpath beaten through the jungle rather than a flat sandy strip.
const LANE_WIDTH := 230.0
const PATH_SHADER: Shader = preload("res://src/client/path.gdshader")

## River: a wide watercourse tracing the river polyline, drawn with the shared water shader
## (WATER_SHADER — drifting toon water, shallow banks frayed into the grass) so it reads as a
## stylised river rather than a flat blue strip. Wider than a lane, and lifted a hair over the
## lanes so a lane crossing reads as water-over-path without z-fighting.
const RIVER_WIDTH := 330.0
const WATER_SHADER: Shader = preload("res://src/client/water.gdshader")

## River course shaping, so the watercourse reads as a natural river rather than a kinked
## polyline: the stored points are Catmull-Rom subdivided into a smooth rounded curve, then a
## gentle sideways meander is layered on (windowed to zero at the map-edge ends) so even the
## straight stretches wander a little. Amplitude in world units; waves over the whole course.
const RIVER_SUBDIV := 10
const RIVER_MEANDER_AMP := 90.0
const RIVER_MEANDER_WAVES := 5.0

## Jungle camp: a flat disc marker on the ground.
const CAMP_RADIUS := 95.0
const CAMP_COLOR := Color(0.28, 0.40, 0.30)

## Bridge: a flat wooden plank deck carried over the river wherever a lane crosses it, so a
## lane reads as crossing on a footbridge rather than wading the water. A bare deck of cross
## planks — no rails — yawed to the lane's heading and cel-shaded wood (the unit shader, no
## team tint) so it sits in the same toon family as everything else, laid just over the water.
const CEL_SHADER: Shader = preload("res://src/client/cel.gdshader")
const BRIDGE_WOOD := Color(0.36, 0.24, 0.13)
const BRIDGE_WIDTH := 280.0  # across the lane, a touch wider than the path it carries
const BRIDGE_SPAN := 560.0  # along the lane, long enough to clear the wide river at an angle
const BRIDGE_DECK_Y := 4.0  # deck height — flat, just over the water so the lane crosses it
const PLANK_DEPTH := 40.0  # each cross plank's size along the lane
const PLANK_GAP := 12.0  # bare gap between planks
const PLANK_THICK := 7.0


## Paints the whole static map under `parent`: each lane as a trampled dirt ribbon, the river
## as a wider water ribbon over them, a flat plank bridge at each lane–river crossing, and a
## disc at every jungle camp. Drawn in that order so the river layers over the lanes and the
## bridges over the river. Call once, after the ground plane exists.
static func build(parent: Node3D) -> void:
	var path_material := _path_material()
	for lane in MapData.lane_count():
		_build_ribbon_mesh(parent, MapData.lane_path(lane, 0), LANE_WIDTH, path_material)
	var river := _meander(
		_smooth_polyline(MapData.river_polyline(), RIVER_SUBDIV),
		RIVER_MEANDER_AMP,
		RIVER_MEANDER_WAVES,
	)
	_build_ribbon_mesh(parent, river, RIVER_WIDTH, _water_material(), DECOR_Y + 1.0)
	_lay_bridges(parent)
	for camp in MapData.JUNGLE_CAMPS:
		_mark_disc(parent, camp, CAMP_RADIUS, CAMP_COLOR)


## Builds a ribbon (lane or river) as one continuous flat mesh tracing a polyline, wearing
## `material` at height `y`. Each polyline point gets a left/right vertex offset by the mitred
## normal — the bisector of its two segment directions — so consecutive quads share an edge and
## the ribbon turns each bend without the angular gaps a row of separate boxes leaves. `UV.x`
## carries the across-position (0 left … 1 right) so the path/water shader can shade and fray
## the banks; vertices are baked in world space and the mesh sits at the origin.
static func _build_ribbon_mesh(
	parent: Node3D, points: PackedVector2Array, width: float, material: Material, y := DECOR_Y
) -> void:
	if points.size() < 2:
		return
	var half := width * 0.5
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in points.size():
		var off := _ribbon_offset(points, i, half)
		var p := points[i]
		left.append(Vector3(p.x + off.x, y, p.y + off.y))
		right.append(Vector3(p.x - off.x, y, p.y - off.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		_ribbon_vert(st, left[i], 0.0)
		_ribbon_vert(st, right[i], 1.0)
		_ribbon_vert(st, left[i + 1], 0.0)
		_ribbon_vert(st, right[i], 1.0)
		_ribbon_vert(st, right[i + 1], 1.0)
		_ribbon_vert(st, left[i + 1], 0.0)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = material
	parent.add_child(mesh_inst)


## Emits one ribbon vertex with its across-position in `UV.x` and an up normal (the ribbon lies
## flat, so the lighting reads it as ground), for the SurfaceTool to assemble.
static func _ribbon_vert(st: SurfaceTool, v: Vector3, u: float) -> void:
	st.set_uv(Vector2(u, 0.0))
	st.set_normal(Vector3.UP)
	st.add_vertex(v)


## The sideways offset (half the width, mitred) from a polyline point `i` to its left edge —
## the bisector of the two adjacent segments' left normals, lengthened so the ribbon keeps its
## width through the bend. Clamped so a sharp turn cannot spike the miter to a long spar. The
## right edge is the point minus this. Endpoints use their single segment normal.
static func _ribbon_offset(points: PackedVector2Array, i: int, half: float) -> Vector2:
	var n_in := Vector2.ZERO
	var n_out := Vector2.ZERO
	if i > 0:
		var d := (points[i] - points[i - 1]).normalized()
		n_in = Vector2(-d.y, d.x)
	if i < points.size() - 1:
		var d := (points[i + 1] - points[i]).normalized()
		n_out = Vector2(-d.y, d.x)
	var normal := n_in + n_out
	if normal.length() < 0.0001:
		normal = n_out if n_in == Vector2.ZERO else n_in
	normal = normal.normalized()
	var reference := n_out if n_in == Vector2.ZERO else n_in
	var cos_half := maxf(normal.dot(reference), 0.35)  # clamp: a sharp bend can't spike the miter
	return normal * (half / cos_half)


## A polyline rounded into a smooth curve: each stored segment is replaced by `subdivisions`
## Catmull-Rom samples through the points, so the kinks at the corners become gentle bends. The
## end points are held (the spline duplicates them as its phantom neighbours), so the course
## still meets the map edges where it did. Returns the original points unchanged when too short.
static func _smooth_polyline(points: PackedVector2Array, subdivisions: int) -> PackedVector2Array:
	if points.size() < 3 or subdivisions < 2:
		return points
	var last := points.size() - 1
	var out := PackedVector2Array()
	for i in last:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, last)]
		for s in subdivisions:
			out.append(_catmull_rom(p0, p1, p2, p3, float(s) / float(subdivisions)))
	out.append(points[last])
	return out


## The Catmull-Rom point at `t` in [0, 1] on the segment p1→p2, with p0/p3 the neighbours that
## set the curve's incoming and outgoing tangents. Passes through p1 and p2.
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## Adds a gentle sideways meander to a course, so even its straight runs wander like a real
## river: each point is pushed along its perpendicular by a sine over the arc length, its
## amplitude windowed by `sin(pi * s)` so the displacement tapers to zero at both ends and the
## course still anchors at the map edges. `amp` is the peak offset (world units), `waves` the
## number of full meanders along the course. Static — computed once when the map is built.
static func _meander(points: PackedVector2Array, amp: float, waves: float) -> PackedVector2Array:
	var count := points.size()
	if count < 3 or amp <= 0.0:
		return points
	var total := 0.0
	for i in count - 1:
		total += points[i].distance_to(points[i + 1])
	if total <= 0.0:
		return points
	var out := PackedVector2Array()
	var travelled := 0.0
	for i in count:
		if i > 0:
			travelled += points[i].distance_to(points[i - 1])
		var s := travelled / total
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var perpendicular := Vector2(-tangent.y, tangent.x)
		var offset := amp * sin(PI * s) * sin(s * waves * TAU)
		out.append(points[i] + perpendicular * offset)
	return out


## Lays a flat plank bridge at every point a lane crosses the river, sharing one wood material.
static func _lay_bridges(parent: Node3D) -> void:
	var wood := _wood_material()
	for crossing in _lane_river_crossings():
		_build_bridge(parent, crossing["pos"], crossing["dir"], wood)


## Every point a lane corridor crosses the river, each as `{pos, dir}` — the crossing point and
## the lane's heading there, so a bridge can be laid spanning the water along the lane. Found by
## intersecting each lane segment against each river segment, so it tracks the geometry rather
## than hard-coding where the top lane meets the water (it crosses twice).
static func _lane_river_crossings() -> Array:
	var river := MapData.river_polyline()
	var out: Array = []
	for lane in MapData.lane_count():
		var path := MapData.lane_path(lane, 0)
		for i in path.size() - 1:
			for j in river.size() - 1:
				var hit = Geometry2D.segment_intersects_segment(
					path[i], path[i + 1], river[j], river[j + 1]
				)
				if hit != null:
					out.append({"pos": hit, "dir": (path[i + 1] - path[i]).normalized()})
	return out


## Builds a flat plank deck at `pos`, yawed so it runs along `dir` (the lane's heading): a row
## of cross planks spanning BRIDGE_SPAN along the lane at deck height, no rails. The planks are
## laid in the deck's local space, so the whole bridge turns as one with the lane it carries.
static func _build_bridge(parent: Node3D, pos: Vector2, dir: Vector2, wood: Material) -> void:
	var bridge := Node3D.new()
	bridge.position = Vector3(pos.x, 0.0, pos.y)
	bridge.rotation.y = atan2(dir.x, dir.y)
	parent.add_child(bridge)
	var pitch := PLANK_DEPTH + PLANK_GAP
	var count := int(BRIDGE_SPAN / pitch)
	var start := -0.5 * float(count - 1) * pitch
	for k in count:
		var plank := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BRIDGE_WIDTH, PLANK_THICK, PLANK_DEPTH)
		plank.mesh = box
		plank.material_override = wood
		plank.position = Vector3(0.0, BRIDGE_DECK_Y, start + float(k) * pitch)
		bridge.add_child(plank)


## The cel-shaded wood material the bridge planks share: the unit cel shader at the wood tone
## with no team tint, so the bridge reads in the same toon family. One instance for all planks.
static func _wood_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CEL_SHADER
	mat.set_shader_parameter("albedo", BRIDGE_WOOD)
	mat.set_shader_parameter("tint_strength", 0.0)
	return mat


## Marks a flat disc of `radius` and `color` on the ground at a field point — a jungle camp.
static func _mark_disc(parent: Node3D, pos: Vector2, radius: float, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	disc.mesh = cyl
	disc.material_override = _flat_material(color)
	disc.position = Vector3(pos.x, DECOR_Y, pos.y)
	parent.add_child(disc)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## The trampled dirt-path material the lane ribbons share. One instance for both lanes; the
## shader reads the across-position from the ribbon mesh UVs, so it needs no width told to it.
static func _path_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PATH_SHADER
	return mat


## The water material the whole river ribbon wears. One instance; the shader reads the
## across-position from the ribbon mesh UVs for its shallow band and bank fray.
static func _water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	return mat
