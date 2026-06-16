shader_type spatial;
render_mode specular_disabled;

// The jungle short-grass ground. A flat plane on its own reads as a dead slab, so this
// breaks the surface into flat patches of two grass greens with a toon-quantised value
// noise — reading as clumped short grass from the close follow-camera — and bands the key
// light into the same flat tones the units wear (cel.gdshader), so a unit and the ground
// it stands on share one lighting treatment. World-space, so the pattern tiles evenly
// across the whole arena regardless of where the plane sits.

// The two grass tones the patches blend between — a deep shade green and a brighter one.
uniform vec3 grass_low : source_color = vec3(0.13, 0.30, 0.12);
uniform vec3 grass_high : source_color = vec3(0.22, 0.45, 0.18);

// How tight the grass clumps are: the broad-patch frequency and the finer speckle on top,
// per world unit, and how many flat steps the blend is quantised into for the toon look.
uniform float patch_scale = 0.004;
uniform float speckle_scale = 0.02;
uniform float patch_steps = 4.0;

// The two light levels the key light steps through — the same three-tone ramp the units
// wear, so the ground tone sits in the same family as the bodies on it.
const float MID_TONE = 0.5;
const float LOW_CUT = 0.25;
const float HIGH_CUT = 0.6;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smoothed value noise in [0, 1] — bilinear blend of four lattice hashes, the building
// block the grass dapple is layered from.
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
	float broad = value_noise(world_pos.xz * patch_scale);
	float fine = value_noise(world_pos.xz * speckle_scale);
	float t = clamp(broad * 0.7 + fine * 0.3, 0.0, 1.0);
	t = floor(t * patch_steps) / (patch_steps - 1.0);
	ALBEDO = mix(grass_low, grass_high, t);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

// Bands the key light into three flat tones, the shadow side left to the ambient fill —
// the same step the units take, so the field lights as one surface.
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float tone = step(LOW_CUT, ndl) * MID_TONE + step(HIGH_CUT, ndl) * (1.0 - MID_TONE);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
