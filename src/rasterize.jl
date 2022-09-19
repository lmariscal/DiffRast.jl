using ImageCore
using StaticArrays

function rasterize(
    ctx::GL.Context, vertex::AbstractArray{Float32},
    index::AbstractArray{UInt32}; width::Integer = 512, height::Integer = 512
)
    if glfwWindowShouldClose(ctx.window) != GLFW_FALSE
        error("Window was closed before the rasterize function was called")
    end

    color0 = GL.Texture(width, height; internal_format=GL_RGBA32F, data_format=GL_RGBA, type = GL_FLOAT)
    color1 = GL.Texture(width, height; internal_format=GL_RGBA32F, data_format=GL_RGBA, type = GL_FLOAT)
    attachments = Dict(GL_COLOR_ATTACHMENT0 => color0, GL_COLOR_ATTACHMENT1 => color1)
    framebuffer = GL.Framebuffer(attachments)

    if !GL.is_complete(framebuffer)
        error("Failed to create framebuffer")
    end

    layout = GL.BufferLayout([
        GL.BufferElement(SVector{4, Float32}, "a_Position")
    ])
    vertex_buffer = GL.VertexBuffer(vertex, layout)
    index_buffer = GL.IndexBuffer(index)
    vertex_array = GL.VertexArray(index_buffer, vertex_buffer)

    # https://www.khronos.org/opengl/wiki/Vertex_Shader/Defined_Inputs
    vertex_shader_code = """
#version 330 core
#extension GL_ARB_shader_draw_parameters : enable
#extension GL_ARB_enhanced_layouts : enable
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) in vec4 position;

layout(location = 0) out Vertex {
    int drawID;
    int instanceID;
} OUT;

void main() {
    gl_Position = position;

    OUT.drawID = gl_DrawIDARB;
    OUT.instanceID = gl_BaseInstanceARB;
}
    """

    geometry_shader_code = """
#version 330 core
#extension GL_ARB_enhanced_layouts : enable

layout (triangles) in;
layout (triangle_strip, max_vertices = 3) out;

uniform vec2 half_resolution;

layout(location = 0) in Vertex {
    int drawID;
    int instanceID;
} IN[];

layout(location = 0) out Geometry {
    vec4 uvzw;
    vec4 baryDiff;
} OUT;

void main() {
    vec4 p0 = gl_in[0].gl_Position;
    vec4 p1 = gl_in[1].gl_Position;
    vec4 p2 = gl_in[2].gl_Position;

    vec2 e0 = p0.xy * p2.w - p2.xy * p0.w;
    vec2 e1 = p1.xy * p2.w - p2.xy * p1.w;
    float a = e0.x * e1.y - e0.y * e1.x;

    float eps = 1e-6f;
    float ca = (abs(a) >= eps) ? a : (a < 0.0f) ? -eps : eps;
    float ia = 1.0f / ca;

    vec2 ascl = ia * half_resolution;
    float dudx =  e1.y * ascl.x;
    float dudy = -e1.x * ascl.y;
    float dvdx = -e0.y * ascl.x;
    float dvdy =  e0.x * ascl.y;

    float duwdx = p2.w * dudx;
    float dvwdx = p2.w * dvdx;
    float duvdx = p0.w * dudx + p1.w * dvdx;
    float duwdy = p2.w * dudy;
    float dvwdy = p2.w * dvdy;
    float duvdy = p0.w * dudy + p1.w * dvdy;

    vec4 db0 = vec4(duvdx - dvwdx, duvdy - dvwdy, dvwdx, dvwdy);
    vec4 db1 = vec4(duwdx, duwdy, duvdx - duwdx, duvdy - duwdy);
    vec4 db2 = vec4(duwdx, duwdy, dvwdx, dvwdy);

    gl_Layer = IN[0].drawID;
    gl_PrimitiveID = gl_PrimitiveIDIn + IN[0].instanceID;
    gl_Position = p0;
    OUT.uvzw = vec4(1.0f, 0.0f, p0.z, p0.w);
    OUT.baryDiff = db0;
    EmitVertex();

    // Undefined after EmitVertex() is called
    gl_Layer = IN[0].drawID;
    gl_PrimitiveID = gl_PrimitiveIDIn + IN[0].instanceID;
    gl_Position = p1;
    OUT.uvzw = vec4(0.0f, 1.0f, p1.z, p1.w);
    OUT.baryDiff = db1;
    EmitVertex();

    // Undefined after EmitVertex() is called
    gl_Layer = IN[0].drawID;
    gl_PrimitiveID = gl_PrimitiveIDIn + IN[0].instanceID;
    gl_Position = p2;
    OUT.uvzw = vec4(0.0f, 0.0f, p2.z, p2.w);
    OUT.baryDiff = db2;
    EmitVertex();

    EndPrimitive();
}
    """

    fragment_shader_code = """
#version 330 core
#extension GL_ARB_enhanced_layouts : enable
#extension GL_ARB_separate_shader_objects : enable

out vec4 FragColor;

layout(location = 0) in Geometry {
    vec4 uvzw;
    vec4 baryDiff;
} IN;

layout(location = 0) out vec4 raster;
layout(location = 1) out vec4 baryDiff;

void main() {
    raster = IN.uvzw;
    raster.z = raster.z / raster.w;
    raster.w = float(gl_PrimitiveID + 1);

    baryDiff = IN.baryDiff * IN.uvzw.w;
}
    """

    shader_program = GL.ShaderProgram((
        GL.Shader(GL_VERTEX_SHADER, vertex_shader_code),
        GL.Shader(GL_GEOMETRY_SHADER, geometry_shader_code),
        GL.Shader(GL_FRAGMENT_SHADER, fragment_shader_code)
    ))

    GL.render_loop(ctx, destroy_context = false) do
        # Even though we are only going to render once, using a loop to properly handle system events.

        GL.bind(framebuffer)
        color_attachment = framebuffer.attachments[GL_COLOR_ATTACHMENT0]
        GL.set_viewport(color_attachment.width, color_attachment.height)
        GL.set_clear_color(0.0, 0.0, 0.0, 0.0)
        GL.clear()

        GL.bind(shader_program)
        GL.bind(vertex_array)
        GL.draw(vertex_array)
        GL.unbind(framebuffer)

        GL.set_viewport(ctx.width, ctx.height)
        glfwSwapBuffers(ctx.window)
        glfwPollEvents()

        glfwSetWindowShouldClose(ctx.window, true)
        true
    end

    raster = GL.get_data(framebuffer.attachments[GL_COLOR_ATTACHMENT0])

    GL.delete!(framebuffer)

    raster
end
