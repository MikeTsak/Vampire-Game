extends RefCounted
## Shared atlas layout for the Skinwalker (Wendigo-Elk) creature.
## Both the texture generator and the mesh UV assignment read these rects,
## so a region can never drift out of sync between paint and unwrap.
##
## Atlas is 256x256 -- the top of the retro-era spec range (64-256px) -- and
## the rects below tile it exhaustively, with no dead space.

const SIZE := 256

# name -> Rect2i in pixels.
const R := {
	"skin":     Rect2i(0, 0, 96, 96),      # mottled brown-gray taut hide (torso)
	"belly":    Rect2i(96, 0, 64, 96),     # thin/taut pale skin, necrotic patches
	"fur":      Rect2i(160, 0, 96, 64),    # matted dark coat, vertical clumps
	"furcard":  Rect2i(160, 64, 96, 32),   # single tuft card, dark falloff at tips
	"gore":     Rect2i(0, 96, 64, 64),     # wet red-black torn flesh
	"rib":      Rect2i(64, 96, 64, 32),    # exposed rib bone, cracked
	"skull":    Rect2i(64, 128, 64, 32),   # skull plate, dirtier ivory
	"antler":   Rect2i(128, 96, 64, 64),   # ridged brown-ivory, chipped tips
	"teeth":    Rect2i(192, 96, 32, 32),   # pale ivory, broken edges
	"mouth":    Rect2i(224, 96, 32, 32),   # near-black wet interior
	"eye":      Rect2i(192, 128, 32, 32),  # dull amber iris in a sunken dark ring
	"claw":     Rect2i(224, 128, 32, 32),  # dark cracked keratin
	"hoof":     Rect2i(0, 160, 32, 32),    # hoof-claw hybrid, near-black
	"sinew":    Rect2i(32, 160, 32, 32),   # stringy tendon (neck, joints)
	"wound":    Rect2i(64, 160, 64, 32),   # raw red wound patch, dry cracked edge
	"dark":     Rect2i(128, 160, 32, 32),  # generic cavity black
	"blood":    Rect2i(160, 160, 96, 32),  # running drips for jaw and sternum
	"skinlimb": Rect2i(0, 192, 96, 64),    # tighter, darker hide over the limbs
	"face":     Rect2i(96, 192, 80, 64),   # snout: dark bridge, pale muzzle, bloodied lip
	"pelt":     Rect2i(176, 192, 80, 64),  # heavy shoulder coat with hide showing through
}

## Per-region roughness. Wet wounds are glossy, bone and hide are matte.
const ROUGH := {
	"skin": 0.86, "belly": 0.80, "fur": 0.96, "furcard": 0.96,
	"gore": 0.18, "rib": 0.74, "skull": 0.78, "antler": 0.82,
	"teeth": 0.46, "mouth": 0.30, "eye": 0.25, "claw": 0.55,
	"hoof": 0.60, "sinew": 0.42, "wound": 0.22, "dark": 0.90,
	"blood": 0.20, "skinlimb": 0.88, "face": 0.82, "pelt": 0.95,
}

## Map a 0-1 local coordinate inside a named region to atlas UV.
## Insets by half a texel so nearest-neighbour filtering can never bleed
## a neighbouring region in along a seam.
static func uv(region: String, u: float, v: float) -> Vector2:
	var r: Rect2i = R[region]
	var inset := 0.5
	var px := float(r.position.x) + inset + clampf(u, 0.0, 1.0) * (float(r.size.x) - 2.0 * inset)
	var py := float(r.position.y) + inset + clampf(v, 0.0, 1.0) * (float(r.size.y) - 2.0 * inset)
	return Vector2(px / float(SIZE), py / float(SIZE))
