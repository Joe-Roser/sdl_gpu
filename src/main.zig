const std = @import("std");
const zul = @import("zul");
const zalg = @import("zalg");
const obj = @import("obj.zig");
pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
});

const Logger = zul.monitoring.Logger;
const Vec2 = zalg.Vec2;
const Vec3 = zalg.Vec3;
const Vec4 = zalg.Vec4;
const Mat4 = zalg.Mat4;

const vert_shader: []const u8 = @embedFile("shaders/out/shader.vert.spv");
const frag_shader: []const u8 = @embedFile("shaders/out/shader.frag.spv");

const obj_path = "assets/sedan-sports.obj";

const UBO = struct {
    mvp: Mat4,
};

const VertexData = struct { position: Vec3, color: Vec4, uv: Vec2 };

const WHITE: Vec4 = .fromSlice(&.{ 1, 1, 1, 1 });

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

fn load_shader(gpu: *c.SDL_GPUDevice, code: []const u8, stage: c.SDL_GPUShaderStage, num_uniform_buffers: u32, num_samplers: u32) !*c.SDL_GPUShader {
    const create_info: c.SDL_GPUShaderCreateInfo = .{
        .code_size = code.len,
        .code = code.ptr,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = stage,
        .num_uniform_buffers = num_uniform_buffers,
        .num_samplers = num_samplers,
    };
    return c.SDL_CreateGPUShader(gpu, &create_info) orelse error.CreateShaderFailed;
}

