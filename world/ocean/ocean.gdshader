shader_type spatial;
// Ocean surface. The wave maths mirrors systems/waves.gd exactly; keep them
// in sync. Parameters are pushed every frame by world/ocean/ocean.gd.
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

uniform vec4 wave_a;
uniform vec4 wave_b;
uniform vec4 wave_c;
uniform vec4 wave_d;
uniform float wave_time;
uniform float amp_scale = 1.0;
uniform vec3 fade_origin;
uniform float fade_start = 260.0;
uniform float fade_end = 420.0;

uniform vec3 deep_color : source_color = vec3(0.02, 0.11, 0.2);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.42, 0.46);
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.97);
uniform float shallow_depth = 7.0;
uniform float shore_foam_depth = 1.1;
uniform float crest_foam = 0.55;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying float v_crest;
varying vec3 v_world;

vec3 gerstner(vec4 w, vec2 p, float fade, inout vec3 tangent, inout vec3 binormal) {
	vec2 d = w.xy;
	float k = 6.2831853 / w.w;
	float c = sqrt(9.81 / k);
	float f = k * (dot(d, p) - c * wave_time);
	float s = w.z * amp_scale * fade;
	float a = s / k;
	float sf = sin(f);
	float cf = cos(f);
	tangent += vec3(-d.x * d.x * s * sf, d.x * s * cf, -d.x * d.y * s * sf);
	binormal += vec3(-d.x * d.y * s * sf, d.y * s * cf, -d.y * d.y * s * sf);
	return vec3(d.x * a * cf, a * sf, d.y * a * cf);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(wp.xz, fade_origin.xz));
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, 1.0);
	vec3 disp = gerstner(wave_a, wp.xz, fade, t, b);
	disp += gerstner(wave_b, wp.xz, fade, t, b);
	disp += gerstner(wave_c, wp.xz, fade, t, b);
	disp += gerstner(wave_d, wp.xz, fade, t, b);
	// The ocean mesh is only ever translated, so world and local offsets match.
	VERTEX += disp;
	NORMAL = normalize(cross(b, t));
	v_crest = disp.y / max(amp_scale, 0.001);
	v_world = wp + disp;
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 floor_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	floor_view.xyz /= floor_view.w;
	float water_depth = clamp(VERTEX.z - floor_view.z, 0.0, 200.0);

	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, shallow_depth, water_depth));

	float n = value_noise(v_world.xz * 0.9 + wave_time * 0.3);
	float shore = 1.0 - smoothstep(0.0, shore_foam_depth * (0.6 + n), water_depth);
	float crest = smoothstep(crest_foam, crest_foam + 0.35, v_crest + n * 0.3);
	float foam = clamp(shore + crest * 0.6, 0.0, 1.0);

	ALBEDO = mix(col, foam_color, foam);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.55, 0.97, smoothstep(0.0, 3.0, water_depth));
	ALPHA = max(ALPHA, foam);
}
