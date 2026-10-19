// Survey terrain printed on paper (style v4 "Signal", poster look; src/ui/v4/survey/survey_map.gd).
// The slab's top is paper with its relief printed as a screen-space halftone (dots grow where the
// light falls away, like a two-colour print), fine contour lines in ink and the rivers in solid
// signal red. The cut sides are solid ink with thin paper strata lines (printed in reverse).
// Unshaded: the light is a uniform direction, the shading is the print. Colours are source_color
// (linear in the 3D buffer; the SubViewport keeps linear values for the HDR canvas).
// Weather: cloud shadows drift over the relief (the dots grow under them) and mist lies in the low
// ground (the dots thin out, the contours fade), both cut from one seamless noise; the floodplain
// hatch creeps along. `flow` 0 holds all of it still (Reduce motion).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 paper : source_color = vec4(0.914, 0.910, 0.886, 1.0);
uniform vec4 ink : source_color = vec4(0.063, 0.067, 0.075, 1.0);
// The halftone ink (black, or signal red for the Infernal chapters).
uniform vec4 dot_ink : source_color = vec4(0.063, 0.067, 0.075, 1.0);
uniform vec4 river : source_color = vec4(1.0, 0.294, 0.122, 1.0);
uniform vec4 side_ink : source_color = vec4(0.078, 0.082, 0.09, 1.0);
uniform vec3 light_dir = vec3(-0.7, 0.55, 0.45);
// Shading: tone = ambient + diffuse; bias darkens (Fallen) or lightens (Celestial) the print.
uniform float ambient = 0.32;
uniform float bias = 0.0;
uniform float gain = 1.0;
// Halftone cell in viewport px, screen angle (radians).
uniform float cell = 5.0;
uniform float angle = 0.785;
uniform float levels = 12.0;
uniform float contour_a = 0.5;
// River half-width as a fraction of the river field (RIVER_REACH units), and the floodplain band.
uniform float river_w = 0.075;
uniform float plain_w = 0.22;
uniform float base_y = -0.9;
uniform float top_y = 1.5;
// Seamless noise for the weather; strengths of the cloud shadows and the valley mist (0 = none).
uniform sampler2D cloud_tex : filter_linear, repeat_enable;
uniform float clouds = 0.0;
uniform float mist = 0.0;
// Cloud drift (noise texture units per second) and the time scale (0 = still).
uniform vec2 wind = vec2(0.014, 0.006);
uniform float flow = 1.0;

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hair(float d, float fw, float px) {
	fw = max(fw, 1e-5);
	return 1.0 - smoothstep(px * 0.5 * fw - 0.5 * fw, px * 0.5 * fw + 0.5 * fw, abs(d));
}

void fragment() {
	vec3 col;
	if (UV2.y < -0.5) {
		// Cut side: solid ink, paper strata lines, a lighter band near the top edge.
		col = side_ink.rgb;
		float s = world_p.y * 9.0;
		float strata = hair(fract(s + 0.5) - 0.5, fwidth(s), 0.8) * 0.35;
		float seam = hair(world_p.y - (base_y + 0.06), fwidth(world_p.y), 1.2) * 0.6;
		col = mix(col, paper.rgb, max(strata, seam));
	} else {
		vec3 n = normalize(world_n);
		float diff = max(dot(n, normalize(light_dir)), 0.0);
		float tone = clamp((ambient + diff * (1.0 - ambient)) * gain + bias, 0.0, 1.0);
		// Cavity from the mesh (COLOR.r 0.5 = flat): valleys print a little darker.
		tone = clamp(tone - (COLOR.r - 0.5) * 0.9, 0.0, 1.0);
		// Weather: drifting cloud shadows darken the print, mist in the low ground lightens it.
		float tt = TIME * flow;
		float cn = texture(cloud_tex, world_p.xz / 8.5 + wind * tt).r;
		float shade = smoothstep(0.54, 0.76, cn) * clouds;
		float mn = texture(cloud_tex, world_p.xz / 3.8 - wind * tt * 1.7 + vec2(0.31, 0.67)).r;
		float low = 1.0 - smoothstep(0.04, 0.42, UV2.x);
		float fog = smoothstep(0.4, 0.8, mn) * low * mist;
		tone = clamp(tone - shade * 0.3 + fog * 0.5, 0.0, 1.0);
		// Screen-space halftone: dot radius grows with the darkness.
		vec2 sp = FRAGCOORD.xy;
		mat2 rot = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
		vec2 g = rot * sp / cell;
		float dist = length(fract(g) - 0.5);
		float r = sqrt(1.0 - tone) * 0.62;
		float aa = max(fwidth(dist), 0.001);
		float dotv = 1.0 - smoothstep(r - aa, r + aa, dist);
		col = mix(paper.rgb, dot_ink.rgb, dotv);
		// Contour lines (every 4th heavier).
		float h = UV2.x * levels;
		float fw = fwidth(h);
		float cl = hair(fract(h + 0.5) - 0.5, fw, 0.9);
		float major = hair(fract(h * 0.25 + 0.5) - 0.5, fw * 0.25, 1.4);
		col = mix(col, ink.rgb, max(cl * contour_a, major * contour_a * 1.3) * (1.0 - fog * 0.6));
		// Rivers: solid signal, a fine signal hatch over the floodplain (creeping slowly along).
		float rd = UV2.y;
		float plain = (1.0 - smoothstep(plain_w * 0.6, plain_w, rd)) * step(0.5, fract((sp.x + sp.y + tt * 3.0) / 4.0));
		col = mix(col, river.rgb, plain * 0.35);
		float rv = 1.0 - smoothstep(river_w - fwidth(rd), river_w + fwidth(rd), rd);
		col = mix(col, river.rgb, rv);
	}
	ALBEDO = col;
}
