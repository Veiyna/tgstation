/// FNF rhythm minigame — chart-accurate timing, movement lock, healthbar, dance poses

#define FNF_SCROLL_ADVANCE  15      // ticks before hit time to spawn an arrow (1.5 s)
#define FNF_BAR_WIDTH       96      // healthbar width in pixels
#define FNF_BAR_HEIGHT      10      // healthbar height in pixels
#define FNF_HEAD_SIZE       32      // portrait sprite size (matches bf.dmi / pico.dmi icon size)
#define FNF_HUD_Y           80      // pixels above stage_obj for the whole HUD row
#define FNF_HEALTH_STEP     6       // health change per hit/miss
#define FNF_SLOT_Y          64      // pixel_y of the arrow slot row (above mob head)
#define FNF_ARROW_SPAWN_Y  -64      // where arrows first appear (below, scrolls up to FNF_SLOT_Y)

/datum/fnf_minigame
	var/datum/weakref/player_ref
	var/datum/weakref/opponent_ref
	var/datum/fnf_minigame/linked_game
	/// TRUE = challenger (BF/player side). FALSE = opponent side.
	var/is_player_side = TRUE

	var/battle_active  = FALSE
	var/list/chart_notes
	var/song_dir
	var/song_name      = "Unknown"
	var/song_bpm       = 100
	/// Song end time in ticks from begin(), set by the microphone from combined chart data.
	var/song_end_ticks = 0

	var/list/cached_arrows
	var/image/minigame_holder
	var/obj/effect/fnf_stage/stage_obj
	var/song_end_timer

	// ── Healthbar ────────────────────────────────────────────────────────────
	/// 0–100 from challenger's view. Only the master (is_player_side=TRUE) updates this.
	var/health_pct         = 50
	var/image/hud_bar_img
	var/image/hud_pl_head_img   // BF portrait — right end of bar (green side)
	var/image/hud_en_head_img   // Pico portrait — left end of bar (red side)

// ── Construction ───────────────────────────────────────────────────────────

/datum/fnf_minigame/New(mob/living/player, mob/living/opponent, list/notes, song_dir_path, song_bpm_val = 100)
	. = ..()
	player_ref    = WEAKREF(player)
	opponent_ref  = WEAKREF(opponent)
	chart_notes   = notes
	song_dir      = song_dir_path
	song_bpm      = song_bpm_val
	cached_arrows = list()

	RegisterSignal(player, COMSIG_MOVABLE_ATTEMPTED_MOVE, PROC_REF(on_player_move))
	RegisterSignal(player, COMSIG_MOVABLE_PRE_MOVE,       PROC_REF(block_player_move))
	RegisterSignal(player, COMSIG_QDELETING,              PROC_REF(lose_minigame))

	minigame_holder = image(icon = 'icons/effects/effects.dmi', loc = player, icon_state = "nothing", layer = ABOVE_ALL_MOB_LAYER + 1)
	player.client?.images |= minigame_holder
	generate_visuals()

// ── Begin ──────────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/begin(is_music_master = FALSE)
	var/mob/living/player = player_ref?.resolve()
	if(!player)
		return
	var/mob/living/opp = opponent_ref?.resolve()

	battle_active = TRUE

	var/opp_name = opp?.name || "an opponent"
	to_chat(player, span_notice("FNF Battle: [song_name] vs [opp_name] — Go!"))

	if(is_music_master)
		// ── Position: challenger stays, opponent 2 tiles ahead, stage in middle ──
		var/turf/player_turf = get_turf(player)
		var/face_dir = player.dir
		if(face_dir != NORTH && face_dir != SOUTH && face_dir != EAST && face_dir != WEST)
			face_dir = SOUTH

		var/turf/step1 = get_step(player_turf, face_dir)
		var/turf/step2 = step1 ? get_step(step1, face_dir) : null

		var/turf/opp_turf
		var/turf/mid_turf

		if(step2 && !step2.density)
			opp_turf = step2
			mid_turf = step1
		else if(step1 && !step1.density)
			opp_turf = step1
			mid_turf = player_turf
		else
			opp_turf = player_turf
			mid_turf = player_turf

		if(opp) opp.forceMove(opp_turf)
		player.setDir(face_dir)
		if(opp) opp.setDir(turn(face_dir, 180))

		stage_obj = new /obj/effect/fnf_stage(mid_turf)

		send_battle_audio(player, opp)
		create_health_hud(player, opp)

	schedule_notes()

// ── Audio ──────────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/send_battle_audio(mob/living/player, mob/living/opp)
	if(!song_dir)
		return
	var/audio_path = "sound/fnf/[song_dir]/Mixed.ogg"
	if(!fexists(audio_path))
		audio_path = "sound/fnf/[song_dir]/Inst.ogg"
	if(fexists(audio_path))
		var/sound/track = sound(audio_path, channel = 1025, volume = 60)
		SEND_SOUND(player, track)
		if(opp) SEND_SOUND(opp, track)

