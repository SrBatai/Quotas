class_name Hud
extends Control
## In-game HUD, direction v2 «Susurro» (docs/research/10_hud_ux.md §V; H1). The world is the picture: at rest only
## the hotbar folded into 10 strokes remains (< 3 % of the screen, measured by tests/hud_coverage.gd); everything
## else appears when it changes and fades after 3–5 s (HudVisibility), or on demand while Info is held
## (Tab / D‑pad ↑, HudInput). One amber accent for the one thing that matters now (AccentArbiter), no boxes.
##
## Layout: `root` is the 1920 × 1080 reference space, scaled by k = min(w/1920, h/1080) × UI scale (80–150 %);
## `safe` is the safe box inside it (64 / 52 px + the "Margen de pantalla" setting, the display safe area, and on
## 21:9 a centred 16:9 box by default). Full-screen effects (frost vignette, damage vignette) stay outside `root`.
## Kept for game.gd / tests: `hotbar`, `category_bar` (now shown only while crafting), `down_panel`, `down_title`.

const FROST_SHADER := preload("res://assets/ui/frost_screen.gdshader")

var k: float = 1.0
var root: Control
var safe: Control
var vis: HudVisibility
var input: HudInput
var accent: AccentArbiter
var router: NotifyRouter
var zones: ZoneTracker
var mlog: MissionLog
var team: TeamTracker
var world_layer: WorldLayer
var hotbar: Hotbar
var vitals: Vitals
var mission_line: MissionLine
var mission_list: MissionList
var info_block: InfoBlock
var hazard: HazardLine
var zone_title: ZoneTitle
var banner: NotifyBanner
var feed: PickupStack
var downed: DownedOverlay
var category_bar: CategoryBar
var map_screen: MapScreen
var frost: ColorRect
var damage: TextureRect
## Legacy names (smoke test): the downed overlay and its title label.
var down_panel: Control
var down_title: Label
## Background luma estimate (0..1) that drives the scrims and the adaptive weight.
var luma: float = 0.7
## Coverage measure (tests/hud_coverage.gd): full-screen effects stay off.
var measure_mode: bool = false

