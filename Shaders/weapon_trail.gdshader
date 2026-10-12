// Weapon trail ribbon (WeaponTrail): a translucent wake with a jagged,
// glowing outer edge and crawling lightning streaks. UV.x is the age (0 at
// the blade now, 1 where the trail ends); UV.y runs from the blade base (0)
// to its tip (1). The edge and streak colors are multiplied by glow_energy
// so they bloom under the level's glow, while the core stays dark.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Seamless noise that shapes the ragged edges and the streaks.
uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
// The wake between the edges; its alpha is how opaque the wake is.
uniform vec4 core_color : source_color = vec4(0.14, 0.02, 0.28, 0.82);
// The glowing rim along the blade tip's path and the trail's newest end.
uniform vec4 edge_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
// The crawling lightning streaks inside the wake.
uniform vec4 streak_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
// HDR multiplier on the edge and streak colors (above 1 blooms).
uniform float glow_energy = 3.5;
// How deep the rim reaches into the wake, as a fraction of its width.
uniform float edge_width : hint_range(0.0, 1.0) = 0.3;
// How fast the noise crawls along the trail.
uniform float crawl_speed = 5.0;
// How many noise features fit along the trail.
uniform float noise_scale = 2.5;
// How thick the lightning streaks are.
uniform float streak_width : hint_range(0.0, 0.25) = 0.05;

void fragment() {
	float age = UV.x;
	float span = UV.y;
	vec2 crawl = vec2(age * noise_scale - TIME * crawl_speed, span * noise_scale * 0.6);
	float n = texture(noise_texture, crawl).r;
	float m = texture(noise_texture, crawl * 1.7 + vec2(0.31, TIME * 0.9)).r;
	float jag = (n - 0.5) * 0.4;
	float tip_rim = smoothstep(1.0 - edge_width, 1.0, span + jag);
	float fresh_rim = 1.0 - smoothstep(0.0, edge_width * 0.6, age + jag * 0.5);
	float rim = max(tip_rim, fresh_rim);
	float streak = (1.0 - smoothstep(0.0, streak_width, abs(m - 0.5))) * smoothstep(0.3, 0.6, span);
	vec3 color = mix(core_color.rgb, edge_color.rgb * glow_energy, rim);
	color = mix(color, streak_color.rgb * glow_energy * 1.5, streak * (1.0 - age));
	float body = mix(core_color.a, 1.0, max(rim, streak));
	// Fades as it ages, with a ragged end, and thins toward the hilt.
	float fade = 1.0 - smoothstep(0.45, 1.0, age + (n - 0.5) * 0.5);
	ALBEDO = color;
	ALPHA = clamp(body * fade * smoothstep(0.0, 0.2, span), 0.0, 1.0);
}
