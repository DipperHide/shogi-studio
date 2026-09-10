shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec2 footprint = vec2(1.0);
uniform vec2 quad_size = vec2(2.0);
uniform float softness = 0.06;
uniform float opacity = 0.32;
uniform bool pentagon = true;
uniform bool clip_to_tabletop = false;
uniform vec4 table_layout = vec4(4.8,5.3,6.5,3.55);
uniform vec2 tray_half_size = vec2(1.7,1.75);
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
    vec2 edge = b-a;
    return length(p-a-edge*clamp(dot(p-a,edge)/dot(edge,edge),0.0,1.0));
}
void fragment() {
    if (clip_to_tabletop) {
        vec2 location = world_position.xz;
        bool on_board = all(lessThanEqual(abs(location),table_layout.xy));
        bool on_tray = all(lessThanEqual(abs(location-table_layout.zw),tray_half_size)) || all(lessThanEqual(abs(location+table_layout.zw),tray_half_size));
        if (!on_board && !on_tray) discard;
    }
    vec2 p = (UV-0.5)*quad_size;
    float distance;
    if (pentagon) {
        vec2 a = vec2(-0.5,0.5)*footprint;
        vec2 b = vec2(0.5,0.5)*footprint;
        vec2 c = vec2(0.43,-0.30)*footprint;
        vec2 d = vec2(0.0,-0.5)*footprint;
        vec2 e = vec2(-0.43,-0.30)*footprint;
        distance = min(min(segment_distance(p,a,b),segment_distance(p,b,c)),min(segment_distance(p,c,d),min(segment_distance(p,d,e),segment_distance(p,e,a))));
        float side_limit = p.y < -footprint.y*0.30 ? (p.y/footprint.y+0.5)*2.15*footprint.x : (0.45625+0.0875*p.y/footprint.y)*footprint.x;
        bool inside = p.y >= -footprint.y*0.5 && p.y <= footprint.y*0.5 && abs(p.x)<=side_limit;
        if (inside) distance = -distance;
    } else {
        vec2 q = abs(p)-footprint*0.5;
        distance = length(max(q,0.0))+min(max(q.x,q.y),0.0);
    }
    ALBEDO = vec3(0.095,0.068,0.039);
    ALPHA = opacity*(1.0-smoothstep(-softness,softness*2.0,distance));
}
