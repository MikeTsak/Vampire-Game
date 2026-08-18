# Skinwalker (Wendigo-Elk) asset pipeline

The whole creature -- skeleton, meshes, textures, materials, animations,
collision and scenes -- is generated from these scripts. Nothing here is
hand-edited binary; change a number, rerun, and the asset rebuilds.

## Rebuild

```sh
GODOT=/path/to/Godot_v4.7.1-stable_win64_console.exe

# 1. Full build: paints the atlas, builds 3 LOD meshes + 68-bone rig,
#    generates the 9 animation clips, writes the scenes.
"$GODOT" --headless --path . --script res://tools/build_skinwalker.gd

# 2. Reimport the regenerated PNGs so the running game sees them.
#    (The editor does this on focus; headless needs it asked for.)
"$GODOT" --headless --editor --path . --quit
```

## Review

```sh
export SW_SHOT_DIR=/tmp/turn

# Five-angle turnaround.
"$GODOT" --path . res://scenes/dev/SkinwalkerShot.tscn

# 8-frame contact sheet for one clip (SW_ANGLE defaults to a side view).
SW_ANIM=walk "$GODOT" --path . res://scenes/dev/SkinwalkerShot.tscn
SW_ANIM=death SW_ANGLE=145 "$GODOT" --path . res://scenes/dev/SkinwalkerShot.tscn
```

Reviewing through the *game* rather than the editor viewport is deliberate:
the editor caches `.res`/`.tres` between builds, so editor screenshots go
stale the moment the generator reruns.

## Verify

```sh
"$GODOT" --headless --path . --script res://tools/run_validate.gd
```

Checks bone count, per-LOD tri counts, material and skin bindings, all nine
clips, the collision proxy, and writes `models/skinwalker/skinwalker.glb`.

## Files

| script | role |
| --- | --- |
| `sw_atlas.gd` | atlas rect table, shared by the painter and the UV code |
| `sw_tex.gd` | paints albedo / normal / roughness / emission at native 256px |
| `sw_rig.gd` | 68-bone skeleton definition |
| `sw_mesh.gd` | generic skinned, flat-shaded mesh builder |
| `sw_body.gd` | assembles the creature from the rig |
| `sw_anim.gd` | the nine clips |
| `sw_shot.gd` | turnaround / contact-sheet driver (attached to the shot scene) |
| `build_skinwalker.gd` | orchestrator -- run this |
| `run_validate.gd` | export validation + glTF |

## Two gotchas worth knowing

- **`MeshInstance3D.skeleton` must be set explicitly.** Its documented default
  (`..`) does not bind when the node is built in code and packed — the mesh
  renders in rest pose while the bones animate perfectly, which looks exactly
  like a broken animation. `build_skinwalker.gd` assigns it by hand.
- **The editor caches `.res`/`.tres`.** Reopening a scene with `force_reload`
  reloads the `.tscn` but keeps the cached mesh and material, so a rebuilt
  asset appears unchanged. Review through the shot scene (a real game process)
  instead of editor screenshots.
