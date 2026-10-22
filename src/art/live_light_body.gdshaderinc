// Live Light's per-pixel part (see live_light.gdshaderinc), inside fragment(): updates `o`.
if (live_light > 0.5 && o.a > 0.02) {
	float ll_radii[4] = float[](4.0, 10.0, 22.0, 40.0);
	vec2 ll_g = vec2(0.0);
	float ll_dmin = 48.0;
	for (int ll_i = 0; ll_i < 8; ll_i++) {
		float ll_a = float(ll_i) * 0.7853982;
		vec2 ll_dir = vec2(cos(ll_a), sin(ll_a));
		float ll_d = 48.0;
		for (int ll_k = 0; ll_k < 4; ll_k++) {
			if (textureLod(TEXTURE, UV + ll_dir * ll_radii[ll_k] * TEXTURE_PIXEL_SIZE, 1.0).a < 0.5) {
				ll_d = ll_radii[ll_k];
				break;
			}
		}
		ll_g += ll_dir / ll_d;
		ll_dmin = min(ll_dmin, ll_d);
	}
	vec3 ll_n = normalize(vec3(ll_g * 5.0, 1.0));
	vec2 ll_q = TEXTURE_PIXEL_SIZE * 2.5;
	float ll_lx = ll_luma(ll_srgb(textureLod(TEXTURE, UV + vec2(ll_q.x, 0.0), 0.0).rgb)) - ll_luma(ll_srgb(textureLod(TEXTURE, UV - vec2(ll_q.x, 0.0), 0.0).rgb));
	float ll_ly = ll_luma(ll_srgb(textureLod(TEXTURE, UV + vec2(0.0, ll_q.y), 0.0).rgb)) - ll_luma(ll_srgb(textureLod(TEXTURE, UV - vec2(0.0, ll_q.y), 0.0).rgb));
	ll_n = normalize(ll_n + vec3(-ll_lx, -ll_ly, 0.0) * 1.8);
	vec4 ll_blur = textureLod(TEXTURE, UV, 3.0);
	float ll_lavg = ll_luma(ll_srgb(ll_blur.rgb / max(ll_blur.a, 0.02)));
	o.rgb = live_light_shade(o.rgb, ll_n, clamp(ll_dmin / 40.0, 0.0, 1.0), ll_lavg, part_pos);
}
