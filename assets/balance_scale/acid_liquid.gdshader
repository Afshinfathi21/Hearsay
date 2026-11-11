shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 acid_color : source_color = vec4(0.72, 0.95, 0.22, 0.85);
uniform float emission_strength = 1.6;
uniform float pulse_speed = 2.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.9 + 0.1 * sin(TIME * pulse_speed + UV.x * 6.0);
	ALBEDO = acid_color.rgb;
	ALPHA = mix(acid_color.a, 1.0, fres);
	EMISSION = acid_color.rgb * emission_strength * pulse * (0.5 + fres);
	ROUGHNESS = 0.1;
}
