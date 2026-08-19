# Level 3 — Sanatorium build notes

3 floors · 24 ward rooms · 1305 scene nodes · 8 PS1 textures · carcass quota 6.

## Where things live

| Path | Role |
| --- | --- |
| `scenes/levels/Level3.tscn` | **Generated output — do not hand-edit.** Overwritten wholesale. |
| `tools/gen_level3.py` | Source of truth for the level: geometry, props, lighting, exterior. |
| `tools/gen_ps1_textures.py` | Writes the eight 128×128 TGAs into `textures/ps1/`. |
| `scripts/level.gd` | Shared by all three levels: indoor spawning, quota, F10 skip, ending trigger. |
| `scripts/ending_sequence.gd` | The reveal — camera, carcass→human swap, fade, THE END. |
| `scripts/carcass_zone.gd` | Tarp drop zone. `spawn_tarp_carcass()` is the one path real drops and F10 both use. |
| `scripts/sealed_door.gd` | HUD line at either shut door. |
| `scripts/lamp_flicker.gd` | Failing pendant fixtures. |

## Regenerating

```sh
# from vampire-game/
python tools/gen_level3.py         # rewrites Level3.tscn (~2s)
python tools/gen_ps1_textures.py   # rewrites textures/ps1/*.tga
```

Then force-reload the scene in Godot. The generator is seeded (`19391123`), so prop
scatter is identical run to run — a regenerate gives a clean diff, not a reshuffle.

## Traps

Six things here behave differently from how they read.

1. **`Transform3D`'s twelve-float constructor takes ROWS**, not the transformed axes.
   Emitting columns silently transposes every rotation — harmless on a yawed box, but it
   inverted the stair ramp into a descent. See `_yaw()` and `ramp()`.

2. **The player cannot step over anything.** Its collider is a flat-bottomed cylinder with
   no step-up, so any vertical lip is a wall. The tarp's 5 cm slab walled off its own drop
   zone until it was recessed and its collision disabled. Stairs must be smooth ramps with
   treads laid over as non-colliding scenery; ankle-high debris must not collide either.

3. **`ramp()` measures `thick` downward** from the surface it is given. Specify a parapet
   at coping height, not floor height — at floor height it becomes a buried slab and the
   player walks off the side of the flight.

4. **Recess and proud signs are easy to invert.** `sealed_door()` takes an `inward` sign for
   which side of the leaf the room is on. Backwards, it pushed the light leak 13 cm out into the
   room — a neon rectangle floating in front of the woodwork — and buried the architrave in the
   wall. The leak subtracts `inward`; the architrave adds it.

5. **Glass refraction samples the screen texture**, not what is geometrically behind the
   pane, so the window glazing picked up the flashlight cone on the surrounding wall and smeared
   it into a bright blob. `Mat_glass` is a plain grimy translucent grey instead — leave
   `refraction_enabled` off.

6. **Texture reimport does not rebuild the compressed variant.** Editing a `.tga` and
   calling reimport left the old `.s3tc.ctex` in place and the game kept rendering the
   previous image. These are now imported lossless (`compress/mode=0`), correct for 128 px
   nearest-filtered art anyway. If one looks stale: delete
   `.godot/imported/<name>.tga-*` and rescan.

## Texture rule

Anything high-contrast in a 128 px texture tiling every ~2 m reads as camouflage netting —
both the plaster and the dado were rebuilt deliberately quiet after exactly that. All
visible peeling comes from hand-placed brick panels, not the wall texture. Architectural
materials use **world triplanar** mapping so texel density is identical on every surface
regardless of box size; keep that when adding materials.

## Tunables

| Knob | Now | Notes |
| --- | --- | --- |
| `carcass_quota` | 6 | Long trek across three floors; lower is defensible. |
| `room_occupancy` | 0.62 | Odds a room has anything in it. |
| `baby_chance` | 0.45 | Odds an adult has young with it. |
| `fog_density` | 0.028 | Raising it re-hides the treeline. |
| `ambient_light_energy` | 0.4 | Cold fill; stops the exterior being pure black. |
| Moonlight energy | 1.35 | Directional, 55° elevation, shadows on — steep so trees silhouette from either side. |
| `Mat_glass` alpha | 0.20 | Window grime. Higher hides the treeline; lower stops reading as glass. |
| `Mat_leak` emission | 0.42 | Night seeping past both shut doors. Shaded and recessed; the far door's beacon is its spotlight, not this. |

## Open

- **Design:** the rifle's ShapeCast skips colliders without a `die()` method rather than
  stopping at the first hit, so animals can be shot through walls. One-line fix in
  `player.gd::shoot()` — left alone deliberately, since core mechanics were to behave
  exactly as in earlier levels.
- **Polish:** reception sits off the spawn sightline.
- **Not from this work:** editor errors from `scripts/settings_menu.gd` and a missing
  `audio/classic_horror_3.mp3`.

## Testing notes

The Godot MCP bridge **cannot send relative mouse motion**, so the view cannot be aimed
programmatically. Movement works through the `ui_up`/`ui_down`/`ui_left`/`ui_right`
actions, but anything needing aim is a human playtest. To inspect a specific place,
temporarily point the Tarp transform and `player_start_yaw_degrees` at it, run, then
regenerate to restore — that is how the stair climb and the upper-floor rooms were
verified. F10 force-ends any level down the same path a natural finish takes, and on
Level 3 tops the tarp up to quota first so the reveal has bodies to swap.

## Tree assets

`Tree_Oak`, `Tree_Pine`, `Tree_Thin` and `Tree_Twisted` were deleted from
`models/environment/trees/` and must not be reintroduced. The exterior uses only
`Tree_Dead`, `Tree_Fir`, `Tree_KermesOak`, `Tree_AleppoPine` and `Tree_Plane`, 102 of them
(`Tree_Strawberry` is available but unused). `Tree_Fir` and `Tree_AleppoPine` have no UID in
their scene headers, so they are referenced by path only — that is correct, not an oversight.

Keep the side bands at |x| >= 25: canopies run up to ~5 m across at these scales, and any nearer
than that they push through the outer wall. The eight `Ridge` blocks exist purely to fill the
horizon from the third floor (eye height ~9.2 m) — they must stay well above that or their top
edges show as black walls.
