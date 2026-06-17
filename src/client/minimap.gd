class_name Minimap
extends Control

## A right-click on the plan: issue the player's move/attack order at this world point.
signal order_requested(world_point: Vector2)
## A left-click or left-drag on the plan: pan the camera to this world point (free look).
signal look_requested(world_point: Vector2)
## The corner minimap: a scaled top-down plan of the arena in the bottom-right, drawn over the
## game camera like the rest of the match UI. It shows the static terrain (lanes, river, the map
## frame) as a backdrop and the live units as dots — friendly always, enemies only where the
## player's team has vision, so it honours the same fog of war the world view does ([[Vision]]).
##
## Pure presentation, reconciled each tick from the snapshot the HUD already consumes: it owns no
## simulation and reads only entity position/team/kind plus the player's own hero (highlighted).
## Geometry comes straight from MapData — the one source the sim, bots, and world decor share — so
## the plan cannot drift from the played map. Built in code on the UiTheme palette, like every
## other overlay; no `.tscn`, no editor pass.
##
## Interactive: a click on the plan reads as a command at the world point under it (the inverse of
## `map_point`). A **right-click** issues the player's move/attack order there — the same order a
## world right-click makes, so it auto-paths and reconciles over the wire identically, only chosen
## off the map so the hero can be sent clear across the arena. A **left-click** (or a left-drag,
## scrubbing) pans the camera there for a free look, until the player re-centres on their hero. The
## panel captures the pointer within its own square, so a click on the plan no longer leaks a stray
## world order under the card; clicks elsewhere still fall through to the world untouched.
##
## It owns no movement or camera state itself — it only projects the click back to a world point and
## emits it; the driver wires `order_requested`/`look_requested` to PlayerInput and the camera. Ping
## markers are a later slice (they travel the wire, so they ride their own netcode pass).

## The square plan's side and its inset from the screen corner, in pixels.
const SIZE := 280.0
const MARGIN := 16.0

## Backdrop: a dark translucent panel with a faint frame, so the plan reads as a card over the
## world without hiding it outright.
const PANEL_BG := Color(0.05, 0.07, 0.06, 0.82)
const PANEL_BORDER := UiTheme.PANEL_BORDER
const BORDER_WIDTH := 2.0

## Terrain backdrop tones, dimmer than the world so the unit dots pop: the lane dirt and the river.
const LANE_COLOR := Color(0.30, 0.26, 0.18)
const LANE_WIDTH := 3.0
const RIVER_COLOR := Color(0.20, 0.32, 0.46)
const RIVER_WIDTH := 3.0

## Unit dot sizing (pixels): a hero reads largest, a creep is a speck, a structure a small square
## (the nexus larger). The player's own hero wears an amber ring so it is found at a glance.
const HERO_RADIUS := 4.5
const CREEP_RADIUS := 2.0
const TOWER_HALF := 3.5
const NEXUS_HALF := 5.0
const OWN_RING_RADIUS := 7.5
const OWN_RING_WIDTH := 2.0
const CREEP_DARKEN := 0.25  # a creep dot sits a shade under its team hue, as in the world view

var _state: SimState = null
var _team: int = 0
var _focus_id: int = 0
var _colors: Array = []
## Whether to filter enemies by vision here: true with local authority (the state is the full
## world), false on a pure CLIENT whose snapshot is already filtered to its team.
var _filter: bool = false
var _visible: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	# Pin a SIZE square into the bottom-right corner, MARGIN in from each edge.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(SIZE + MARGIN)
	offset_top = -(SIZE + MARGIN)
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	# Capture the pointer over the plan so a click here is a map command, not a stray world order
	# under the card. Only this square stops the pointer; clicks elsewhere fall through as before.
	mouse_filter = Control.MOUSE_FILTER_STOP


## Routes a click on the plan to a world command. A right-click emits a move/attack order, a
## left-click (or a left-drag, so the camera scrubs as the pointer moves) a camera look — both at
## the world point under the cursor, projected back through `unmap_point`. The event position is
## panel-local already, so it maps straight into the plan square.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var at := unmap_point(event.position, size)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			order_requested.emit(at)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			look_requested.emit(at)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		look_requested.emit(unmap_point(event.position, size))


