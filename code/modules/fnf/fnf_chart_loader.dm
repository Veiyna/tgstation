/// FNF chart parser — loads .json chart files and converts to note queues

/// List of available FNF songs  (display name => song_dir)
GLOBAL_LIST_INIT(fnf_songs, list(
	"Bopeebo"           = "bopeebo",
	"Fresh"             = "fresh",
	"Dad Battle"        = "dadbattle",
	"Spookeez"          = "spookeez",
	"South"             = "south",
	"Monster"           = "monster",
	"Pico"              = "pico",
	"Philly Nice"       = "philly-nice",
	"Blammed"           = "blammed",
	"Satin Panties"     = "satin-panties",
	"High"              = "high",
	"Milf"              = "milf",
	"Cocoa"             = "cocoa",
	"Eggnog"            = "eggnog",
	"Winter Horrorland" = "winter-horrorland",
	"Senpai"            = "senpai",
	"Roses"             = "roses",
	"Thorns"            = "thorns",
	"Ugh"               = "ugh",
	"Guns"              = "guns",
	"Stress"            = "stress",
	"Chiller"           = "chiller",
))

/**
 * Strip variant suffixes from FNF character IDs so they match voice file names.
 * FNF metadata uses variant IDs like "bf-car", "mom-car", "bf-christmas", "parents-christmas".
 * The actual voice OGG files are named after the base character: Voices-bf, Voices-mom, Voices-parents.
 * We strip everything from the first hyphen onward.
 * Examples: "bf-car" → "bf", "mom-car" → "mom", "parents-christmas" → "parents", "dad" → "dad".
 */
/proc/fnf_normalize_vocal_char(char_id)
	var/hyphen = findtext(char_id, "-")
	if(hyphen)
		return copytext(char_id, 1, hyphen)
	return char_id

/// Human-readable display name for a normalised voice character id.
/proc/fnf_voice_label(voice_id)
	switch(voice_id)
		if("bf")      return "BF"
		if("dad")     return "Dad"
		if("mom")     return "Mom"
		if("pico")    return "Pico"
		if("spooky")  return "Skid & Pump"
		if("darnell") return "Darnell"
		if("monster") return "Monster"
		if("senpai")  return "Senpai"
		if("spirit")  return "Spirit"
		if("tankman") return "Tankman"
		if("parents") return "Mom & Dad"
	return uppertext(copytext(voice_id, 1, 2)) + copytext(voice_id, 2)

/// Load an FNF chart from a song directory.
/// Returns: list("player" = player_notes, "enemy" = enemy_notes, "all" = all_notes)
/// Each note is list("d" = direction 0-3, "t" = time_ms).
/proc/load_fnf_chart(song_dir, difficulty = "hard")
	var/chart_path = "data/fnf/songs/[song_dir]/[song_dir]-chart.json"

	var/list/chart_json
	try
		chart_json = json_decode(file2text(chart_path))
	catch
		CRASH("Failed to load FNF chart: [chart_path]")

	var/list/player_notes = list()
	var/list/enemy_notes  = list()
	var/list/all_notes    = list()
	var/list/raw_notes    = list()

	if(chart_json["notes"])
		if(chart_json["notes"][difficulty])
			raw_notes = chart_json["notes"][difficulty]
		else if(chart_json["notes"]["normal"])
			raw_notes = chart_json["notes"]["normal"]
		else if(chart_json["notes"]["easy"])
			raw_notes = chart_json["notes"]["easy"]

	for(var/list/note in raw_notes)
		var/direction = note["d"]
		var/note_data = list("d" = direction % 4, "t" = note["t"])
		all_notes += list(note_data)
		if(direction <= 3)
			player_notes += list(note_data)
		else
			enemy_notes  += list(note_data)

	sortTim(player_notes, GLOBAL_PROC_REF(cmp_note_time))
	sortTim(enemy_notes,  GLOBAL_PROC_REF(cmp_note_time))
	sortTim(all_notes,    GLOBAL_PROC_REF(cmp_note_time))

	return list("player" = player_notes, "enemy" = enemy_notes, "all" = all_notes)

/proc/cmp_note_time(list/a, list/b)
	return a["t"] - b["t"]

/// Get song metadata: list("songName", "bpm", "artist").
/proc/get_fnf_metadata(song_dir)
	var/metadata_path = "data/fnf/songs/[song_dir]/[song_dir]-metadata.json"
	var/list/metadata
	try
		metadata = json_decode(file2text(metadata_path))
	catch
		return list("songName" = song_dir, "bpm" = 100, "artist" = "Unknown")

	var/bpm = 100
	if(length(metadata["timeChanges"]))
		bpm = metadata["timeChanges"][1]["bpm"]

	return list(
		"songName" = metadata["songName"] || song_dir,
		"bpm"      = bpm,
		"artist"   = metadata["artist"]   || "Unknown",
	)

/**
 * Return available voice characters for a song.
 * Returns: list("player_voices" = list(...), "opponent_voice" = "...")
 *
 * Character IDs are normalised (variant suffixes stripped) and then checked via
 * fexists() — only chars with actual OGG files on disk are offered.
 * "player_voices" always contains at least "bf" as a fallback.
 */
/proc/get_fnf_voices(song_dir)
	var/metadata_path = "data/fnf/songs/[song_dir]/[song_dir]-metadata.json"
	var/list/metadata
	try
		metadata = json_decode(file2text(metadata_path))
	catch
		return list("player_voices" = list("bf"), "opponent_voice" = "")

	var/list/player_voices = list()
	var/opponent_voice     = ""

	var/list/play_data = metadata["playData"]
	if(play_data)
		var/list/chars = play_data["characters"]
		if(chars)
			var/list/opp_vocals = chars["opponentVocals"]
			if(length(opp_vocals))
				opponent_voice = fnf_normalize_vocal_char("[opp_vocals[1]]")
			var/list/pl_vocals = chars["playerVocals"]
			if(length(pl_vocals))
				for(var/v in pl_vocals)
					player_voices |= fnf_normalize_vocal_char("[v]")

		// "pico" variation means pico is also playable
		var/list/variations = play_data["songVariations"]
		if(length(variations))
			for(var/variant in variations)
				if("[variant]" == "pico")
					player_voices |= "pico"

	if(!length(player_voices))
		player_voices += "bf"

	// Filter to chars with real audio files
	var/list/available_player = list()
	for(var/v in player_voices)
		if(fexists("sound/fnf/[song_dir]/Voices-[v].ogg"))
			available_player += v

	if(!fexists("sound/fnf/[song_dir]/Voices-[opponent_voice].ogg"))
		opponent_voice = ""

	if(!length(available_player))
		available_player += "bf"

	return list("player_voices" = available_player, "opponent_voice" = opponent_voice)
