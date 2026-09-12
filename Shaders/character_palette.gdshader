shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Textures
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gradient_palettes[8] : source_color, filter_linear, repeat_disable;

// Settings
uniform int palette_mode : hint_range(0, 2) = 0; // 0 = ENEMY, 1 = PLAYER, 2 = GLOBAL_TINT_ONLY
uniform bool enable_palette = true;
uniform int gradient_mask = 0; // Bitmask for active columns 0..7 (computed from non-null gradients)
uniform vec4 global_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

vec4 sample_palette(int idx, float t) {
	switch (idx) {
		case 0: return texture(gradient_palettes[0], vec2(t, 0.5));
		case 1: return texture(gradient_palettes[1], vec2(t, 0.5));
		case 2: return texture(gradient_palettes[2], vec2(t, 0.5));
		case 3: return texture(gradient_palettes[3], vec2(t, 0.5));
		case 4: return texture(gradient_palettes[4], vec2(t, 0.5));
		case 5: return texture(gradient_palettes[5], vec2(t, 0.5));
		case 6: return texture(gradient_palettes[6], vec2(t, 0.5));
		case 7: return texture(gradient_palettes[7], vec2(t, 0.5));
		default: return vec4(1.0);
	}
}

void fragment() {
	vec4 base_color = texture(albedo_texture, UV);
	vec3 out_color = base_color.rgb;

	if (enable_palette) {
		int col_idx = int(floor(clamp(UV.x, 0.0, 0.999) * 8.0));

		if (palette_mode == 0) {
			// ENEMY MODE:
			// Top half (UV.y <= 0.5) contains the 8 gradient columns:
			// Col 0: Straps/joints, Col 1: Slate armor, Col 2: Cool grey armor,
			// Col 3: White rivets, Col 4: Blue, Col 5: Green, Col 6: Yellow, Col 7: Main body/tunic
			if (UV.y <= 0.5 && ((gradient_mask & (1 << col_idx)) != 0)) {
				float t = clamp(UV.y * 2.0, 0.0, 1.0);
				vec4 grad_col = sample_palette(col_idx, t);
				out_color = grad_col.rgb;
			}
			// Bottom half (UV.y > 0.5) preserves eyes, horns, and face details from base texture.
		} else if (palette_mode == 1) {
			// PLAYER MODE:
			// Bottom half:
			//   Cols 2 & 3: Main outfit (shirt / trousers) -> Gradient 7
			//   Cols 0 & 1: Trim / Torso accent -> Gradient 1
			//   Cols 4..7:  Boots & gloves -> Gradient 0
			// Top half:
			//   Cols 6 & 7: Belt / Leather holster -> Gradient 6
			// (Cols 0..5 in top half contain head, face, eyes, and mouth -> NEVER overwritten)
			if (UV.y > 0.5) {
				float t = clamp((UV.y - 0.5) * 2.0, 0.0, 1.0);
				if ((col_idx == 2 || col_idx == 3) && ((gradient_mask & (1 << 7)) != 0)) {
					out_color = sample_palette(7, t).rgb;
				} else if ((col_idx == 0 || col_idx == 1) && ((gradient_mask & (1 << 1)) != 0)) {
					out_color = sample_palette(1, t).rgb;
				} else if (col_idx >= 4 && ((gradient_mask & (1 << 0)) != 0)) {
					out_color = sample_palette(0, t).rgb;
				}
			} else {
				float t = clamp(UV.y * 2.0, 0.0, 1.0);
				if (col_idx >= 6 && ((gradient_mask & (1 << 6)) != 0)) {
					out_color = sample_palette(6, t).rgb;
				}
				// Head and face features in col_idx 0..5 are preserved from base_color
			}
		}
	}

	ALBEDO = out_color * global_tint.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
