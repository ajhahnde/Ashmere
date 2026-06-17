class_name MatchCamera
extends RefCounted
## The match follow-rig: a close, LoL-style camera trailing the player's hero, lifted out of
## `main.gd` to keep that file under the line cap (the same reason PlayerInput, MoveMarker, and the
## overlays were lifted). It owns the `Camera3D`, its eased target, and the free-look state — a
## minimap left-click pans the view off the hero, and the re-centre key drops it back on.
##
## It holds no sim knowledge: each tick the driver hands it the hero's field point (or signals there
## is none yet) and whether the re-centre key is down, and it eases the camera. The sim→3D mapping
## comes in as a Callable so the rig and the driver agree on one projection.

## Follow-rig geometry: height and the backward offset set the look angle (atan(height / back) ~=
## 67°) and the zoom (~950 units off the hero); eyeball tuning knobs for the windowed playtest.
const HEIGHT := 880.0
const BACK := 370.0
## How far the camera closes the gap to its target each tick (0..1) — a smooth trail rather than a
## hard 1:1 lock, so a direction change eases. At 60 Hz, 0.2/tick settles in ~0.25 s.
const LERP := 0.2

## The Camera3D itself — the driver adds it to the scene and hands it to PlayerInput for the ground
## ray. Made current so it is the view the moment the match opens.
var node: Camera3D

## The field point the camera trails. Set to the hero each tick it exists and held at its last value
## while the hero is gone (dead, pre-spawn), so the view rests on the last sighting rather than
## snapping to the arena centre. Seeded at the arena centre for the menu backdrop.
var _target: Vector2
## False until the camera has been placed once: the first placement snaps (no glide-in from the
## world origin), every one after eases toward the target by LERP.
var _ready: bool = false
## Free-look: true while the player has panned the camera off their hero with a minimap left-click,
## so `follow` holds the panned target instead of re-pinning it to the hero. Cleared by the
## re-centre key, back to following the hero.
var _free: bool = false
## The sim→3D ground projection, shared with the driver so both agree on one mapping.
var _to_world: Callable


func _init(to_world: Callable) -> void:
	_to_world = to_world
	node = Camera3D.new()
	node.far = 20000.0
	node.current = true


## Snaps the camera onto a point with no glide — the build-time placement that frames the arena
## centre for the menu backdrop before any hero exists. Call once the node is in the tree (look_at
## needs a global transform); every placement after eases.
func place(point: Vector2) -> void:
	_target = point
	_point()


## The field point the camera is framing this tick — the hero, or the free-look point. The driver
## reads it to fade the foliage standing over the framed spot.
func target() -> Vector2:
	return _target


## Pans the camera to a point chosen off the minimap and holds it there (free look) until the player
## re-centres on their hero.
func look_at_point(point: Vector2) -> void:
	_target = point
	_free = true


## Trails the hero for this tick: re-pins to its field point (held at the last while the hero is
## gone), unless free-look holds a panned point. `recenter` — the re-centre key — drops free-look
## back onto the hero. `has_focus` is false before a hero spawns or once it leaves the world.
func follow(focus: Vector2, has_focus: bool, recenter: bool) -> void:
	if _free and recenter:
		_free = false
	if not _free and has_focus:
		_target = focus
	_point()


## Eases the camera toward a pose above and behind the target, looking down at it. The first
## placement snaps; each tick after closes LERP of the remaining gap, so the view trails smoothly.
func _point() -> void:
	var ground: Vector3 = _to_world.call(_target)
	var goal := ground + Vector3(0.0, HEIGHT, BACK)
	node.position = goal if not _ready else node.position.lerp(goal, LERP)
	_ready = true
	node.look_at(ground)
