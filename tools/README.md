# Skinwalker (Wendigo-Elk) asset pipeline

The creature stands upright at ~3.4m to the antler tips. Its torso is a
VERTICAL column, so every helper that wraps the body works on a horizontal
cross-section: `ang == 0` is the spine ridge at the back (+Z), `ang == PI` is
the sternum. Anything riding the shell must use `_radial()`, which carries the
same squash as the torso tube -- treating the cross-section as a circle floats
the ribs off the flank.

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

## Gotchas worth knowing

- **`MeshInstance3D.skeleton` must be set explicitly.** Its documented default
  (`..`) does not bind when the node is built in code and packed — the mesh
  renders in rest pose while the bones animate perfectly, which looks exactly
  like a broken animation. `build_skinwalker.gd` assigns it by hand.
- **The editor caches `.res`/`.tres`.** Reopening a scene with `force_reload`
  reloads the `.tscn` but keeps the cached mesh and material, so a rebuilt
  asset appears unchanged. Review through the shot scene (a real game process)
  instead of editor screenshots.
- **Winding is CCW-front in Godot** (`WIND_CW = false` in `sw_mesh.gd`). Get it
  backwards and a closed convex form keeps its silhouette — you just see the
  inside of the far wall, lit by an outward normal — so the torso merely looks
  a bit flat. It only becomes obvious on the skull, where the muzzle sits
  inside the cranium and the interior shows straight through. If the model ever
  looks subtly wrong and "hollow" around overlapping parts, check this first.
  `SW_NOCULL=1` on the shot scene is the quick test: if the problem vanishes
  with culling off, it is winding, not a gap in the mesh.
- **The eye lamps must not light the creature.** They sit ~12cm from the antler
  pedicles, so any energy strong enough to reach the ground blows those out to
  white. The creature renders on layer 2 and the lamps mask it out, which lets
  them run at a useful energy and throw light into the world instead. Raising
  their energy without that mask just floodlights the model orange.
- **Decals need feathered tiles.** Gore and wound patches are quads laid on the
  hide; a tile with a hard edge reads as a rectangle pasted on the model. The
  `gore` tile fades to hide colour at its border for exactly this reason, and
  blood is drawn as several narrow runs of uneven length rather than one wide
  card.

---

# Rifle / muzzle flash pipeline

```sh
# Muzzle flash mesh, material and scene.
"$GODOT" --headless --path . --script res://tools/build_weapon.gd

# Sub-bass layer for the gunshot (needs an editor import pass after).
python tools/generate_gun_audio.py

# Iron sights, muzzle marker + flash, audio players, animation set.
"$GODOT" --headless --path . --script res://tools/patch_player.gd

# Rebuild the test range, then fire a shot and grab a contact sheet.
"$GODOT" --headless --path . --script res://tools/build_guntest.gd
GUN_SHOT_DIR=/tmp/gun "$GODOT" --path . res://scenes/dev/GunTest.tscn
```

`patch_player.gd` re-packs `Player.tscn` rather than editing its text, and is
idempotent — rerunning it will not duplicate nodes. It re-adds the `player`
group explicitly, because the skinwalker AI finds the player by group and a
re-pack must not drop it.

## Weapon gotchas

- **One owner for weapon position.** `WeaponPivot` is positioned by
  `player.gd` (hip carry ↔ ADS) and the recoil springs add to it. `WWIRifle`
  sits at the pivot origin and the animations only add sway/bob/bolt on top.
  Previously both nodes carried offsets *and* the clips keyed absolute
  positions, so aiming and animating fought and ADS never centred the gun.
- **Recoil rides the Camera3D, not the Head.** Mouse look owns
  `head.rotation.x`; adding kick there fights the player's aim on the same axis.
- **Nothing that moves the rifle body belongs in the reload clip.** Shouldered,
  the receiver sits centimetres from the lens, so body motion baked into the
  animation punches straight through the near plane. The clip carries the bolt
  tracks only; `player.gd` applies the tip-away sway procedurally and blends it
  between a full hip value and a much smaller aimed one via `_ads_blend`.
  Blending rather than gating also covers aiming part-way through a reload, or
  releasing aim mid-cycle — the sway follows the sights in and out.
- **Aimed, the bolt is behind the camera.** With no sway at all a reload reads
  as nothing happening, so the aimed values are deliberately non-zero: enough
  to feel, an order of magnitude too small to reach the lens.
- **Sight geometry sets the ADS distance.** The rear notch must be far enough
  forward that lining it up does not put the buttstock on the lens — that is why
  it is barrel-mounted rather than on the receiver.
- **The gunshot must be ONE shot.** The supplied take
  (`audio/source/gunshot_full_take.wav`, kept behind a `.gdignore` so Godot
  never imports the 1.3MB original) is 14.71s holding ~25 separate shots.
  Assigned whole it plays the entire firing sequence per trigger pull, which
  sounds exactly like an infinite loop but is not one — the stream's
  `loop_mode` is disabled. `tools/trim_gunshot.py` lifts the single best bang
  out of it (9.10s in, sharpest attack in the take) and soft-clips it for
  loudness: peak-normalising alone only moves the highest sample to full scale,
  whereas driving into a tanh lifts RMS by ~5.6dB, which is what the ear reads
  as loud.