var _clock: float = 0.0
var _last_hit: float = -100.0
var _last_swing: float = -100.0
var _flash: float = 0.0
var _luma_acc: float = 0.0
var _settings: UiSettings


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings = UiSettings.get_instance()
	_build_screen_fx()
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.theme()
	add_child(root)
	safe = Control.new()
	safe.name = "Safe"
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(safe)
	# logic
	vis = HudVisibility.new()
	vis.name = "Visibility"
	add_child(vis)
	mlog = MissionLog.new()
	mlog.name = "MissionLog"
	add_child(mlog)
	team = TeamTracker.new()
	team.name = "Team"
	add_child(team)
	accent = AccentArbiter.new()
	accent.name = "Accent"
	add_child(accent)
	accent.setup(team, mlog, vis)
	input = HudInput.new()
	input.name = "Input"
	input.vis = vis
	input.track_next = mlog.track_next
	add_child(input)
	# components (reference space); the world layer first so text draws over it
	world_layer = WorldLayer.new()
	world_layer.name = "WorldLayer"
	root.add_child(world_layer)
	world_layer.setup(self, vis, accent, team, mlog)
	mission_list = MissionList.new()
	mission_list.name = "MissionList"
	safe.add_child(mission_list)
	mission_list.setup(vis, mlog)
	mission_line = MissionLine.new()
	mission_line.name = "MissionLine"
	safe.add_child(mission_line)
	mission_line.setup(vis, mlog)
	hazard = HazardLine.new()
	hazard.name = "HazardLine"
	safe.add_child(hazard)
	hazard.setup(vis)
	vitals = Vitals.new()
	vitals.name = "Vitals"
	safe.add_child(vitals)
	vitals.setup(vis)
	info_block = InfoBlock.new()
	info_block.name = "InfoBlock"
	safe.add_child(info_block)
	info_block.setup(vis, team, vitals, hazard)
	feed = PickupStack.new()
	feed.name = "PickupStack"
	safe.add_child(feed)
	zone_title = ZoneTitle.new()
	zone_title.name = "ZoneTitle"
	root.add_child(zone_title)
	banner = NotifyBanner.new()
	banner.name = "Banner"
	root.add_child(banner)
	hotbar = Hotbar.new()
	hotbar.name = "Hotbar"
	root.add_child(hotbar)
	hotbar.setup(vis)
	downed = DownedOverlay.new()
	downed.name = "Downed"
	downed.team = team
	root.add_child(downed)
	down_panel = downed
	down_title = downed.title
	router = NotifyRouter.new()
	router.name = "NotifyRouter"
	router.banner = banner
	router.feed = feed
	router.hazard = hazard
	router.zone_title = zone_title
	router.vis = vis
	add_child(router)
	zones = ZoneTracker.new()
	zones.name = "ZoneTracker"
	zones.in_combat = in_combat
	zones.p0_active = p0_active
	add_child(zones)
	# the paper map and the journal (M / Back): a full screen on demand, not part of the HUD
	map_screen = MapScreen.new()
	map_screen.name = "Map"
	map_screen.hud = self
	root.add_child(map_screen)
	# legacy crafting categories: only while the craft panel is open (appendix §1.2)
	category_bar = CategoryBar.new()
	category_bar.name = "CategoryBar"
	category_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	category_bar.offset_left = 16
	category_bar.offset_top = -160
	add_child(category_bar)
	Events.stat_changed.connect(_on_stat)
	Events.player_damaged.connect(func(_a: float, _s: StringName) -> void:
		_last_hit = _clock
		_flash = 1.0)
	Events.local_swing.connect(func(_c: StringName) -> void: _last_swing = _clock)
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	_settings.changed.connect(_on_settings)
	_on_settings()


func _build_screen_fx() -> void:
	frost = ColorRect.new()
	frost.name = "Frost"
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = FROST_SHADER
	m.set_shader_parameter("strength", 0.0)
	frost.material = m
	frost.visible = false
	add_child(frost)
	damage = TextureRect.new()
	damage.name = "DamageVignette"
	damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	damage.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0.55, 0.06, 0.11, 0.0), Color(0.55, 0.06, 0.11, 0.0), Color(0.55, 0.06, 0.11, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.55)
	gt.fill_to = Vector2(1.05, 0.55)
	gt.width = 128
	gt.height = 128
	damage.texture = gt
	damage.modulate.a = 0.0
	damage.visible = false
	add_child(damage)


func _on_settings() -> void:
	UiStyle.set_flags(UiStyle.bright, bool(_settings.values.get("text_bold", false)))
	_layout()
	get_tree().call_group("hud_scrim", "queue_redraw")


