shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec3 color : source_color = vec3(0.7, 0.9, 1.0);
uniform float alpha = 0.45;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 1.5);
	ALBEDO = color;
	EMISSION = color * (0.3 + fres * 0.8);
	ALPHA = clamp(alpha + fres * 0.4 + 0.08 * sin(TIME * 3.0), 0.0, 1.0);
	ROUGHNESS = 0.3;
}
