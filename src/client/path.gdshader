shader_type spatial;
render_mode specular_disabled, cull_disabled;

// The trampled dirt path a lane wears — worn earth beaten through the jungle grass rather
// than a flat tan strip. Two dirt tones are dappled into toon patches like the grass, and
// the path's long edges are frayed away with a noise cut so the border breaks into the
// grass irregularly instead of as a clean ruled line. Cel-banded to match every other
// surface. Driven per lane ribbon by MapView, which passes the ribbon's half-width.

// The two dirt tones the worn path dapples between — a dark damp earth and a lighter dust.
uniform vec3 dirt_low : source_color = vec3(0.20, 0.15, 0.10);
uniform vec3 dirt_high : source_color = vec3(0.40, 0.32, 0.20);

// Clump tightness of the dirt dapple (per world unit) and how many flat toon steps it bands
// into — the same treatment the grass takes, so path and grass read as one family.
uniform float patch_scale = 0.006;
uniform float patch_steps = 4.0;

// Edge fray: where across the ribbon (0 centre … 1 edge, read from UV.x) the fray starts, the
// noise frequency that breaks the border up, and how hard the noise bites into it.
uniform float fray_start : hint_range(0.0, 1.0) = 0.62;
uniform float fray_scale = 0.012;
uniform float fray_jitter : hint_range(0.0, 1.0) = 0.55;

// The toon light ramp shared with the units and the grass.
const float MID_TONE = 0.5;
const float LOW_CUT = 0.25;
const float HIGH_CUT = 0.6;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fray the long edges into the grass: past `fray_start` toward the edge, a noise cut eats
	// the border away irregularly, so the path dissolves into grass rather than ruling a clean
	// line. The centre stays solid. UV.x runs 0 (left) … 1 (right) across the ribbon.
	float edge = clamp(abs(UV.x - 0.5) * 2.0, 0.0, 1.0);
	float bite = (value_noise(world_pos.xz * fray_scale) - 0.5) * fray_jitter;
	if (edge - fray_start + bite > 0.0 && edge > fray_start) {
		discard;
	}
	float t = floor(value_noise(world_pos.xz * patch_scale) * patch_steps) / (patch_steps - 1.0);
	ALBEDO = mix(dirt_low, dirt_high, t);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float tone = step(LOW_CUT, ndl) * MID_TONE + step(HIGH_CUT, ndl) * (1.0 - MID_TONE);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
