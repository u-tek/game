shader_type canvas_item;
// Holographic foil for the Legendary heroes (HeroSprite.holo; owner, 2026-10-20: "when the phone
// tilts the shader/character reacts like a real holo"). Draws the HaloRig warp mesh exactly like
// src/art/rig/warp.gdshader (same skinning, same tint) and lays a foil on her glossy materials only,
// so the foil follows the deforming art like a print on a trading card:
//   where: read from the painted texture itself. Highlights brighter than the texture on both sides
//     (latex, PVC and chrome streaks; not the edge of a bright area, not single hair strands) take
//     the most; the glossy or saturated material around them a faint sheen. Skin tones are rejected
//     (a warm-hue / saturation test on the pixel's neighbourhood), fine detail (hair strands, lace,
//     fur) and pale neutral surfaces (white hair, feathers) take little, the face is never touched
//     (an ellipse around it in rest space, face_ellipse) and hair and wings are kept low (per-bone
//     weights, bone_foil, weighted per vertex).
//   what: thin-film rainbow interference on the highlights, a faint rainbow sheen on the material,
//     a glare band that sweeps across her with the tilt and sparse star glitter that twinkles as she
//     tilts. The phase follows the phone's tilt (global ui_tilt) and drifts slowly with time. Gentle
//     at rest, vivid while tilting. motion = 0 (Reduce motion) holds a still, gentle foil.
// Maths in sRGB numbers: samples are taken to sRGB and the result back to the canvas with ui_linear
// (linear when HDR 2D is on). Nothing depends on bloom (HDR 2D is off on iOS).
// Cost: 6 texture reads (the art and 5 from its mipmaps), no loops; skipped where there is no foil.
// Tuning: main.gd --holo-debug=1 shows the masks, =2 what the foil adds; --tilt=x,y holds the tilt.
#include "res://src/art/rig/rig_tint.gdshaderinc"
#include "res://src/art/rig/warp_skin.gdshaderinc"

global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform float strength = 1.0;          // 0..1 master
uniform float motion = 1.0;            // 1: tilt and time move it; 0: Reduce motion (still, gentle)
uniform vec4 face_ellipse = vec4(0.0, -1050.0, 70.0, 60.0);   // rest rig space: centre xy, radii zw
uniform float bone_foil[32];           // per bone 0..1 (face 0, head and hair low), set by HeroSprite
uniform int debug_view = 0;            // 1: the masks (red highlights, green material, blue skin); 2: what the foil adds (x3)

varying float v_foil;

void vertex() {
	vec2 p = VERTEX;
	part_pos = p;
	VERTEX = warp_skin(p, CUSTOM0, CUSTOM1);
	float wb = max(0.0, 1.0 - CUSTOM0.y - CUSTOM0.w - CUSTOM1.y);
	v_foil = bone_foil[int(CUSTOM0.x + 0.5)] * CUSTOM0.y + bone_foil[int(CUSTOM0.z + 0.5)] * CUSTOM0.w
		+ bone_foil[int(CUSTOM1.x + 0.5)] * CUSTOM1.y + bone_foil[body_bone] * wb;
}

vec3 to_srgb(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
}

vec3 to_canvas(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Hash without sine (stable on mobile GPUs).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// How much an sRGB colour looks like skin: a warm red-orange hue, some but not latex-level
// saturation, not dark. Measured on the 42 Legendary looks (hue 0.0-0.07, saturation 0.12-0.62);
// gold lamé and blonde hair sit just yellower (hue 0.08 and up) and stay out.
float skin_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float d = mx - min(c.r, min(c.g, c.b));
	float s = d / max(mx, 0.0001);
	float dd = max(d, 0.00001);
	float h;
	if (mx == c.r) {
		h = mod((c.g - c.b) / dd, 6.0);
	} else if (mx == c.g) {
		h = (c.b - c.r) / dd + 2.0;
	} else {
		h = (c.r - c.g) / dd + 4.0;
	}
	float hd = abs(fract(h / 6.0 - 0.03 + 0.5) - 0.5);
	return (1.0 - smoothstep(0.035, 0.06, hd)) * smoothstep(0.05, 0.11, s) * (1.0 - smoothstep(0.62, 0.76, s))
		* smoothstep(0.15, 0.30, mx);
}

// A mip sample as (sRGB colour, how much of it is painted): transparent texels are black in the
// art, so the colour is un-premultiplied by the sample's coverage.
vec4 painted(vec4 s) {
	return vec4(to_srgb(s.rgb / max(s.a, 0.02)), smoothstep(0.05, 0.5, s.a));
}

