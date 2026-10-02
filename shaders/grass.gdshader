shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 base_color : source_color = vec3(0.2, 0.45, 0.12);
uniform vec3 tip_color : source_color = vec3(0.55, 0.75, 0.25);
uniform float sway = 0.25;

varying float vh;

void vertex() {
	vh = UV.y;
	float t = TIME * 1.4;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(t + wp.x * 0.7 + wp.z * 0.5) * sway * (1.0 - UV.y);
	VERTEX.x += s;
	VERTEX.z += s * 0.4;
}

void fragment() {
	vec3 c = mix(tip_color, base_color, vh) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
