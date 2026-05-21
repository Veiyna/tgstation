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
	appearance.transform = matrix().Scale(0.6, 0.6)
	// pixel_y positive = UP. Hands are at the bottom of the sprite, so negative Y.
	// Left hand extends to the LEFT of center (negative X), right hand to the RIGHT (positive X).
	// Thumb is on the inner side (toward body), pinky on the outer side.
	var/hand_center = (side == "l") ? -20 : 20
	var/hand_y = -14
	// Fan: thumb (inner, smaller offset) to pinky (outer, larger offset)
	var/fan_offset = (side == "l") ? (3 - finger_position) : (finger_position - 3)
	appearance.pixel_x = hand_center + fan_offset * 2
	appearance.pixel_y = hand_y
	return appearance

/datum/bodypart_overlay/simple/finger/color_image(image/overlay, layer, obj/item/bodypart/limb)
	overlay.color = limb?.draw_color || COLOR_WHITE

/datum/bodypart_overlay/simple/finger/can_draw_on_bodypart(obj/item/bodypart/limb)
	. = ..()
	if(. && istype(limb) && limb.bodypart_disabled)
		return FALSE
