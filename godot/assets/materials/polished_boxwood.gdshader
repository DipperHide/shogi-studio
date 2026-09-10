shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wood_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ink_texture : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_ink = false;

void fragment() {
    vec3 wood = texture(wood_texture,UV).rgb;
    float ink = has_ink ? texture(ink_texture,UV).r : 0.0;
    // Lossless coverage provides the final lettering edge independently of
    // the imported color texture and its platform-specific compression.
    ALBEDO = mix(wood,vec3(0.008,0.006,0.004),ink);
    float grain = dot(wood,vec3(0.2126,0.7152,0.0722));
    ROUGHNESS = mix(clamp(0.32+(grain-0.4)*0.055,0.28,0.38),0.20,ink);
    SPECULAR = mix(0.42,0.48,ink);
    CLEARCOAT = mix(0.18,0.27,ink);
    CLEARCOAT_ROUGHNESS = mix(0.27,0.18,ink);
    // Sub-millimetre grain and raised lacquer, with screen-space filtering.
    // This changes only the normal, retaining sharp and fully readable ink.
    float height = mix(grain*0.00065,0.0011,ink);
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    vec3 r1 = cross(dy,NORMAL);
    vec3 r2 = cross(NORMAL,dx);
    float det = dot(dx,r1);
    vec3 gradient = sign(det)*(dFdx(height)*r1+dFdy(height)*r2);
    NORMAL = normalize(abs(det)*NORMAL-gradient);
}