## Whether the pointer is over the plan right now — the driver reads this to suppress the world
## right-click order while the cursor sits on the minimap, so the panel's own order is the only one.
func contains_pointer() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


## Reconciles the plan against this tick's world. `state` is the world to draw, `focus` the player's
## own hero (null before it spawns), `team_colors` the per-team dot colours indexed by team id, and
## `hide_fogged` filters enemies by the player's vision (set only with local authority — a pure
## CLIENT's snapshot is already team-filtered). Recomputes the visible set once here, not per dot.
func update(
	state: SimState, player_team: int, focus: SimEntity, team_colors: Array, hide_fogged: bool
) -> void:
	_state = state
	_team = player_team
	_focus_id = focus.id if focus != null else 0
	_colors = team_colors
	_filter = hide_fogged
	_visible = Vision.visible_ids(state, player_team) if (hide_fogged and state != null) else {}
	queue_redraw()


## Maps a sim-field point into the panel's local pixel space: the arena bounds scaled to the SIZE
## square, sim x → right and sim y → down (the same top-down orientation as the world camera).
## Static and pure so the mapping is unit-testable without drawing.
static func map_point(p: Vector2, panel_size: Vector2) -> Vector2:
	var bounds := MapData.BOUNDS
	var n := (p - bounds.position) / bounds.size
	return Vector2(n.x * panel_size.x, n.y * panel_size.y)


## The inverse: a panel pixel back to the sim-field point under it, so a click on the plan becomes a
## world command. Static and pure, the exact inverse of `map_point` — a round trip is the identity.
static func unmap_point(panel_point: Vector2, panel_size: Vector2) -> Vector2:
	var bounds := MapData.BOUNDS
	var n := Vector2(panel_point.x / panel_size.x, panel_point.y / panel_size.y)
	return bounds.position + n * bounds.size


func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, PANEL_BG)
	if _state != null:
		_draw_terrain()
		_draw_units()
	draw_rect(panel, PANEL_BORDER, false, BORDER_WIDTH)


## The static backdrop — the lane corridors and the river — drawn dim so the unit dots read over it.
func _draw_terrain() -> void:
	for lane in MapData.LANES:
		draw_polyline(_scaled(lane), LANE_COLOR, LANE_WIDTH)
	draw_polyline(_scaled(MapData.RIVER), RIVER_COLOR, RIVER_WIDTH)


## The live units as dots: friendly always, enemies only where the team has vision. A structure is a
## square (nexus larger), a creep a speck, a hero a disc; the player's own hero gets an amber ring.
func _draw_units() -> void:
	for id in _state.entities:
		var entity: SimEntity = _state.entities[id]
		if _filter and entity.team != _team and not _visible.has(id):
			continue
		var at := map_point(entity.position, size)
		var color := _team_color(entity.team)
		if entity.is_nexus:
			_draw_square(at, NEXUS_HALF, color)
		elif entity.is_structure:
			_draw_square(at, TOWER_HALF, color)
		elif entity.is_creep:
			draw_circle(at, CREEP_RADIUS, color.darkened(CREEP_DARKEN))
		else:
			draw_circle(at, HERO_RADIUS, color)
			if id == _focus_id:
				draw_arc(at, OWN_RING_RADIUS, 0.0, TAU, 20, UiTheme.ACCENT, OWN_RING_WIDTH)


## A team's dot colour from the passed palette, falling back to white if a team index is unmapped.
func _team_color(team: int) -> Color:
	if team >= 0 and team < _colors.size():
		return _colors[team]
	return Color.WHITE


## A filled square centred on `at`, half-side `half` — the structure dot.
func _draw_square(at: Vector2, half: float, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), color)


## A polyline of sim points mapped into panel space — the terrain backdrop helper.
func _scaled(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(map_point(p, size))
	return out
