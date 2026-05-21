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
	appearance.transform = matrix() * 0.3
	// Splay out in a horizontal fan: positions -4, -2, 0, 2, 4
	var/x_offset = (finger_position - 3) * 2
	appearance.pixel_x = (side == "l") ? x_offset : -x_offset
	appearance.pixel_y = -2
	return appearance

/datum/bodypart_overlay/simple/finger/color_image(image/overlay, layer, obj/item/bodypart/limb)
	overlay.color = limb?.draw_color || COLOR_WHITE

/datum/bodypart_overlay/simple/finger/can_draw_on_bodypart(obj/item/bodypart/limb)
	. = ..()
	if(. && istype(limb) && limb.bodypart_disabled)
		return FALSE
