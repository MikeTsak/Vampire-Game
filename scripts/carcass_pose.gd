extends Object
## Shared placement for a dead animal's visual inside a carcass body.
##
## Both the shot-in-the-field path (animal.gd) and the tarp path
## (carcass_zone.gd) take an animal's MeshBase and tip it onto its side. The
## rotation happens about MeshBase's origin, which sits at the animal's feet, so
## on its own it swings the whole body out sideways and half of it below the
## floor -- a deer ends up buried to the ribs a metre from its own collision
## box. Re-centring afterwards is what puts the body where the carcass is.

## Onto its side, the way carcasses have always been laid out here.
const LIE_DOWN := Vector3(PI, 0.0, PI / 2)

## Tips `mesh_base` onto its side and centres it on its parent's origin, which
## is where the carcass body's collision box sits. Returns the size that box
## should be: centred visual plus matching box means physics rests the animal
## exactly on the ground, instead of floating it half a metre up (the old fixed
## 1x1x1.5 box was taller than a deer lying down, and four times a piglet).
static func lay_down(mesh_base: Node3D) -> Vector3:
	mesh_base.position = Vector3.ZERO
	mesh_base.rotation = LIE_DOWN
	var box := visual_bounds(mesh_base)
	if box.size == Vector3.ZERO:
		return Vector3.ZERO
	mesh_base.position = -box.get_center()
	return box.size

## Bounds of everything drawn under `root`, in the space of root's parent.
## Walks transforms by hand rather than reading global_transform, because both
## callers pose the carcass before it is added to the tree.
static func visual_bounds(root: Node3D) -> AABB:
	var boxes := _collect(root, root.transform)
	if boxes.is_empty():
		return AABB()
	var out: AABB = boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out

static func _collect(node: Node, xform: Transform3D) -> Array:
	var out := []
	if node is VisualInstance3D:
		# For a skinned mesh this is the bind-pose box, which is what a carcass
		# is in anyway. CSG animals report through the same call.
		out.append(xform * (node as VisualInstance3D).get_aabb())
	for c in node.get_children():
		var child_xform := xform
		if c is Node3D:
			child_xform = xform * (c as Node3D).transform
		out += _collect(c, child_xform)
	return out
