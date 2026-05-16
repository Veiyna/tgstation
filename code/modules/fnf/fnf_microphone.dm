/// FNF Microphone — used to start rhythm battles between two players

/obj/item/fnf_microphone
	name = "battle microphone"
	desc = "A sleek microphone used for rhythm battles. When two players face off, only one can keep the beat."
	icon = 'icons/obj/device.dmi'
	icon_state = "forensic1"
	inhand_icon_state = "forensic1"
	w_class = WEIGHT_CLASS_SMALL

	var/in_battle = FALSE

	var/challenge_song_dir
	var/list/challenge_notes
	var/list/challenge_enemy_notes
	var/list/challenge_metadata
	var/datum/weakref/challenger_ref

// ── Self-use: pick a song and arm the mic ─────────────────────────────────

/obj/item/fnf_microphone/attack_self(mob/user)
	. = ..()
	if(in_battle)
		balloon_alert(user, "already in a battle!")
		return
	if(challenge_notes)
		clear_challenge()
	choose_song(user)

/obj/item/fnf_microphone/proc/choose_song(mob/user)
	var/list/choices = list()
	for(var/name in GLOB.fnf_songs)
		choices[name] = GLOB.fnf_songs[name]

	var/chosen_name = tgui_input_list(user, "Pick a song", "FNF Battle", sort_list(choices))
	if(!chosen_name)
		return

	challenge_song_dir = choices[chosen_name]

	var/list/all_charts = load_fnf_chart(challenge_song_dir, "hard")
	if(!length(all_charts["player"]))
		balloon_alert(user, "chart loading failed!")
		challenge_song_dir = null
		return

	challenge_notes       = all_charts["player"]
	challenge_enemy_notes = all_charts["enemy"]
	challenge_metadata    = get_fnf_metadata(challenge_song_dir)
	challenger_ref        = WEAKREF(user)

	var/song_display = challenge_metadata["songName"]
	to_chat(user, span_notice("You ready the microphone: [song_display]. Face another player and click them to challenge!"))
	user.visible_message(span_notice("[user] brandishes a microphone, looking for a challenger!"))

// ── Clear challenge state ─────────────────────────────────────────────────

/obj/item/fnf_microphone/proc/clear_challenge()
	challenger_ref        = null
	challenge_song_dir    = null
	challenge_notes       = null
	challenge_enemy_notes = null
	challenge_metadata    = null

// ── Start the battle ──────────────────────────────────────────────────────

/obj/item/fnf_microphone/proc/start_battle(mob/living/challenger, mob/living/opponent)
	if(in_battle)
		return FALSE
	in_battle = TRUE

	var/list/player_notes = challenge_notes
	var/list/enemy_notes  = challenge_enemy_notes
	var/list/meta         = challenge_metadata
	var/song_name         = meta["songName"]
	var/bpm               = meta["bpm"]
	var/song_dir          = challenge_song_dir

	clear_challenge()

	// Compute combined song end from the max last-note time across both charts,
	// then add a 30-second buffer so the song always plays to completion.
	var/combined_last_t = 0
	if(length(player_notes))
		combined_last_t = max(combined_last_t, player_notes[length(player_notes)]["t"])
	if(length(enemy_notes))
		combined_last_t = max(combined_last_t, enemy_notes[length(enemy_notes)]["t"])
	var/end_ticks = combined_last_t / 100 + 50    // ticks: last note + 5 s buffer

	challenger.visible_message(span_boldnotice("[challenger] challenges [opponent] to a rhythm battle!"))

	var/datum/fnf_minigame/player_game = new(challenger, opponent, player_notes, song_dir, bpm)
	player_game.is_player_side = TRUE
	player_game.song_name      = song_name
	player_game.song_end_ticks = end_ticks

	var/datum/fnf_minigame/enemy_game = new(opponent, challenger, enemy_notes, song_dir, bpm)
	enemy_game.is_player_side = FALSE
	enemy_game.song_name      = song_name
	// enemy_game.song_end_ticks intentionally left 0 — only master fires the timer

	player_game.linked_game = enemy_game
	enemy_game.linked_game  = player_game

	player_game.begin(TRUE)
	enemy_game.begin(FALSE)

	RegisterSignal(player_game, COMSIG_QDELETING, PROC_REF(on_battle_end))
	return TRUE

/obj/item/fnf_microphone/proc/on_battle_end(datum/source)
	SIGNAL_HANDLER
	in_battle = FALSE

// ── Click on another player to trigger the challenge ─────────────────────

/obj/item/fnf_microphone/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		return
	if(!isliving(target) || target == user)
		return
	if(isnull(challenge_notes))
		return
	start_battle(user, target)
