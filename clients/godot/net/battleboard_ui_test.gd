extends SceneTree
# Headless test for the 2-D BATTLE BOARD (scenes/BattleBoard.gd) — the coordinator
# order path. The board is DISPLAY-ONLY theatre (no server, no core, no wire), so
# this is a plain logic test of the coordinator seam: force spawn, MOVE and ENGAGE
# orders, the engage → close → fire → resolve loop, red SAM auto-defense, and reset.
# The script is instanced OFF-TREE (no _ready → no UI/terrain build, no _process) and
# stepped by calling _sim_step directly — the slice-16 mock-harness pattern.
#
# Run:  godot --headless --path clients/godot --script res://net/battleboard_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const BoardScript := preload("res://scenes/BattleBoard.gd")

var _bb

func _initialize() -> void:
	print("BBUI_INIT godot=", Engine.get_version_info().string)
	var bb = BoardScript.new()          # NOT added to the tree → _ready never fires
	_bb = bb
	bb._spawn_forces()

	# ---- force spawn: 12 blue + 8 red, everyone alive, red armor has its patrol ----
	var n_blue := 0
	var n_red := 0
	for u in bb._units:
		if u["alive"]:
			if u["side"] == "blue":
				n_blue += 1
			else:
				n_red += 1
	print("BBUI_SPAWN blue=%d red=%d" % [n_blue, n_red])
	if n_blue != 12 or n_red != 8:
		return _fail("expected 12 blue + 8 red alive units, got %d + %d" % [n_blue, n_red])
	if not bb._by_id("R-ARM").has("patrol"):
		return _fail("R-ARM must carry a patrol loop")

	# ---- MOVE order: a selected tank platoon closes on the waypoint ----
	bb._sel = ["B-ARM1"]
	var wp := Vector2(20000.0, 10000.0)
	bb._issue_move(wp)
	var tank = bb._by_id("B-ARM1")
	if tank["order"] == null or tank["order"]["kind"] != "move":
		return _fail("MOVE order did not land on B-ARM1: %s" % str(tank["order"]))
	var d0: float = tank["pos"].distance_to(wp)
	for i in range(40):
		bb._sim_step(0.5)
	var d1: float = tank["pos"].distance_to(wp)
	print("BBUI_MOVE d0=%.0f d1=%.0f" % [d0, d1])
	if d1 >= d0:
		return _fail("B-ARM1 did not close on its waypoint (%.0f → %.0f m)" % [d0, d1])

	# ---- ENGAGE order: artillery vs the red armor company — fires, then kills ----
	# Park the target inside the arty ring so the test exercises fire/resolve, not a
	# long march (the march is already covered by the MOVE assert above).
	var arty = bb._by_id("B-ARTY")
	var ram = bb._by_id("R-ARM")
	ram.erase("patrol")                  # hold still for the shoot
	ram["order"] = null
	ram["pos"] = arty["pos"] + Vector2(12000.0, 0.0)   # inside the 16-km ring
	bb._sel = ["B-ARTY"]
	bb._issue_engage("R-ARM")
	if arty["order"] == null or arty["order"]["kind"] != "engage":
		return _fail("ENGAGE order did not land on B-ARTY: %s" % str(arty["order"]))
	var fired := false
	var steps := 0
	while ram["alive"] and steps < 4000:
		bb._sim_step(0.25)
		steps += 1
		if not bb._shots.is_empty():
			fired = true
	print("BBUI_ENGAGE fired=%s dead=%s steps=%d booms=%d" %
			[str(fired), str(not ram["alive"]), steps, bb._booms.size()])
	if not fired:
		return _fail("B-ARTY never fired at R-ARM inside its ring")
	if ram["alive"]:
		return _fail("R-ARM survived %d steps of seeded 155 mm fire (pk=0.65)" % steps)
	bb._sim_step(0.25)                   # the shooter notices the kill on its NEXT step
	if arty["order"] != null:
		return _fail("B-ARTY should go idle once its target dies, order=%s" % str(arty["order"]))

	# ---- weapon gating: an unarmed asset and a wrong-domain weapon both refuse ----
	bb._sel = ["B-AEW", "B-SAM"]         # no weapon / air-only weapon
	bb._issue_engage("R-CP")             # a land target
	if bb._by_id("B-AEW")["order"] != null or bb._by_id("B-SAM")["order"] != null:
		return _fail("unarmed/wrong-domain units accepted an engage order")

	# ---- red auto-defense: blue air inside a red SAM ring draws fire ----
	var cap = bb._by_id("B-CAP1")
	var rsam = bb._by_id("R-SAM1")
	cap["order"] = null
	cap["station"] = rsam["pos"] + Vector2(-6000.0, 0.0)
	cap["pos"] = cap["station"]
	var red_shot := false
	for i in range(80):
		bb._sim_step(0.25)
		for s in bb._shots:
			if s["side"] == "red" and s["tgt"] == "B-CAP1":
				red_shot = true
	print("BBUI_REDAI red_shot=%s cap_alive=%s" % [str(red_shot), str(cap["alive"])])
	if not red_shot:
		return _fail("R-SAM1 never auto-engaged blue air inside its 13-km ring")

	# ---- reset: full rosters back, clocks/orders/effects cleared ----
	bb._spawn_forces()
	var alive := 0
	for u in bb._units:
		if u["alive"]:
			alive += 1
	if alive != 20 or not bb._shots.is_empty() or bb._t != 0.0:
		return _fail("reset did not restore the board (alive=%d shots=%d t=%.1f)" %
				[alive, bb._shots.size(), bb._t])

	print("BBUI OK: 12+8 spawn; MOVE closes on the waypoint; ENGAGE fires and kills inside " +
			"the ring then goes idle; unarmed/wrong-domain refuse; red SAM auto-defends its " +
			"ring; reset restores the board")
	_teardown()
	quit(0)

func _fail(msg: String) -> void:
	push_error("BBUI FAIL: " + msg)
	print("BBUI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _bb != null:
		_bb.free()
		_bb = null
