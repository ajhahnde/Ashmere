shader_type spatial;
render_mode specular_disabled, cull_disabled;

// The river surface — a stylised toon water in place of the flat blue strip. A slow broad
// tone varies the deep channel; crisp highlight bands drift along the current (TIME) so it
// reads as flowing water; the banks lighten to a shallow tone and then fray irregularly into
// the grass. Cel-banded like every other surface. Driven per river ribbon by MapView, which
// passes the ribbon's half-width so the bank shaping works in object space.
//
// The flow bands ride a world-space diagonal (x - z) — the axis the river runs along — so the
// pattern is continuous across the separate ribbon segments (no seams at the joins) and scrolls
// roughly along the watercourse.

// Deep channel, mid surface, the bright crest the drifting bands lift to, and the lighter
// shallow tone the water fades to at its banks.
uniform vec3 water_deep : source_color = vec3(0.04, 0.14, 0.32);
uniform vec3 water_mid : source_color = vec3(0.09, 0.27, 0.48);
uniform vec3 water_crest : source_color = vec3(0.34, 0.60, 0.78);
uniform vec3 water_shallow : source_color = vec3(0.28, 0.52, 0.58);

// Broad tone clump size, and the drifting flow bands: their spacing (frequency), scroll speed,
// where along the wave the crest cuts in, and how far the crest lifts toward `water_crest`.
uniform float tone_scale = 0.004;
uniform float wave_freq = 0.013;
uniform float wave_speed = 2.2;
uniform float wave_cut : hint_range(0.0, 1.0) = 0.62;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.5;

// Bank shaping (across the ribbon, 0 centre … 1 edge from UV.x): where the shallow lightening
// begins, where the fray begins, and the noise that breaks the bank up.
uniform float shallow_start : hint_range(0.0, 1.0) = 0.5;
uniform float fray_start : hint_range(0.0, 1.0) = 0.82;
uniform float fray_scale = 0.012;
uniform float fray_jitter : hint_range(0.0, 1.0) = 0.4;

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
	float edge = clamp(abs(UV.x - 0.5) * 2.0, 0.0, 1.0); // 0 centre … 1 bank, from the ribbon UV
	// Fray the banks into the grass, the same noise cut the dirt path takes.
	float bite = (value_noise(world_pos.xz * fray_scale) - 0.5) * fray_jitter;
	if (edge > fray_start && edge - fray_start + bite > 0.0) {
		discard;
	}
	// Broad slow tone across the channel, then crisp highlight bands drifting along the flow.
	float tone = value_noise(world_pos.xz * tone_scale);
	vec3 surface = mix(water_deep, water_mid, tone);
	float wave = sin((world_pos.x - world_pos.z) * wave_freq - TIME * wave_speed) * 0.5 + 0.5;
	float crest = smoothstep(wave_cut, wave_cut + 0.08, wave);
	surface = mix(surface, water_crest, crest * wave_strength);
	float shallow = smoothstep(shallow_start, 1.0, edge);
	ALBEDO = mix(surface, water_shallow, shallow);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float toon = step(LOW_CUT, ndl) * MID_TONE + step(HIGH_CUT, ndl) * (1.0 - MID_TONE);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * toon;
}
