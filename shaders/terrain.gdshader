shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform float detail_scale : hint_range(0.05, 2.0) = 0.35;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 fog_tint : source_color = vec3(1.0);

varying vec3 world_pos;
varying vec3 vcol;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR.rgb;
}

void fragment() {
	float n = vnoise(world_pos.xz * detail_scale) * 0.6 + vnoise(world_pos.xz * detail_scale * 4.1) * 0.4;
	float d = 1.0 + (n - 0.5) * 2.0 * detail_strength;
	ALBEDO = vcol * d * fog_tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
