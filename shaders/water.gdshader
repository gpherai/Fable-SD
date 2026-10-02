shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform vec3 shallow_color : source_color = vec3(0.25, 0.55, 0.6);
uniform vec3 deep_color : source_color = vec3(0.05, 0.2, 0.35);
uniform float alpha : hint_range(0.0, 1.0) = 0.78;
uniform float wave_scale = 0.35;
uniform float wave_speed = 0.6;
uniform float wave_height = 0.08;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * wave_scale + TIME * wave_speed) * cos(wpos.z * wave_scale * 1.3 + TIME * wave_speed * 0.8);
	VERTEX.y += w * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	float r1 = sin(wpos.x * 0.9 + wpos.z * 0.4 + t);
	float r2 = sin(wpos.z * 0.7 - wpos.x * 0.35 - t * 1.3);
	float r3 = sin((wpos.x + wpos.z) * 0.25 + t * 0.6);
	float ripple = 0.5 + (r1 + r2 + r3) / 6.0;
	vec3 col = mix(deep_color, shallow_color, ripple * 0.6 + 0.2);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.5);
	ALBEDO = col + fres * 0.25;
	ALPHA = clamp(alpha + fres * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	NORMAL_MAP = vec3(0.5 + 0.08 * sin(wpos.x * 3.0 + t * 2.0), 0.5 + 0.08 * cos(wpos.z * 2.7 - t * 1.7), 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	EMISSION = col * 0.03;
}
