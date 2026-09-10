shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D wood_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ink_texture : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_ink = false;
uniform float saturation = 1.0;
uniform float lightness = 1.0;
uniform float surface_roughness = 0.32;
uniform float finish_coat = 0.24;
uniform float texture_strength = 1.0;
uniform vec3 base_tone : source_color = vec3(0.44,0.46,0.39);
uniform vec2 uv_scale = vec2(1.0);
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec3 wood = texture(wood_texture, UV * uv_scale).rgb;
    float luminance = dot(wood, vec3(0.2126,0.7152,0.0722));
    wood = mix(vec3(luminance), wood, saturation) * lightness;
    ALBEDO = mix(base_tone, wood, texture_strength);
    ROUGHNESS = clamp(surface_roughness + (luminance-0.5)*0.025, 0.18, 1.0);
    SPECULAR = 0.45;
    CLEARCOAT = finish_coat;
    CLEARCOAT_ROUGHNESS = 0.30;
	float ink = has_ink ? texture(ink_texture,UV).r : 0.0;
	ROUGHNESS = mix(ROUGHNESS,0.28,ink);
	CLEARCOAT = mix(CLEARCOAT,0.22,ink);
	SPECULAR = mix(SPECULAR,0.30,ink);
    // Soft finite window reflection in the finish, separate from the scanned
    // base color. Low energy preserves both grain and lacquered letter edges.
    vec2 window_offset = (world_position.xz-vec2(-1.8,-0.7))/vec2(3.2,4.8);
    float window = exp(-dot(window_offset,window_offset));
    float facing = smoothstep(0.72,0.99,dot(NORMAL,VIEW));
    EMISSION = vec3(0.024,0.026,0.028)*window*facing*(1.0-0.9*ink)*finish_coat/0.24;
}
