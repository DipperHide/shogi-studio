shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D rush_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    // Fine parallel rush stems and shallow binding channels, at physical scale.
    vec2 uv = 1.0-abs(mod(world_position.zx/8.2+0.5, 2.0)-1.0);
    vec3 rush = mix(texture(rush_texture, uv, 1.1).rgb,texture(rush_texture, uv, 0.0).rgb,0.40);
    float luminance = dot(rush, vec3(0.2126,0.7152,0.0722));
    float daylight = mix(1.23,0.73,smoothstep(-12.0,12.0,world_position.x));
    vec3 straw = mix(vec3(0.44,0.42,0.345),vec3(0.49,0.393,0.238),smoothstep(-12.0,12.0,world_position.x));
    ALBEDO = (straw+(luminance-0.37)*0.28)*daylight;
    // Subtle surface relief reacts to the actual scene light and viewpoint.
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    vec3 r1 = cross(dy, NORMAL);
    vec3 r2 = cross(NORMAL, dx);
    float det = dot(dx, r1);
    vec3 gradient = sign(det)*(dFdx(luminance)*r1+dFdy(luminance)*r2);
    NORMAL = normalize(abs(det)*NORMAL-gradient*0.0015);
    ROUGHNESS = 0.94;
    SPECULAR = 0.20;
}
