const std = @import("std");
const zul = @import("zul");
pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const Logger = zul.monitoring.Logger;

const vert_shader: []const u8 = @embedFile("shaders/out/shader.vert.spv");
const frag_shader: []const u8 = @embedFile("shaders/out/shader.frag.spv");

// Helper function to check all SDL errors
fn check_err(b: bool) !void {
    if (b) return;
    std.log.err("SDL: {s}\r\n", .{c.SDL_GetError()});
    return error.SDL_Error;
}

// Wrapping the logger to allow SDL to use it instead
fn wrapped_log(userdata: ?*anyopaque, category: c_int, priority: c.SDL_LogPriority, msg: [*c]const u8) callconv(.c) void {
    const level = switch (priority) {
        c.SDL_LOG_PRIORITY_CRITICAL => "critical",
        c.SDL_LOG_PRIORITY_ERROR => "error",
        c.SDL_LOG_PRIORITY_WARN => "warn",
        c.SDL_LOG_PRIORITY_DEBUG => "debug",
        c.SDL_LOG_PRIORITY_INFO => "info",
        c.SDL_LOG_PRIORITY_INVALID => "invalid",
        c.SDL_LOG_PRIORITY_TRACE => "trace",
        c.SDL_LOG_PRIORITY_VERBOSE => "verbose",
        c.SDL_LOG_PRIORITY_COUNT => "count",
        else => unreachable,
    };
    const cat = switch (category) {
        c.SDL_LOG_CATEGORY_APPLICATION => "application",
        c.SDL_LOG_CATEGORY_ERROR => "error",
        c.SDL_LOG_CATEGORY_ASSERT => "assert",
        c.SDL_LOG_CATEGORY_SYSTEM => "system",
        c.SDL_LOG_CATEGORY_AUDIO => "audio",
        c.SDL_LOG_CATEGORY_VIDEO => "video",
        c.SDL_LOG_CATEGORY_RENDER => "render",
        c.SDL_LOG_CATEGORY_INPUT => "input",
        c.SDL_LOG_CATEGORY_TEST => "test",
        c.SDL_LOG_CATEGORY_GPU => "GPU",
        c.SDL_LOG_CATEGORY_CUSTOM => "custom",
        else => unreachable,
    };

    var log: *Logger = @ptrCast(@alignCast(userdata));
    log.plain("[SDL: {s}] {s}: {s}", .{ cat, level, msg }) catch std.debug.print("Logger failed", .{});
}

fn load_shader(gpu: *c.SDL_GPUDevice, code: []const u8, stage: c.SDL_GPUShaderStage) !*c.SDL_GPUShader {
    const vert_create_info: c.SDL_GPUShaderCreateInfo = .{
        .code_size = code.len,
        .code = code.ptr,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = stage,
    };
    return c.SDL_CreateGPUShader(gpu, &vert_create_info) orelse error.CreateShaderFailed;
}

// main
//
//
pub fn main() !void {
    // Setting up logging
    var stdout: std.fs.File = .stdout();
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = stdout.writer(&stdout_buf);

    var log: Logger = .init(&stdout_writer.interface);
    defer log.flush() catch {};

    // Giving logging to SDL
    c.SDL_SetLogPriorities(c.SDL_LOG_PRIORITY_VERBOSE);
    c.SDL_SetLogOutputFunction(&wrapped_log, &log);

    // Initialising SDL
    try check_err(
        c.SDL_Init(c.SDL_INIT_VIDEO),
    );
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("SDL GPU", 1200, 700, 0) orelse return error.CreateWindowFailed;

    const gpu = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse return error.CreateGPUFailed;
    try check_err(
        c.SDL_ClaimWindowForGPUDevice(gpu, window),
    );
    try log.info("Window and GPU setup", .{});

    try log.info("Setup complete", .{});
    try log.flush();

    const pipeline = pipeline: {
        // Create Shaders
        const vertex_shader = try load_shader(gpu, vert_shader, c.SDL_GPU_SHADERSTAGE_VERTEX);
        const fragment_shader = try load_shader(gpu, frag_shader, c.SDL_GPU_SHADERSTAGE_FRAGMENT);
        defer c.SDL_ReleaseGPUShader(gpu, vertex_shader);
        defer c.SDL_ReleaseGPUShader(gpu, fragment_shader);

        try log.info("Shaders loaded", .{});

        // Create Shader Pipeline
        const colour_target_description: [1]c.SDL_GPUColorTargetDescription = .{
            .{ .format = c.SDL_GetGPUSwapchainTextureFormat(gpu, window) },
        };
        const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .target_info = .{
                .num_color_targets = 1,
                .color_target_descriptions = &colour_target_description,
            },
        };
        break :pipeline c.SDL_CreateGPUGraphicsPipeline(gpu, &pipeline_info) orelse return error.CreatePipelineFailed;
    };

    try log.info("Starting main loop", .{});

    mainloop: while (true) {
        // Process Events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :mainloop,
                else => continue,
            }
        }

        // Render
        // - Aquire Command Buffer
        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(gpu) orelse return error.AquireCmdBufFailed;

        // - Aquire Swapchain Texture
        var swp_texture: ?*c.SDL_GPUTexture = undefined;
        try check_err(
            c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swp_texture, 0, 0),
        );

        // - Begin Render Pass
        const colour_target_info: c.SDL_GPUColorTargetInfo = .{
            .texture = swp_texture,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .clear_color = .{ .r = 0, .g = 1, .b = 1, .a = 1 },
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &colour_target_info, 1, null);

        // - Draw Stuff
        // - - Bind Pipeline
        c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
        // - - Bind Vertex Data

        // - - Bind Uniform Data

        // - - Draw Calls
        c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);

        // - End Render Pass
        c.SDL_EndGPURenderPass(render_pass);

        // - Repeat Render Passes

        // - Submit Command Buffer
        try check_err(
            c.SDL_SubmitGPUCommandBuffer(cmd_buf),
        );
    }
}