- **`compress/mode` in a `.import` can be reverted by a later editor pass.**
  Both weapon sounds want `compress/mode=0` (PCM) because QOA smears the
  transient. Set it, run the import, then *verify* — a full editor scan has
  overwritten it back to QOA before.
- **The audio probe self-gates at runtime.** `GUN_AUDIO_PROBE=1` bakes an
  AudioProbe node into `GunTest.tscn`; left active it pulls the trigger every
  0.25s, which looks precisely like the game re-firing on its own. It now frees
  itself unless the env var is set at run time too.
- **The archive.org recording below is superseded** by the supplied take, but
  `tools/fetch_gunshot.py` still works if you want it back.
- **The gunshot is a real recording, not synthesised.** `tools/fetch_gunshot.py`
  pulls track 04 of *GOLD TAPE: 33 Explosions and War* from archive.org, which
  is **CC0 1.0** (public domain dedication -- shippable commercially, no
  attribution required), isolates the cleanest single shot and trims it. Run it
  to regenerate; the 5MB source caches under `tools/.cache/` which carries a
  `.gdignore` so Godot never imports it.
  It is deliberately kept at 48kHz where the rest of the audio set is 22050Hz
  lo-fi: a rifle's crack lives in the top octaves and downsampling is precisely
  what made the synthesised one sound like a toy. Both weapon sounds are also
  forced to **PCM** in their `.import` (`compress/mode=0`) rather than Godot's
  default QOA, because lossy compression smears the transient that makes the
  shot hit. The previous synthesised version is kept as `audio/gunshot_synth.wav`.
- **Additive flash colour stays under white.** The three flame petals overlap,
  and their colours sum; authored near white the whole flash saturates into a
  flat blob.
- **Any `--script X.gd` tool that instantiates `Player.tscn` can silently
  strip `player.gd` from the save.** `player.gd` reads the `SettingsManager`
  autoload. A bare `extends MainLoop` script (which is what every tool in
  this file is) never spins up a `SceneTree`, so autoloads never register and
  the identifier fails to resolve -- `load(PLAYER).instantiate()` prints a
  `SCRIPT ERROR` but keeps going, the script slot on the root node comes back
  null, and a subsequent `ResourceSaver.save()` writes `Player.tscn` back out
  *without* `script = ExtResource(...)` at all. The node tree still looks
  fine in a hierarchy dump; only the missing `script` property gives it away.
  This bit `patch_player_hands.gd` on the first run and had to be repaired by
  hand. Until these tools are moved to `extends SceneTree` (which does
  initialize autoloads), do not rerun `patch_player.gd`,
  `patch_player_hands.gd`, or `build_guntest.gd` without diffing
  `Player.tscn` afterward for a missing root `script =` line and a vanished
  `id="1_p0vlq"` ext_resource. Property-only edits through the live MCP
  editor session (`node_set_property`, `scene_save`) don't hit this at all --
  the editor's own `SceneTree` has autoloads loaded, so prefer that path for
  anything short of a full geometry rebuild.

---

# Player hands / sleeves pipeline

```sh
# Paints a small skin+wool atlas, crops it into two textures, and builds
# PlayerHands.tscn as chunky CSG box primitives.
"$GODOT" --headless --path . --script res://tools/build_hands.gd

# Instances PlayerHands.tscn into Player.tscn as a SIBLING of WWIRifle under
# WeaponPivot -- see the MainLoop/SettingsManager gotcha above before
# rerunning this one; diff Player.tscn afterward.
"$GODOT" --headless --path . --script res://tools/patch_player_hands.gd
```

Chunky, squared, Pixar-"Up"-inspired veteran's hands: weathered tan skin,
coarse olive-drab wool sleeves, built entirely from `CSGBox3D` primitives the
same way `WWIRifle` is -- plain boxes parented under a plain `Node3D`, no CSG
boolean tree. `PlayerHands` is its own scene, instanced into `Player.tscn`
rather than added as raw nodes, and it sits beside `WWIRifle`, never inside
it, so nothing here ever touches the rifle and the hands can get their own
`AnimationPlayer` later without any risk to the gun's.

## Hands gotchas

- **Rifle-local space is shared, unearned.** `WWIRifle` sits at the origin of
  `WeaponPivot` (see the weapon gotchas above), and `PlayerHands` is placed at
  that same origin as its sibling. That means `HandGrip`/`HandForend`'s
  positions can be authored directly against `WWIRifle`'s own child
  transforms (e.g. `Grip` at `(0, -0.06, 0.539)`) without any extra offset
  math -- both trees live in the same frame.
