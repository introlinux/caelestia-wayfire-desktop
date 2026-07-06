#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float aspect;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 center = vec2(0.5, 0.5);
    vec2 distVec = (uv - center);
    distVec.x *= aspect;
    float dist = length(distVec);
    
    // Max distance to cover the screen from center
    float maxDist = length(vec2(0.5 * aspect, 0.5));
    
    // Smooth step for a clean edge
    float smoothing = 0.02;
    float radius = progress * (maxDist + smoothing);
    float alpha = 1.0 - smoothstep(radius - smoothing, radius, dist);
    
    fragColor = texture(source, qt_TexCoord0) * alpha * qt_Opacity;
}
