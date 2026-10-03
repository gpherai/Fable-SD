## Combat visual helpers. Orbs (tapas and gold) burst out of a fallen enemy, settle on the
## ground and then fly to the player, who collects them on contact.
extends RefCounted

const Props = preload("res://scripts/world/Props.gd")

const ORB_COLORS := {
	"general": "#ffe9b0",
	"bala": "#ff6a3d",
	"kaushala": "#5be37d",
	"shakti": "#7a8cff",
	"gold": "#ffd24a",
}

## An experience or gold orb. Collecting it awards the amount through Game.
class Orb extends Node3D:
	var kind: String = "general"
	var amount: int = 0
	var world: Node = null
	var vel := Vector3.ZERO
	var age: float = 0.0
	var settled: bool = false

	func setup(kind_: String, amount_: int, world_: Node, pos: Vector3) -> void:
		kind = kind_
		amount = amount_
		world = world_
		var c := Color.html(ORB_COLORS.get(kind, "#ffffff"))
		add_child(Props.sphere(0.11, c, Vector3.ZERO, Vector3.ONE, 0.3, 0.0, Color(c.r, c.g, c.b, 0.9)))
		world.add_child(self)
		global_position = pos + Vector3(0, 0.9, 0)
		vel = Vector3(randf_range(-2.2, 2.2), randf_range(3.0, 5.0), randf_range(-2.2, 2.2))

	func _physics_process(delta: float) -> void:
		age += delta
		var player = Game.player
		if player == null or not is_instance_valid(player):
			return
		var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var dist := global_position.distance_to(target)
		if age > 0.7 and (dist < 16.0 or age > 45.0):
			# home in, accelerating the longer the orb has been flying
			var speed := 6.0 + (age - 0.7) * 10.0
			global_position = global_position.move_toward(target, speed * delta)
			if global_position.distance_to(target) < 0.5:
				_collect()
			return
		if not settled:
			vel.y -= 14.0 * delta
			global_position += vel * delta
			var floor_y: float = world.height_at(global_position.x, global_position.z) + 0.35
			if global_position.y <= floor_y:
				global_position.y = floor_y
				vel = Vector3.ZERO
				settled = true
		else:
			position.y += sin(age * 4.0) * 0.003

	func _collect() -> void:
		if kind == "gold":
			Game.add_gold(amount)
			Audio.play("gold", -4.0)
		else:
			Game.add_tapas(kind, amount)
			Audio.play("tapas", -6.0)
		queue_free()

## Spawns tapas orbs. amounts: {general, bala, kaushala, shakti}.
static func tapas_orbs(world: Node, pos: Vector3, amounts: Dictionary) -> void:
	for kind in ["general", "bala", "kaushala", "shakti"]:
		var total := int(amounts.get(kind, 0))
		if total > 0:
			_spawn_split(world, pos, kind, total, 10)

static func gold_orb(world: Node, pos: Vector3, amount: int) -> void:
	if amount > 0:
		_spawn_split(world, pos, "gold", amount, 25)

## Splits a total over a few orbs (about one per `chunk`, between 1 and 6) so big rewards look big.
static func _spawn_split(world: Node, pos: Vector3, kind: String, total: int, chunk: int) -> void:
	var n := clampi(int(ceil(float(total) / float(chunk))), 1, 6)
	var left := total
	for i in n:
		var part := int(ceil(float(left) / float(n - i)))
		left -= part
		var orb := Orb.new()
		orb.name = "Orb_" + kind
		orb.setup(kind, part, world, pos)
