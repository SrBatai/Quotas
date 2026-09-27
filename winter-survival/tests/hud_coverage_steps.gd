extends RefCounted
## Body of tests/hud_coverage.gd. Measures the screen coverage of the HUD LAYER ONLY, with the method of
## docs/research/10_hud_ux.md §V.5: the 3D world is not rendered (root.disable_3d), full-screen effects (frost and
## damage vignettes) and gradient scrims are hidden, and the HUD is rendered twice — over black and over white —
## to recover its alpha (a = 1 − (white − black)). Two numbers over the 1920 × 1080 frame:
##   ink    pixels with opacity ≥ 10 %;
##   boxes  area of the union of the bounding boxes of every element after a 15 × 15 px morphological closing
##          (letters grouped into lines and blocks) — the conservative figure used as "coverage".
## GATE: at rest (day, nothing happening) boxes ≤ 3 %. The other moments are reported (not gated).

const GATE_PCT := 3.0
const BLOCK := 2          # the closing / components run on 2 × 2 px cells
const CLOSE_CELLS := 7    # ≈ 15 px window

var tree: SceneTree
var failed: bool = false
var results: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failed = true
		print("FAIL: ", msg)


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func run(p_tree: SceneTree, moments: PackedStringArray, out_dir: String) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA HUD coverage (H1, §V.5 method) at %s px" % tree.root.size)
	GameFlow.play_offline()
	var waited := 0
	while GameFlow.local_player() == null and waited < 2000:
		await tree.process_frame
		waited += 1
	var game := tree.current_scene
	var player: Player = GameFlow.local_player()
	if player == null:
		print("FAIL: no local player")
		tree.quit(1)
		return
	var world: World = game.get_node("World")
	var hud: Hud = game.get("hud")
	UiSettings.get_instance().reset()   # default HUD (Mínimo) whatever this machine saved
	# HUD layer only: no 3D rendering, the other UI panels hidden
	tree.root.disable_3d = true
	for c in game.get_node("UI").get_children():
		if c != hud:
			(c as CanvasItem).visible = false
	world.get_node("WolfSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	var weather: Weather = world.get_node("Weather")
	weather.scheduler_enabled = false
	weather.cancel()
	WorldState.instance.set_time(1, 11.0)
	await tree.create_timer(1.3).timeout   # the opening notice comes and goes through the router
	hud.zones.enabled = false
	for m: String in moments:
		await _setup(m, hud, world, player)
		var r := await measure(hud, m, out_dir)
		results[m] = r
		print("coverage %-9s boxes %5.2f %%  ink %5.2f %%  (%d px ink, %d elements)" % [m, r["boxes"], r["ink"], r["ink_px"], r["blobs"]])
		Engine.time_scale = 1.0
	if results.has("idle"):
		check(float(results["idle"]["boxes"]) <= GATE_PCT, "idle HUD coverage %.2f %% ≤ %.1f %% at 1920 × 1080 (ink %.2f %%)" % [results["idle"]["boxes"], GATE_PCT, results["idle"]["ink"]])
	print("== HUD COVERAGE %s" % ("FAILED" if failed else "OK"))
	tree.quit(1 if failed else 0)


func _setup(m: String, hud: Hud, world: World, player: Player) -> void:
	Engine.time_scale = 1.0
	hud.settle_to_rest()
	player.state.health = Balance.HEALTH_MAX
	player.state.warmth = 90.0
	player.state.hunger = 80.0
	player.state.mark(&"stats")
	await frames(3)
	match m:
		"idle":
			WorldState.instance.set_time(1, 11.0)
			await frames(3)
			hud.settle_to_rest()
			# a few seconds of rest: nothing may come back by itself
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 3000:
				await tree.process_frame
		"action":
			WorldState.instance.set_time(1, 18.4)
			var sys := ZombieSystem.instance
			sys.clear_all()
			var p := player.global_position + Vector3(1.2, 0, -0.4)
			sys.spawn(ZombieKinds.Kind.WALKER, p, 0.0, ZombieKinds.State.CHASE, -1, -2)
			await frames(4)
			player.state.health = 58.0
			player.state.mark(&"stats")
			await frames(2)
			player.stats.take_damage(16.0, &"zombi")
			player.state.stamina = 36.0
			player.state.emit_sim(&"item_picked_up", [&"madera", 2])
			hud.hotbar.poke(true)
			hud.vis.poke(&"edge")
			for i in 8:
				await tree.process_frame
				player.state.stamina = 36.0
			hud.vis.settle()
			Engine.time_scale = 0.0
			sys.clear_all()
		"zone":
			WorldState.instance.set_time(1, 22.5)
			hud.zone_title.show_card(hud.zones.info_for(Locations.by_id("claro_del_cazador"), true, "full"), 1.8)
			await frames(2)
			Engine.time_scale = 0.0
		"blizzard":
			WorldState.instance.set_time(1, 21.5)
			(world.get_node("Weather") as Weather).force_blizzard(160.0)
			world.cabin.stove.burner.add_fuel(600.0)
			var down := Vector3(0.7071, 0.0, 0.7071)
			var c := world.cabin.global_position + down * 7.5 + Vector3(-1.5, 0, 1.5)
			c.y = world.get_height(c.x, c.z)
			player.global_position = c + Vector3(0, 0.2, 0)
			for i in 20:
				await tree.process_frame
				player.state.warmth = 14.0
				player.state.mark(&"stats")
			hud.vis.settle()
			Engine.time_scale = 0.0
		"info":
			WorldState.instance.set_time(1, 15.3)
			hud.input.set_info(true)
			await frames(6)
			hud.vis.settle()
			Engine.time_scale = 0.0
	await frames(2)


## Renders the HUD over black and white and returns {boxes, ink, ink_px, blobs}.
func measure(hud: Hud, moment: String, out_dir: String) -> Dictionary:
	Scrim.suppressed = true
	hud.measure_mode = true
	tree.call_group("hud_scrim", "queue_redraw")
	var black := await _grab(Color.BLACK)
	var white := await _grab(Color.WHITE)
	Scrim.suppressed = false
	hud.measure_mode = false
	tree.call_group("hud_scrim", "queue_redraw")
	RenderingServer.set_default_clear_color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3)))
	if moment == "info":
		hud.input.set_info(false)
	return _metrics(black, white, moment, out_dir)