- **The gun deliberately does not cast a flashlight shadow** (`layers = 4` on
  every rifle primitive, matched by the flashlight's
  `shadow_caster_mask = 4294967291`, which excludes that layer). The hands
  are left on the default layer specifically so they aren't excluded, plus
  `cast_shadow = ON` explicitly on every box -- inspect
  `PlayerHands/HandGrip/Palm` with `node_get_properties` if a rebuild ever
  looks like it stopped throwing a shadow.
- **`editor_screenshot(source="cinematic")` renders raw edit-time
  transforms, not gameplay ones.** `player.gd` only ever pushes
  `WeaponPivot.position` to the hip/ADS offset from `_process()`, which does
  not run outside a live game. A cinematic capture with the scene merely
  *open* shows `WeaponPivot` sitting at the editor-time `(0,0,0)` -- the
  entire gun+hands assembly crammed right up against the near plane. Either
  temporarily set `WeaponPivot.position` for the shot (and revert it after --
  the saved value must stay `(0,0,0)`, `player.gd` owns it at runtime), or
  use `source="game"` against an actual `project_run` session.
- **CSG UV scale on a small primitive is not worth fighting.** A box's native
  UV window shrinks with its size, so a 2cm finger only ever samples a sliver
  of whatever texture it's given. Rather than rely on `uv1_offset`/`uv1_scale`
  atlas math staying correct across wildly different box sizes, `build_hands.gd`
  crops the painted atlas into two dedicated, single-purpose textures (skin,
  fabric) up front and gives each primitive a full `0..1` read of its own
  crop -- correct regardless of which sliver a given box's UVs land on.

---

# Branding — Parnitha 1937

```sh
# Trim + downscale the supplied logos and bake the glow plate.
"$GODOT" --headless --path . --script res://tools/prep_logos.gd

# Rebuild ui/MainMenu.tscn with the branding.
"$GODOT" --headless --path . --script res://tools/build_menu.gd

# Preview it without opening the editor.
MENU_SHOT_DIR=/tmp "$GODOT" --path . res://scenes/dev/MenuShot.tscn
```

`prep_logos.gd` reads the originals from an absolute path in the scratchpad —
point `SRC` at wherever the source PNGs live if they need re-processing.

## Branding gotchas

- **Both supplied logos are drawn for light backgrounds.** The ATT hourglass is
  black linework over dark red and the Agile Advisors mark has a black wordmark;
  on the near-black menu each loses half of itself. The ATT mark gets a baked
  radial glow plate behind it, and the AA mark sits on a light plaque. Neither
  logo is recoloured — brand assets are used as supplied.
- **Resize before scanning alpha.** `prep_logos.gd` trims transparent margins,
  but scanning 4096×4096 with `get_pixel()` from GDScript takes minutes; it
  downscales first and reads the raw buffer, which is visually identical and
  runs in seconds.
- **`main_menu.gd` owns node paths.** It reaches for
  `VBoxContainer/PlayButton` and friends and inserts a debug button at index 1,
  so the rebuilt menu keeps those exact names.

---

# Skinwalker activation

Armed by `active_level` (2) plus physically entering the Park of Souls.

```sh
# Rebuild the park's trigger volume if the park geometry changes.
"$GODOT" --headless --path . --script res://tools/add_park_trigger.gd

# Verify: dormant on 1 and 3, wakes on entry in 2.
SW_LEVEL=2 LEVEL_PATH=res://scenes/levels/Level2.tscn "$GODOT" --path . res://scenes/dev/SkinwalkerTest.tscn
SW_DEBUG_FORCE=1 SW_LEVEL=1 LEVEL_PATH=res://scenes/levels/Level1.tscn "$GODOT" --path . res://scenes/dev/SkinwalkerTest.tscn
```

## Gotchas

- **The level scene owns `GameManager.level`.** `level.gd` exports
  `level_number` and writes it to GameManager at the top of `_ready()`. Before
  this, the main menu's *Debug Level 2* button (and running a level .tscn
  directly from the editor) jumped straight into the scene without touching
  GameManager, so `level` stayed at 1 — the skinwalker could never arm, and
  pack spawning silently produced no babies. If a new level is added, set
  `level_number` on its root or it will behave as Level 1.
- **The old fallback woke it on every level.** `_process_dormant` used to activate
  the skinwalker if no Park of Souls turned up within 5 seconds, so it roamed in
  Level 1 and Level 3 where no park exists at all. That fallback is gone; there
  is now no path to activation except the park trigger or `debug_force_activate`.
- **Proximity is not entry.** It used to fire at 70m from the park's origin.
  `ParkOfSouls.tscn` now carries a `ParkTrigger` Area3D sized to the park's own
  footprint (~25x25m), so the player has to walk in among the statues.
- **The park is spawned at runtime** by `forest_generator.gd`, so the trigger
  cannot be bound in `_ready`. `_bind_park_trigger()` retries each dormant frame
  until it appears.
- **The HUD readout is unchanged.** It still reads exactly
  `"Skinwalker Activated"`; only the console line carries the reason, so debug
  activation and real activation look identical in game.
