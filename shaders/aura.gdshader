shader_type spatial;
render_mode blend_add, cull_back, depth_draw_never, unshaded;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.3);
uniform float intensity = 1.0;
uniform float pulse = 1.5;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.0);
	float p = 0.75 + 0.25 * sin(TIME * pulse);
	ALBEDO = color * fres * intensity * p;
	ALPHA = fres * 0.9;
}