## Reference scale, safe box and block positions (called on resize and on settings changes). `vp_override`:
## lay out for another canvas size (tests of 21:9 / 16:10).
func _layout(vp_override: Vector2 = Vector2.ZERO) -> void:
	if root == null:
		return
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	if vp_override != Vector2.ZERO:
		vp = vp_override
	k = minf(vp.x / UiTokens.REF_SIZE.x, vp.y / UiTokens.REF_SIZE.y) * _settings.ui_scale()
	k = maxf(k, 0.05)
	root.scale = Vector2(k, k)
	root.position = Vector2.ZERO
	root.size = vp / k
	var ref := root.size
	var margin := float(_settings.values.get("screen_margin", 0.0))
	var mx := UiTokens.SAFE_X + ref.x * margin
	var my := UiTokens.SAFE_Y + ref.y * margin
	var box := Rect2(mx, my, ref.x - mx * 2.0, ref.y - my * 2.0)
	# display safe area (TV / notch), when the window covers the screen
	var sa := _display_insets(ref)
	box.position += sa.position
	box.size -= sa.position + sa.size
	# 21:9 and wider: corner blocks stay in a centred 16:9 (or 21:9) box by default (appendix §5.7)
	var width_mode: StringName = _settings.values.get("hud_width", &"16:9")
	var max_ratio := 16.0 / 9.0 if width_mode == &"16:9" else (21.0 / 9.0 if width_mode == &"21:9" else 100.0)
	if ref.x / ref.y > max_ratio + 0.01:
		var w := ref.y * max_ratio
		box.position.x = (ref.x - w) * 0.5 + mx
		box.size.x = w - mx * 2.0
	safe.position = box.position
	safe.size = box.size
	var sw := safe.size
	world_layer.position = Vector2.ZERO
	world_layer.size = ref
	mission_list.position = Vector2.ZERO
	mission_list.size = sw
	mission_line.position = Vector2(0.0, 4.0)
	mission_line.size = Vector2(760.0, 140.0)
	hazard.position = Vector2(sw.x - 760.0, 4.0)
	hazard.size = Vector2(760.0, 40.0)
	info_block.position = Vector2(sw.x - 760.0, 4.0)
	info_block.size = Vector2(760.0, 110.0)
	vitals.position = Vector2(0.0, sw.y - 240.0)
	vitals.size = Vector2(700.0, 240.0)
	feed.position = Vector2(sw.x - 560.0, sw.y - 240.0)
	feed.size = Vector2(560.0, 200.0)
	zone_title.position = Vector2.ZERO
	zone_title.size = ref
	banner.position = Vector2.ZERO
	banner.size = Vector2(ref.x, 260.0)
	var hw := hotbar.custom_minimum_size.x
	var hh := hotbar.custom_minimum_size.y
	hotbar.size = Vector2(hw, hh)
	hotbar.position = Vector2((ref.x - hw) * 0.5, ref.y - UiTokens.HOTBAR_BOTTOM - hh)
	downed.position = Vector2.ZERO
	downed.size = ref
	map_screen.position = Vector2.ZERO
	map_screen.size = ref
	if map_screen.is_open:
		map_screen._layout()
	(frost.material as ShaderMaterial).set_shader_parameter("ref_size", ref)


## Insets of the display safe area in reference px (zero on a desktop window).
func _display_insets(ref: Vector2) -> Rect2:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return Rect2()
	var win := DisplayServer.window_get_size()
	var scr := DisplayServer.screen_get_size()
	var area := DisplayServer.get_display_safe_area()
	if win != scr or area.size == Vector2i.ZERO or area.size == scr:
		return Rect2()
	var sx := ref.x / float(scr.x)
	var sy := ref.y / float(scr.y)
	return Rect2(Vector2(area.position.x * sx, area.position.y * sy),
		Vector2((scr.x - area.end.x) * sx, (scr.y - area.end.y) * sy))


# ------------------------------------------------------------------ state for the components
## In combat (the zone card waits): hit, swing or a zombie chasing within 25 m in the last 5 s.
func in_combat() -> bool:
	if _clock - _last_hit < UiTokens.COMBAT_WINDOW or _clock - _last_swing < UiTokens.COMBAT_WINDOW:
		return true
	var p := GameFlow.local_player() as Node3D
	if p == null or ZombieClient.instance == null:
		return false
	for id in ZombieClient.instance.records:
		var z: ZombieClient.ZRec = ZombieClient.instance.records[id]
		if (z.state == ZombieKinds.State.CHASE or z.state == ZombieKinds.State.ATTACK) \
				and Vector2(z.render_pos.x - p.global_position.x, z.render_pos.z - p.global_position.z).length() < 25.0:
			_last_hit = maxf(_last_hit, _clock - UiTokens.COMBAT_WINDOW + 1.0)
			return true
	return false


## A P0 condition is on (downed, freezing): zone cards turn compact and wait.
func p0_active() -> bool:
	var p := GameFlow.local_player() as Player
	return p != null and (p.downed or (p.state != null and p.state.warmth < Balance.FREEZING_SLOW_BELOW))