// main
//
//
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

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

    const pipeline = pipeline: {
        // Create Shaders
        const vertex_shader = try load_shader(gpu, vert_shader, c.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0);
        const fragment_shader = try load_shader(gpu, frag_shader, c.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 1);
        defer c.SDL_ReleaseGPUShader(gpu, vertex_shader);
        defer c.SDL_ReleaseGPUShader(gpu, fragment_shader);

        try log.info("Shaders loaded", .{});

        // Desrcibe the vertex buffers
        const vertex_buf_descriptions = &[_]c.SDL_GPUVertexBufferDescription{
            .{
                .slot = 0,
                .pitch = @sizeOf(VertexData),
            },
        };
        // Define what the vertex info for this pipelie looks like
        const vertex_attrs = &[_]c.SDL_GPUVertexAttribute{
            .{
                .location = 0,
                .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .offset = @offsetOf(VertexData, "position"), // Using the fields from the input struct
            },
            .{
                .location = 1,
                .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                .offset = @offsetOf(VertexData, "color"),
            },
            .{
                .location = 2,
                .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = @offsetOf(VertexData, "uv"),
            },
        };

        // Create Shader Pipeline
        const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .target_info = .{
                .num_color_targets = 1,
                .color_target_descriptions = &.{ .format = c.SDL_GetGPUSwapchainTextureFormat(gpu, window) },
                .has_depth_stencil_target = true,
                .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
            },
            .vertex_input_state = .{
                .num_vertex_buffers = vertex_buf_descriptions.len,
                .vertex_buffer_descriptions = vertex_buf_descriptions,
                .num_vertex_attributes = vertex_attrs.len,
                .vertex_attributes = vertex_attrs,
            },
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = true,
                .compare_op = c.SDL_GPU_COMPAREOP_LESS,
            },
        };
        break :pipeline c.SDL_CreateGPUGraphicsPipeline(gpu, &pipeline_info) orelse return error.CreatePipelineFailed;
    };

    // Setting up the projection matrix
    var window_w: i32 = undefined;
    var window_h: i32 = undefined;
    try check_err(
        c.SDL_GetWindowSize(window, &window_w, &window_h),
    );
    const x: f32 = @floatFromInt(window_w);
    const y: f32 = @floatFromInt(window_h);
    const proj_mat = Mat4.perspective(70, x / y, 0.0001, 1000);
    const trans_mat = Mat4.fromTranslate(.fromSlice(&.{ 0, -1, -3 }));

    const rotation_speed = 90;
    var rotation: f32 = 0.0; // In Degrees

    // Making the object model
    const car_obj = try obj.Obj.from_file(alloc, obj_path);

    var vertecies = try alloc.alloc(VertexData, car_obj.faces.len);
    defer alloc.free(vertecies);
    var indicies = try alloc.alloc(u16, car_obj.faces.len);
    defer alloc.free(indicies);

    for (car_obj.faces, 0..) |face, i| {
        const uv = car_obj.uvs[face.uv];
        vertecies[i] = .{
            .position = car_obj.positions[face.pos],
            .color = WHITE,
            .uv = .fromSlice(&.{ uv.x(), 1 - uv.y() }),
        };
        indicies[i] = @intCast(i);
    }

    car_obj.deinit();

    // Creating vertex buffer and index buffer
    const vertex_buffer_size: u32 = @intCast(vertecies.len * @sizeOf(VertexData));
    const vertex_buffer = c.SDL_CreateGPUBuffer(gpu, &.{
        .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = vertex_buffer_size,
    }) orelse return error.CreateVBufFailed;
    const index_buffer_size: u32 = @intCast(indicies.len * @sizeOf(u16));
    const index_buffer = c.SDL_CreateGPUBuffer(gpu, &.{
        .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = index_buffer_size,
    }) orelse return error.CreateIBufFailed;

    var cobble_w: i32 = 0;
    var cobble_h: i32 = 0;
    var cobble_texture: *c.SDL_GPUTexture = undefined;
    defer c.SDL_ReleaseGPUTexture(gpu, cobble_texture);

    var depth_texture: *c.SDL_GPUTexture = undefined;
    defer c.SDL_ReleaseGPUTexture(gpu, depth_texture);
    {
        const buffer_size = index_buffer_size + vertex_buffer_size;
        // Upload data to VBuf
        // - Create Transfer Buf
        const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu, &.{
            .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = buffer_size,
        }) orelse return error.CreateTBufFailed;
        defer c.SDL_ReleaseGPUTransferBuffer(gpu, transfer_buffer);

        // - Map buffer to memory
        const transfer_mem: [*]u8 = @ptrCast(
            c.SDL_MapGPUTransferBuffer(gpu, transfer_buffer, false) orelse return error.MapTBufFailed,
        );

        // - Copy
        const vertex_bytes = std.mem.sliceAsBytes(vertecies);
        std.mem.copyForwards(u8, transfer_mem[0..vertex_bytes.len], vertex_bytes);
        const index_bytes = std.mem.sliceAsBytes(indicies);
        std.mem.copyForwards(u8, transfer_mem[vertex_bytes.len..buffer_size], index_bytes);
        c.SDL_UnmapGPUTransferBuffer(gpu, transfer_buffer);

        // - Begin Copy Pass
        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(gpu) orelse return error.GetCmdBufFailed;
        const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buf) orelse return error.StartCopyPassFailed;

        // - Invoke Upload Command
        c.SDL_UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = transfer_buffer,
            .offset = 0,
        }, &.{
            .buffer = vertex_buffer,
            .offset = 0,
            .size = vertex_buffer_size,
        }, false);
        c.SDL_UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = transfer_buffer,
            .offset = vertex_buffer_size,
        }, &.{
            .buffer = index_buffer,
            .offset = 0,
            .size = index_buffer_size,
        }, false);

        cobble_texture = c.IMG_LoadGPUTexture(gpu, copy_pass, "assets/colormap.png", &cobble_w, &cobble_h) orelse return error.LoadTextureFailed;

        depth_texture = c.SDL_CreateGPUTexture(gpu, &.{
            .format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
            .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            .width = @intCast(window_w),
            .height = @intCast(window_h),
            .layer_count_or_depth = 1,
            .num_levels = 1,
        }) orelse return error.DepthTextureFail;

        // - End Copy Pass and Submit
        c.SDL_EndGPUCopyPass(copy_pass);
        try check_err(
            c.SDL_SubmitGPUCommandBuffer(cmd_buf),
        );
    }
    try log.info("Primed GPU buffers", .{});

    const sampler = c.SDL_CreateGPUSampler(gpu, &.{}) orelse return error.CreateSamplerFailed;

    try log.info("Setup complete", .{});
    try log.flush();

    // Main Loop
    try log.info("Starting main loop", .{});
    var last_ticks = c.SDL_GetTicks();
    mainloop: while (true) {
        const this_ticks = c.SDL_GetTicks();
        const dt = @as(f32, @floatFromInt(this_ticks - last_ticks)) / 1000;
        last_ticks = this_ticks;

        // Process Events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :mainloop,
                else => continue,
            }
        }

        rotation += dt * rotation_speed;

        const model_mat = trans_mat.mul(
            Mat4.fromRotation(rotation, .fromSlice(&[_]f32{ 0, 1, 0 })),
        );
        const ubo: UBO = .{
            .mvp = proj_mat.mul(
                model_mat,
            ),
        };

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
            .clear_color = .{ .r = 0, .g = 0.2, .b = 0.4, .a = 1 },
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const depth_target_info: c.SDL_GPUDepthStencilTargetInfo = .{
            .texture = depth_texture,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .clear_depth = 1,
        };
        const render_pass = c.SDL_BeginGPURenderPass(cmd_buf, &colour_target_info, 1, &depth_target_info);

        // - Draw Stuff
        // - - Bind Pipeline
        c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

        // - - Bind Vertex Data
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &.{
            .offset = 0,
            .buffer = vertex_buffer,
        }, 1);

        // Bind the texture sampler
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &.{
            .texture = cobble_texture,
            .sampler = sampler,
        }, 1);

        // Bind Index Buffer
        c.SDL_BindGPUIndexBuffer(render_pass, &.{
            .offset = 0,
            .buffer = index_buffer,
        }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        // - - Bind Uniform Data
        c.SDL_PushGPUVertexUniformData(cmd_buf, 0, &ubo, @sizeOf(UBO));

        // - - Draw Calls
        c.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(indicies.len), 1, 0, 0, 0);

        // - End Render Pass
        c.SDL_EndGPURenderPass(render_pass);

        // - Repeat Render Passes

        // - Submit Command Buffer
        try check_err(
            c.SDL_SubmitGPUCommandBuffer(cmd_buf),
        );
        try log.flush();
    }
}

test "recurse" {
    std.testing.refAllDecls(@This());
}