void fragment() {
	vec4 o = halo_tint(texture(TEXTURE, UV), vec4(1.0));
	// No foil on the face, nor under the battle tints (they never meet: holo is off in battle).
	vec2 fq = (part_pos - face_ellipse.xy) / max(face_ellipse.zw * vec2(1.25, 1.35), vec2(1.0));
	float k = strength * v_foil * smoothstep(0.85, 1.25, length(fq))
		* (1.0 - clamp(max(max(flash, desat), max(shade, max(map_on, dissolve))), 0.0, 1.0));
	if (k > 0.002 && o.a > 0.004) {
		vec3 c = to_srgb(o.rgb);
		vec3 c1 = painted(textureLod(TEXTURE, UV, 2.0)).rgb;
		vec2 off = TEXTURE_PIXEL_SIZE * 12.0;
		vec4 nl = painted(textureLod(TEXTURE, UV - vec2(off.x, 0.0), 3.0));
		vec4 nr = painted(textureLod(TEXTURE, UV + vec2(off.x, 0.0), 3.0));
		vec4 nu = painted(textureLod(TEXTURE, UV - vec2(0.0, off.y), 3.0));
		vec4 nd = painted(textureLod(TEXTURE, UV + vec2(0.0, off.y), 3.0));
		float l0 = luma(c);
		float l1 = luma(c1);
		// Neighbours 12 texels away (8-texel blur); off the figure they count as the centre.
		float ll = mix(l1, luma(nl.rgb), nl.a);
		float lr = mix(l1, luma(nr.rgb), nr.a);
		float lu = mix(l1, luma(nu.rgb), nu.a);
		float ld = mix(l1, luma(nd.rgb), nd.a);
		vec3 cn = (nl.rgb * nl.a + nr.rgb * nr.a + nu.rgb * nu.a + nd.rgb * nd.a + c1 * 0.001)
			/ (nl.a + nr.a + nu.a + nd.a + 0.001);
		// A highlight: the 4-texel blur brighter than both neighbours along one axis.
		float two = max(l1 - max(ll, lr), l1 - max(lu, ld));
		float spec_m = smoothstep(0.05, 0.22, two) * smoothstep(0.30, 0.75, l0);
		// Glossy material: strong contrast around (highlights nearby) or a saturated colour.
		float gloss = smoothstep(0.04, 0.24, max(max(ll, lr), max(lu, ld)) - min(min(ll, lr), min(lu, ld)));
		// Skin: the neighbourhood's colour decides; the pixel's own only where it is not glossy
		// (a pale warm highlight on gold looks like skin, the gold around it does not).
		float skin = max(skin_of(cn), skin_of(c1) * (1.0 - gloss));
		float cmx = max(cn.r, max(cn.g, cn.b));
		float sn = (cmx - min(cn.r, min(cn.g, cn.b))) / max(cmx, 0.0001);
		float satm = smoothstep(0.45, 0.75, sn) * smoothstep(0.15, 0.35, cmx);
		// Fine detail (hair strands, lace, fishnet, fur) keeps out: only smooth surfaces take foil.
		float broad = 1.0 - smoothstep(0.03, 0.14, abs(l0 - l1));
		float keep = k * (1.0 - skin) * broad;
		float spec = spec_m * keep;
		// Pale neutral surfaces (white or silver hair, feathers, white cloth) take only their highlights:
		// next to dark latex or wings they would read as glossy, and a rainbow on them looks like a filter.
		float c0max = max(c.r, max(c.g, c.b));
		float pale = smoothstep(0.5, 0.78, l0) * (1.0 - smoothstep(0.1, 0.3, (c0max - min(c.r, min(c.g, c.b))) / max(c0max, 0.0001)));
		float region = max(satm, gloss * (1.0 - 0.75 * pale)) * keep;

		vec3 c_in = c;
		if (debug_view == 1) {
			c = vec3(spec, region, skin * k) + c * 0.15;
		} else {
			vec2 tl = ui_tilt * motion;
			float tm = TIME * motion;
			float amt = 0.3 + 0.7 * smoothstep(0.03, 0.35, length(tl));
			vec2 p = part_pos;
			// Thin-film colour: the phase runs across her, with her shading, and with the tilt.
			float ph = p.x * 0.0021 + p.y * 0.0034 + l0 * 0.9 + tl.x * 1.6 - tl.y * 1.1 + tm * 0.03;
			vec3 film = (0.5 + 0.5 * cos(6.28318 * (ph + vec3(0.0, 0.33, 0.67)))) * 0.85 + 0.15;
			// Highlights turn rainbow; the material around them takes a faint screen of the same film.
			c = mix(c, film * (0.6 + 0.55 * l0), spec * amt * 0.9);
			c = 1.0 - (1.0 - c) * (1.0 - film * (region * amt * 0.32 * (0.3 + l0)));
			// The glare band: a diagonal that crosses her as the phone tilts. In it the foil flashes:
			// highlights go white-hot, the material lights up in the film's colour (dark latex too).
			float u = (p.x * 0.62 - (p.y + 650.0) * 0.78) / 1300.0 + tl.x * 0.85 + tl.y * 0.6 - 0.15 * sin(tm * 0.25);
			float sw = exp(-(u / 0.13) * (u / 0.13)) * amt;
			c += sw * (0.6 * spec * (0.55 + 0.45 * film) + 0.6 * region * film);
			// Glitter: one possible star per 20-unit cell, three in ten lit, twinkling with tilt and time.
			vec2 g = floor(p / 20.0);
			float h1 = hash12(g);
			vec2 d = p - (g + 0.25 + 0.5 * vec2(hash12(g + 17.31), hash12(g + 41.73))) * 20.0;
			float star = exp(-length(d) / 3.2)
				+ 0.9 * (exp(-abs(d.x) / 1.4) * exp(-abs(d.y) / 8.0) + exp(-abs(d.y) / 1.4) * exp(-abs(d.x) / 8.0));
			float tw = pow(max(0.0, sin(h1 * 80.0 + tl.x * 16.0 + tl.y * 12.0 + tm * 1.3)), 10.0);
			float gm = clamp(region * 2.0 + spec * 2.0 + keep * 0.8 * (1.0 - pale), 0.0, 1.0);
			c += step(0.7, h1) * min(star, 1.0) * tw * gm * (0.2 + 0.8 * amt) * 3.0 * (0.65 + 0.35 * film);
		}
		if (debug_view == 2) {
			c = abs(c - c_in) * 3.0;
		}
		// Kept in 0..1: on the HDR canvas anything brighter would bloom on desktop and not on iOS.
		o.rgb = to_canvas(clamp(c, vec3(0.0), vec3(1.0)));
	}
	COLOR = o * COLOR;
}