## Rectangles (reference px) the edge marker must not land on.
func exclusion_rects() -> Array:
	var out: Array = []
	out.append(Rect2(hotbar.position + Vector2(-20, -60), hotbar.size + Vector2(40, 100)))
	if vis.alpha_of(&"vitals.health") + vis.alpha_of(&"vitals.warmth") + vis.alpha_of(&"vitals.hunger") > 0.05:
		out.append(Rect2(safe.position + vitals.position + Vector2(-40, 100), Vector2(420, 180)))
	if mission_line.visible:
		out.append(Rect2(safe.position + mission_line.position + Vector2(-40, -20), Vector2(480, 150)))
	if hazard.visible or info_block.visible:
		out.append(Rect2(safe.position + Vector2(safe.size.x - 460.0, -20.0), Vector2(520, 170)))
	return out


# ------------------------------------------------------------------ frame
func _on_stat(stat: StringName, value: float, _max: float) -> void:
	if stat == &"warmth":
		var s := clampf(1.0 - value / UiTokens.FROST_START, 0.0, 1.0)
		(frost.material as ShaderMaterial).set_shader_parameter("strength", s)
		frost.visible = s > 0.005 and not measure_mode


func _process(delta: float) -> void:
	_clock += delta
	# damage vignette: 250 ms flash on a hit, a slow heartbeat below 25 health, steady while downed
	var p := GameFlow.local_player() as Player
	var a := 0.0
	var no_flash := bool(_settings.values.get("reduced_flashes", false))
	if _flash > 0.0:
		_flash = maxf(_flash - delta / UiTokens.T_DAMAGE_FLASH, 0.0)
		if not no_flash:
			a = maxf(a, 0.8 * _flash)
	if p != null and p.state != null:
		if p.downed and not p.dead:
			a = maxf(a, 0.75)
		elif p.state.health < Balance.LOW_HEALTH and not p.dead:
			var beat := 0.3 if no_flash else 0.22 + 0.16 * pow(maxf(sin(_clock * TAU * 1.1), 0.0), 3.0)
			a = maxf(a, beat)
	damage.modulate.a = a
	damage.visible = a > 0.002 and not measure_mode
	if measure_mode:
		frost.visible = false
	# background luma estimate → scrim α (4 Hz)
	_luma_acc += delta
	if _luma_acc >= 0.25:
		_luma_acc = 0.0
		_update_luma(p)


## Luma of the picture behind the HUD, estimated from the time of day, the weather and being indoors (reading the
## screen back every 0.25 s would cost a GPU→CPU copy): snow by day ≈ 0.78, night ≈ 0.30, blizzard ≈ 0.72.
func _update_luma(p: Player) -> void:
	var h := WorldState.hour_now()
	var day := 0.78
	var night := 0.30
	var l := night
	if h >= 8.0 and h < 18.0:
		l = day
	elif h >= 18.0 and h < 21.0:
		l = lerpf(day, night, (h - 18.0) / 3.0)
	elif h >= 5.0 and h < 8.0:
		l = lerpf(night, day, (h - 5.0) / 3.0)
	if WorldState.weather_now() == &"blizzard":
		l = maxf(l, 0.62)
	if p != null and p.in_house:
		l = 0.35
	if absf(l - luma) < 0.01:
		return
	luma = l
	Scrim.base_alpha = UiTokens.scrim_alpha(luma)
	UiStyle.set_flags(luma > UiTokens.BRIGHT_LUMA, bool(_settings.values.get("text_bold", false)))
	get_tree().call_group("hud_scrim", "queue_redraw")


# ------------------------------------------------------------------ tests / screenshots
## Every transient element jumps to rest (the zone card and banners end, fades finish).
func settle_to_rest() -> void:
	vis.clear_all()
	vis.set_info(false)
	zone_title.t = -1.0
	zone_title.visible = false
	router.queue.clear()
	router.current = {}
	banner.show_notice({}, 0)
	banner.visible = false
	feed.lines.clear()
	mission_line._since = 99.0
	vis.settle()
