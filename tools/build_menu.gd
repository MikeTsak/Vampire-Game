extends MainLoop
## Rebuilds ui/MainMenu.tscn with the Parnitha 1937 branding.
##
## Node names main_menu.gd depends on are preserved exactly: a VBoxContainer
## holding PlayButton / SettingsButton / ModelViewerButton / ExitButton, since
## the script reaches for those paths and inserts a debug button at index 1.

const MENU := "res://ui/MainMenu.tscn"
const BRAND := "res://textures/branding/"
const FONT := "res://textures/fonts/fonnts.com-PF-Hellenica-.otf"

const BG := Color(0.035, 0.030, 0.038)
const BLOOD := Color(0.62, 0.07, 0.09)
const BONE := Color(0.74, 0.70, 0.63)
const DIM := Color(0.42, 0.39, 0.38)

var _font: Font = null

func _initialize() -> void:
	_font = load(FONT)
	var root := Control.new()
	root.name = "MainMenu"
	root.set_script(load("res://scripts/main_menu.gd"))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	root.add_child(_header())
	root.add_child(_buttons())
	root.add_child(_footer())

	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	print("save err=%d" % ResourceSaver.save(ps, MENU))
	root.free()
	print("MENU_DONE")

func _label(name: String, text: String, size: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.name = name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	return l

# ------------------------------------------------------------------ header

func _header() -> Control:
	var box := VBoxContainer.new()
	box.name = "Header"
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = 18.0
	box.offset_bottom = 308.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Logo sits on its glow: a plain Control lets the two overlap.
	var stack := Control.new()
	stack.name = "LogoStack"
	stack.custom_minimum_size = Vector2(0, 132)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stack)

	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.texture = load(BRAND + "logo_glow.png")
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.offset_left = -150.0
	glow.offset_right = 150.0
	glow.offset_top = -150.0
	glow.offset_bottom = 150.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(glow)

	var mark := TextureRect.new()
	mark.name = "AttLogo"
	mark.texture = load(BRAND + "att_logo.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.set_anchors_preset(Control.PRESET_CENTER)
	mark.offset_left = -84.0
	mark.offset_right = 84.0
	mark.offset_top = -65.0
	mark.offset_bottom = 65.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(mark)

	var eyebrow := _label("Eyebrow", "ATHENS  THROUGH  TIME", 15, BONE)
	eyebrow.add_theme_color_override("font_color", Color(0.58, 0.54, 0.48))
	box.add_child(eyebrow)

	var title := _label("Title", "PARNITHA 1937", 66, BLOOD, _font)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var greek := _label("TitleGreek", "ΠΑΡΝΗΘΑ 1937", 20, Color(0.50, 0.46, 0.44), _font)
	box.add_child(greek)

	var tag := _label("Tagline", "an Athens Through Time LARP story", 14, DIM)
	box.add_child(tag)
	return box

# ----------------------------------------------------------------- buttons

func _buttons() -> Control:
	var box := VBoxContainer.new()
	box.name = "VBoxContainer"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -110.0
	box.offset_right = 110.0
	box.offset_top = -6.0
	box.offset_bottom = 186.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 3)
	for spec in [["PlayButton", "Play"], ["SettingsButton", "Settings"],
			["ModelViewerButton", "Model Viewer"], ["ExitButton", "Exit Game"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.flat = true
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_hover_color", Color(0.92, 0.16, 0.16))
		b.add_theme_color_override("font_focus_color", Color(0.92, 0.16, 0.16))
		b.add_theme_font_size_override("font_size", 20)
		if _font:
			b.add_theme_font_override("font", _font)
		box.add_child(b)
	return box

# ------------------------------------------------------------------ footer

func _footer() -> Control:
	var box := VBoxContainer.new()
	box.name = "Footer"
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.anchor_left = 0.5
	box.anchor_top = 1.0
	box.anchor_right = 0.5
	box.anchor_bottom = 1.0
	box.offset_left = -300.0
	box.offset_right = 300.0
	box.offset_top = -118.0
	box.offset_bottom = -8.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	box.add_child(_label("Credit", "created by  Michail Tsakiroglou", 16, Color(0.58, 0.54, 0.49)))

	# The Agile Advisors mark is a black wordmark; on this background it needs a
	# light plaque behind it or it simply is not there.
	var centre := CenterContainer.new()
	centre.name = "PartnerRow"
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(centre)

	var plaque := PanelContainer.new()
	plaque.name = "Plaque"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.90, 0.88, 0.84, 0.93)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	plaque.add_theme_stylebox_override("panel", sb)
	centre.add_child(plaque)

	var aa := TextureRect.new()
	aa.name = "AgileAdvisorsLogo"
	aa.texture = load(BRAND + "agileadvisors_logo.png")
	aa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aa.custom_minimum_size = Vector2(140, 44)
	plaque.add_child(aa)

	box.add_child(_label("Links", "miketsak.gr   ·   agileadvisors.gr   ·   attlarp.gr",
		14, Color(0.44, 0.41, 0.40)))
	box.add_child(_label("CopyrightLabel", "© 2026 Michail Tsakiroglou", 12, Color(0.32, 0.30, 0.30)))
	return box

func _own(n: Node, own: Node) -> void:
	for c in n.get_children():
		c.owner = own
		_own(c, own)

func _process(_d: float) -> bool:
	return true