/datum/fnf_minigame/proc/stop_music_for(mob/living/target)
	if(!target)
		return
	SEND_SOUND(target, sound(null, channel = 1025))

// ── Healthbar ──────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/create_health_hud(mob/living/player, mob/living/opp)
	if(!stage_obj)
		return

	// Shift the entire HUD left by half a tile to center it visually between the two fighters.
	var/x_shift = -16
	var/portrait_y = FNF_HUD_Y - (FNF_HEAD_SIZE - FNF_BAR_HEIGHT) / 2

	hud_bar_img = image(icon = make_health_bar_icon(), loc = stage_obj, layer = ABOVE_ALL_MOB_LAYER + 3)
	hud_bar_img.pixel_x = -48
	hud_bar_img.pixel_y = FNF_HUD_Y

	// BF portrait — RIGHT end of bar (green / player side). bf.dmi already faces left.
	hud_pl_head_img = image(icon = 'icons/mob/bf.dmi', icon_state = "normal", loc = stage_obj, layer = ABOVE_ALL_MOB_LAYER + 3)
	hud_pl_head_img.pixel_x = x_shift + (FNF_BAR_WIDTH / 2 + FNF_HEAD_SIZE / 2 + 4)
	hud_pl_head_img.pixel_y = portrait_y

	// Pico portrait — LEFT end of bar (red / enemy side). pico.dmi faces right toward BF.
	hud_en_head_img = image(icon = 'icons/mob/pico.dmi', icon_state = "normal", loc = stage_obj, layer = ABOVE_ALL_MOB_LAYER + 3)
	hud_en_head_img.pixel_x = x_shift - (FNF_BAR_WIDTH / 2 + FNF_HEAD_SIZE / 2 + 4)
	hud_en_head_img.pixel_y = portrait_y

	// Push to both clients
	player.client?.images |= hud_bar_img
	player.client?.images |= hud_pl_head_img
	player.client?.images |= hud_en_head_img
	if(opp?.client)
		opp.client.images |= hud_bar_img
		opp.client.images |= hud_pl_head_img
		opp.client.images |= hud_en_head_img

/**
 * Draw the healthbar icon.
 * FNF convention: player (green) fills from the RIGHT, enemy (red) from the LEFT.
 * health_pct=50 → equal split. health_pct=100 → all green. health_pct=0 → all red.
 */
/datum/fnf_minigame/proc/make_health_bar_icon()
	var/icon/bar = icon('icons/effects/effects.dmi', "nothing")
	bar.Scale(FNF_BAR_WIDTH, FNF_BAR_HEIGHT)

	// Dark border
	bar.DrawBox("#111111", 1, 1, FNF_BAR_WIDTH, FNF_BAR_HEIGHT)

	var/inner_w = FNF_BAR_WIDTH - 4                       // 92 px of usable fill
	var/red_w   = round((100 - health_pct) * inner_w / 100)
	red_w = clamp(red_w, 0, inner_w)

	// Red — enemy side, LEFT
	if(red_w > 0)
		bar.DrawBox("#dd2222", 2, 2, red_w + 1, FNF_BAR_HEIGHT - 1)

	// Green — player side, RIGHT
	if(red_w < inner_w)
		bar.DrawBox("#22dd55", red_w + 2, 2, FNF_BAR_WIDTH - 1, FNF_BAR_HEIGHT - 1)

	// White divider at the split point
	var/div_x = clamp(red_w + 1, 2, FNF_BAR_WIDTH - 2)
	bar.DrawBox("#ffffff", div_x, 1, div_x + 2, FNF_BAR_HEIGHT)

	return bar

/datum/fnf_minigame/proc/update_health(delta)
	if(!is_player_side)
		return
	health_pct = clamp(health_pct + delta, 0, 100)
	if(hud_bar_img && battle_active)
		hud_bar_img.icon = make_health_bar_icon()
	// Switch portrait states based on who is losing
	if(hud_pl_head_img)
		hud_pl_head_img.icon_state = (health_pct < 20) ? "losing" : "normal"
	if(hud_en_head_img)
		hud_en_head_img.icon_state = (health_pct > 80) ? "losing" : "normal"

/datum/fnf_minigame/proc/report_health_event(hit)
	var/delta = hit ? FNF_HEALTH_STEP : -FNF_HEALTH_STEP
	if(is_player_side)
		update_health(delta)
	else if(linked_game)
		linked_game.update_health(-delta)

