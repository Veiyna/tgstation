/// Disgusting wriggly moth-arm fingers that poke out of every hand
/datum/bodypart_overlay/simple/finger
	icon = 'icons/mob/human/species/moth/bodyparts.dmi'
	layers = EXTERNAL_FRONT
	/// 1-5, spreads them in a fan
	var/finger_position = 1
	/// "l" or "r"
	var/side = "l"

/datum/bodypart_overlay/simple/finger/get_image(layer, obj/item/bodypart/limb)
	var/icon_state_name = (side == "l") ? "moth_l_arm" : "moth_r_arm"
	var/mutable_appearance/appearance = mutable_appearance(icon, icon_state_name, layer = layer)
	appearance.transform = matrix().Scale(0.5, 0.5)
	// Position at the hand area using the bodypart's artist-defined px_x/px_y as base
	var/hand_x = (side == "l") ? 2 : 22
	var/hand_y = 14
	// Fan spread: -3, -1.5, 0, 1.5, 3 pixels around the hand center
	var/fan_spread = (finger_position - 3) * 1.5
	appearance.pixel_x = hand_x + fan_spread
	appearance.pixel_y = hand_y
	return appearance

/datum/bodypart_overlay/simple/finger/color_image(image/overlay, layer, obj/item/bodypart/limb)
	overlay.color = limb?.draw_color || COLOR_WHITE

/datum/bodypart_overlay/simple/finger/can_draw_on_bodypart(obj/item/bodypart/limb)
	. = ..()
	if(. && istype(limb) && limb.bodypart_disabled)
		return FALSE
