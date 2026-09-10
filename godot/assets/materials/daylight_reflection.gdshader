shader_type sky;

void sky() {
    vec3 daylight = mix(vec3(0.34, 0.37, 0.28), vec3(0.60, 0.70, 0.80), smoothstep(-0.1, 0.8, EYEDIR.y));
    // A broad room window reflected by the polished wood finish.
    float opening = exp(-pow((EYEDIR.x+0.25)/0.30, 2.0)-pow((EYEDIR.z+0.55)/0.25, 2.0));
    COLOR = daylight*0.35 + vec3(0.64, 0.62, 0.58)*opening*smoothstep(0.3, 0.7, EYEDIR.y);
}