// ── Arrow HUD ──────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/generate_visuals()
	// left / down / up / right — match FNF's LDUR lane order
	var/static/list/arrow_order = list("west", "south", "north", "east")
	var/x_offset = -24
	for(var/dir_name in arrow_order)
		var/obj/effect/overlay/fnf_arrow/slot = new
		slot.icon       = 'icons/effects/riding_minigame.dmi'
		slot.icon_state = "blank_arrow"
		slot.setDir(text2dir(dir_name))
		slot.pixel_x    = x_offset
		slot.pixel_y    = FNF_SLOT_Y     // well above the mob's head
		slot.layer      = ABOVE_ALL_MOB_LAYER
		minigame_holder.vis_contents += slot
		cached_arrows[dir_name] = list("visual_object" = slot, "active_queue" = list())
		x_offset += 16

// ── Note scheduling ────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/schedule_notes()
	for(var/list/note in chart_notes)
		var/spawn_delay = max(0, note["t"] / 100 - FNF_SCROLL_ADVANCE)
		addtimer(CALLBACK(src, PROC_REF(spawn_note_visual), note), spawn_delay, TIMER_DELETE_ME)

	// Only the master game controls the song end — slave (enemy) game must not set its own timer.
	// song_end_ticks is set by the microphone from the combined max of both charts.
	if(is_player_side && song_end_ticks > 0)
		song_end_timer = addtimer(CALLBACK(src, PROC_REF(on_song_end)), song_end_ticks, TIMER_STOPPABLE|TIMER_DELETE_ME)

/datum/fnf_minigame/proc/spawn_note_visual(list/note)
	if(!battle_active || QDELETED(src))
		return

	var/fnf_dir   = note["d"] % 4
	var/static/list/dir_map = list("0" = "west", "1" = "south", "2" = "north", "3" = "east")
	var/byond_dir = dir_map["[fnf_dir]"]

	var/obj/effect/overlay/fnf_arrow/arrow = new
	arrow.icon       = 'icons/effects/riding_minigame.dmi'
	arrow.icon_state = "[byond_dir]_arrow"
	arrow.alpha      = 0
	arrow.layer      = ABOVE_ALL_MOB_LAYER + 0.1
	arrow.pixel_x    = arrow_x_for(fnf_dir)
	arrow.pixel_y    = FNF_ARROW_SPAWN_Y
	minigame_holder.vis_contents += arrow

	animate(arrow, alpha = 255, time = 1)
	animate(arrow, pixel_y = FNF_SLOT_Y, time = 1.5 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(activate_arrow), arrow, byond_dir), 1 SECONDS, TIMER_DELETE_ME)

/datum/fnf_minigame/proc/arrow_x_for(fnf_dir)
	switch(fnf_dir)
		if(0) return -24
		if(1) return -8
		if(2) return 8
		if(3) return 24
	return 0

/datum/fnf_minigame/proc/activate_arrow(obj/effect/overlay/fnf_arrow/arrow, direction)
	if(QDELETED(arrow) || !battle_active)
		if(!QDELETED(arrow)) qdel(arrow)
		return
	cached_arrows[direction]["active_queue"] += arrow
	addtimer(CALLBACK(src, PROC_REF(deactivate_arrow), arrow, direction), 0.8 SECONDS, TIMER_DELETE_ME)

/datum/fnf_minigame/proc/deactivate_arrow(obj/effect/overlay/fnf_arrow/arrow, direction)
	if(QDELETED(arrow))
		return
	cached_arrows[direction]["active_queue"] -= arrow
	animate(arrow, alpha = 0, time = 0.5)
	QDEL_IN(arrow, 0.5 SECONDS)

// ── Movement blocking ──────────────────────────────────────────────────────

/datum/fnf_minigame/proc/block_player_move(atom/movable/source, atom/new_loc)
	SIGNAL_HANDLER
	if(!battle_active)
		return NONE
	return COMPONENT_MOVABLE_BLOCK_PRE_MOVE

// ── Input ──────────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/on_player_move(atom/movable/source, atom/new_loc, direction)
	SIGNAL_HANDLER
	. = NONE

	if(!battle_active)
		return

	var/dir_key = dir2text(direction)
	var/list/arrow_data = cached_arrows[dir_key]
	if(!arrow_data)
		return

	var/list/queue = arrow_data["active_queue"]
	if(length(queue))
		// ── HIT ──
		var/obj/effect/overlay/fnf_arrow/hit_arrow = queue[1]
		queue.Remove(hit_arrow)
		if(!QDELETED(hit_arrow))
			qdel(hit_arrow)
		var/obj/effect/overlay/fnf_arrow/slot = arrow_data["visual_object"]
		if(!QDELETED(slot))
			flick("blank_arrow_win", slot)
		var/static/list/dir_to_fnf = list("west" = 0, "south" = 1, "north" = 2, "east" = 3)
		play_dance_pose(dir_to_fnf[dir_key])
		report_health_event(TRUE)
		return

	// ── MISS ──
	for(var/adir in cached_arrows)
		var/obj/effect/overlay/fnf_arrow/slot = cached_arrows[adir]["visual_object"]
		if(!QDELETED(slot))
			flick("blank_arrow_lose", slot)
	report_health_event(FALSE)