func _grab(bg: Color) -> Image:
	RenderingServer.set_default_clear_color(bg)
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := tree.root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func _metrics(b: Image, w: Image, moment: String, out_dir: String) -> Dictionary:
	var W := b.get_width()
	var H := b.get_height()
	var bd := b.get_data()
	var wd := w.get_data()
	var cw := W / BLOCK
	var ch := H / BLOCK
	var mask := PackedByteArray()
	mask.resize(cw * ch)
	var alpha := PackedByteArray()
	alpha.resize(W * H)
	var ink := 0
	var i := 0
	for y in H:
		var row := (y / BLOCK) * cw
		for x in W:
			var diff := (int(wd[i]) - int(bd[i]) + int(wd[i + 1]) - int(bd[i + 1]) + int(wd[i + 2]) - int(bd[i + 2])) / 3
			var a := clampi(255 - diff, 0, 255)
			alpha[y * W + x] = a
			if a >= 26:
				ink += 1
				var cx := x / BLOCK
				if cx < cw and y / BLOCK < ch:
					mask[row + cx] = 1
			i += 3
	var closed := _erode(_dilate(mask, cw, ch, CLOSE_CELLS), cw, ch, CLOSE_CELLS)
	var boxes := _union_of_boxes(closed, cw, ch)
	var total := float(W * H)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var img := Image.create_from_data(W, H, false, Image.FORMAT_L8, alpha)
		img.save_png(out_dir.path_join("coverage_%s_alpha.png" % moment))
	return {"boxes": 100.0 * float(boxes["cells"] * BLOCK * BLOCK) / total, "ink": 100.0 * float(ink) / total,
		"ink_px": ink, "blobs": boxes["blobs"]}


## Separable max filter (window `win` cells, outside = 0).
func _dilate(m: PackedByteArray, cw: int, ch: int, win: int) -> PackedByteArray:
	var r := win / 2
	var tmp := PackedByteArray()
	tmp.resize(cw * ch)
	for y in ch:
		var base := y * cw
		var count := 0
		for x in range(0, mini(r, cw)):
			count += m[base + x]
		for x in cw:
			var add := x + r
			if add < cw:
				count += m[base + add]
			var sub := x - r - 1
			if sub >= 0:
				count -= m[base + sub]
			tmp[base + x] = 1 if count > 0 else 0
	var out := PackedByteArray()
	out.resize(cw * ch)
	for x in cw:
		var count := 0
		for y in range(0, mini(r, ch)):
			count += tmp[y * cw + x]
		for y in ch:
			var add := y + r
			if add < ch:
				count += tmp[add * cw + x]
			var sub := y - r - 1
			if sub >= 0:
				count -= tmp[sub * cw + x]
			out[y * cw + x] = 1 if count > 0 else 0
	return out


## Separable min filter (outside = 1, so shapes on the border do not erode).
func _erode(m: PackedByteArray, cw: int, ch: int, win: int) -> PackedByteArray:
	var inv := PackedByteArray()
	inv.resize(cw * ch)
	for i in cw * ch:
		inv[i] = 1 - m[i]
	var d := _dilate(inv, cw, ch, win)
	for i in cw * ch:
		d[i] = 1 - d[i]
	return d


## Connected components (4-neighbours) → their bounding boxes → area of the union (cells) and the count.
func _union_of_boxes(m: PackedByteArray, cw: int, ch: int) -> Dictionary:
	var seen := PackedByteArray()
	seen.resize(cw * ch)
	var cover := PackedByteArray()
	cover.resize(cw * ch)
	var blobs := 0
	var stack := PackedInt32Array()
	for start in cw * ch:
		if m[start] == 0 or seen[start] == 1:
			continue
		blobs += 1
		var x0 := cw
		var y0 := ch
		var x1 := -1
		var y1 := -1
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var cx := c % cw
			var cy := c / cw
			x0 = mini(x0, cx)
			x1 = maxi(x1, cx)
			y0 = mini(y0, cy)
			y1 = maxi(y1, cy)
			for n: int in [c - 1 if cx > 0 else -1, c + 1 if cx < cw - 1 else -1, c - cw if cy > 0 else -1, c + cw if cy < ch - 1 else -1]:
				if n >= 0 and m[n] == 1 and seen[n] == 0:
					seen[n] = 1
					stack.append(n)
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				cover[yy * cw + xx] = 1
	var cells := 0
	for v in cover:
		cells += v
	return {"cells": cells, "blobs": blobs}
