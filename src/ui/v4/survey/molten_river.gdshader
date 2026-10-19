// The stage route as a molten river on the survey map's terrain (style v4 "Signal", poster look;
// src/ui/v4/survey/survey_map.gd): a ribbon draped over the river bed, a white-hot core grading to
// signal orange at the banks, with slow streaks of brighter melt flowing downstream (a painted
// emissive gradient, no bloom). Past the furthest open stage (`reach`, distance along the river) the
// melt has cooled to a dark crust with a faint glow in its cracks; now and then a bright pulse runs
// down the open stretch to the current stage. UV.x is the distance along the river (world units),
// UV.y runs across it (0..1). Unshaded, opaque; colours are source_color (linear in the 3D buffer).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 warm : source_color = vec4(1.0, 0.294, 0.122, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform vec4 core_col : source_color = vec4(1.0, 0.96, 0.84, 1.0);
uniform vec4 crust : source_color = vec4(0.16, 0.08, 0.06, 1.0);
uniform sampler2D noise_tex : filter_linear, repeat_enable;
// Distance along the river where the open route ends (beyond it: cooled crust).
uniform float reach = 1000.0;
uniform float flow = 1.0;
uniform float speed = 0.22;
// The pulse: every `pulse_every` seconds it runs `pulse_run` seconds from `pulse_from` to reach.
uniform float pulse_from = 0.0;
uniform float pulse_every = 5.0;
uniform float pulse_run = 1.6;

void fragment() {
	float tt = TIME * flow;
	float across = abs(UV.y - 0.5) * 2.0;
	float n = texture(noise_tex, vec2(UV.x * 0.45 - tt * speed, UV.y * 0.35)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.3 - tt * speed * 1.7, UV.y * 0.6 + 0.37)).r;
	// Hot melt: core to bank.
	float core = 1.0 - smoothstep(0.0, 0.55 + n * 0.25, across);
	vec3 melt = mix(warm.rgb, hot.rgb, smoothstep(0.1, 0.8, core));
	melt = mix(melt, core_col.rgb, smoothstep(0.55, 1.0, core) * (0.6 + 0.4 * n2));
	melt *= 0.88 + 0.24 * smoothstep(0.45, 0.75, n2);
	// Cooled crust beyond the reach: dark plates, a faint glow in the cracks.
	float cool = smoothstep(reach - 0.05, reach + 0.6, UV.x);
	float crack = smoothstep(0.42, 0.5, n) * (1.0 - smoothstep(0.5, 0.58, n));
	vec3 crusted = mix(crust.rgb, warm.rgb * 0.75, crack * (1.0 - across) * 0.8);
	vec3 col = mix(melt, crusted, cool);
	// The pulse running down the open stretch.
	float pk = mod(tt, pulse_every) / pulse_run;
	if (flow > 0.0 && pk < 1.0 && reach > pulse_from) {
		float head = mix(pulse_from, reach, 1.0 - (1.0 - pk) * (1.0 - pk));
		float d = head - UV.x;
		float trail = step(0.0, d) * exp(-d * 2.2) * (1.0 - cool);
		col = mix(col, core_col.rgb, clamp(trail * (1.0 - across * 0.6), 0.0, 1.0) * 0.85);
	}
	ALBEDO = col;
}
