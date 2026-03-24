#version 460

layout(set = 2, binding = 0) uniform sampler2D tex_sampler;

layout(location = 0) in vec4 in_color;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = texture(tex_sampler, in_uv) * in_color;
}
