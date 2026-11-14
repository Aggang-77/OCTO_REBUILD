extends Node3D
## An authoritative native solver site, not a second octopus rigid body.
var controller: Node3D
var arm: int = 0
var site: int = 12

func receive_contact_force(force: Vector3, _point: Vector3, _delta: float) -> void:
	controller.add_site_force(arm, site, force)