// ── Dance poses ────────────────────────────────────────────────────────────

/datum/fnf_minigame/proc/play_dance_pose(fnf_direction)
	var/mob/living/carbon/human/dancer = player_ref?.resolve()
	if(!istype(dancer))
		return

	var/pose
	if(is_player_side)
		var/static/list/pm = list("0" = "fnf_player_left", "1" = "fnf_player_down", "2" = "fnf_player_up", "3" = "fnf_player_right")
		pose = pm["[fnf_direction]"]
	else
		// Regular dances for the opponent — left=disco, down=floss, up=robot, right=bow
		var/static/list/em = list("0" = "disco", "1" = "floss", "2" = "robot", "3" = "bow")
		pose = em["[fnf_direction]"]

	// Player FNF poses live in emote_animations; opponent dances live in all_dances_by_name.
	var/datum/humanoid_animation/anim = GLOB.emote_animations[pose] || GLOB.all_dances_by_name[pose]
	if(!anim)
		return
	// Enemy dance animations are played slightly faster (0.75×) so they feel snappy on note hits.
	dancer.start_animation(is_player_side ? anim : make_fast_animation(anim))

/**
 * Return a copy of an animation with all keyframe times scaled by speed_factor.
 * Pose datums are shared (not deep-copied) since only timing is modified.
 */
/datum/fnf_minigame/proc/make_fast_animation(datum/humanoid_animation/source, speed_factor = 0.75)
	var/datum/humanoid_animation/fast = new
	fast.name      = source.name
	fast.keyframes = list()
	for(var/datum/animation_keyframe/kf in source.keyframes)
		var/datum/animation_keyframe/kf2 = new
		kf2.time     = max(1, round(kf.time * speed_factor))
		kf2.animate  = kf.animate
		kf2.head_dir = kf.head_dir
		kf2.body_dir = kf.body_dir
		kf2.legs_dir = kf.legs_dir
		kf2.head  = kf.head
		kf2.body  = kf.body
		kf2.arm_l = kf.arm_l
		kf2.arm_r = kf.arm_r
		kf2.leg_l = kf.leg_l
		kf2.leg_r = kf.leg_r
		fast.keyframes += kf2
	return fast

// ── Song end / forfeit ─────────────────────────────────────────────────────

/datum/fnf_minigame/proc/on_song_end()
	song_end_timer = null
	var/mob/living/player = player_ref?.resolve()
	if(player)
		to_chat(player, span_boldnotice("The battle is over!"))
	qdel(src)

/datum/fnf_minigame/proc/lose_minigame()
	var/mob/living/player = player_ref?.resolve()
	if(player)
		to_chat(player, span_userdanger("You left the battle!"))
	qdel(src)

// ── Cleanup ────────────────────────────────────────────────────────────────

/datum/fnf_minigame/Destroy()
	battle_active = FALSE

	if(linked_game)
		linked_game.linked_game = null
		QDEL_NULL(linked_game)

	if(song_end_timer)
		deltimer(song_end_timer)
		song_end_timer = null

	QDEL_NULL(stage_obj)

	var/mob/living/player = player_ref?.resolve()
	var/mob/living/opp    = opponent_ref?.resolve()

	stop_music_for(player)
	stop_music_for(opp)

	for(var/mob/living/target in list(player, opp))
		if(!target?.client) continue
		target.client.images -= hud_bar_img
		target.client.images -= hud_pl_head_img
		target.client.images -= hud_en_head_img

	hud_bar_img     = null
	hud_pl_head_img = null
	hud_en_head_img = null

	if(player)
		player.client?.images -= minigame_holder
		UnregisterSignal(player, list(
			COMSIG_MOVABLE_ATTEMPTED_MOVE,
			COMSIG_MOVABLE_PRE_MOVE,
			COMSIG_QDELETING,
		))

	player_ref      = null
	opponent_ref    = null
	cached_arrows   = null
	minigame_holder = null
	chart_notes     = null
	return ..()

#undef FNF_SCROLL_ADVANCE
#undef FNF_BAR_WIDTH
#undef FNF_BAR_HEIGHT
#undef FNF_HEAD_SIZE
#undef FNF_HUD_Y
#undef FNF_HEALTH_STEP
#undef FNF_SLOT_Y
#undef FNF_ARROW_SPAWN_Y

// ── Types ──────────────────────────────────────────────────────────────────

/obj/effect/overlay/fnf_arrow

/obj/effect/fnf_stage
	name          = "battle stage"
	desc          = "An ephemeral stage for a rhythm battle."
	icon          = 'icons/effects/effects.dmi'
	icon_state    = "nothing"
	anchored      = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
