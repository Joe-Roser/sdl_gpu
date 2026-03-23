const std = @import("std");
const builtin = @import("builtin");
const zul = @import("zul");
const zalg = @import("zalg");
const obj_zig = @import("obj.zig");
pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
    @cInclude("stdlib.h");
});

const Logger = zul.monitoring.Logger;
const Vec2 = zalg.Vec2;
const Vec3 = zalg.Vec3;
const Vec4 = zalg.Vec4;
const Mat4 = zalg.Mat4;

const OBJ_PATH = "assets/sedan-sports.obj";
const TEX_PATH = "assets/colormap.png";
const vert_shader: []const u8 = @embedFile("shaders/out/shader.vert.spv");
const frag_shader: []const u8 = @embedFile("shaders/out/shader.frag.spv");

var keydown: [513]u1 = .{0} ** 513;
const Look = struct {
    yaw: f32,
    pitch: f32,
};
var look: Look = .{ .pitch = 0, .yaw = 0 };

const WHITE: Vec4 = .fromSlice(&.{ 1, 1, 1, 1 });
const DEPTH_FORMAT = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM;
const SPEED = 3;
const MOUSE_SENSITIVITY = 0.3;

const UBO = struct { mvp: Mat4 };
const VertexData = struct { position: Vec3, color: Vec4, uv: Vec2 };
const Window = struct {
    ptr: *c.SDL_Window,
    width: u32,
    height: u32,

    fn init() !Window {
        const width = 1200;
        const heigt = 700;

        return .{
            .ptr = c.SDL_CreateWindow("SDL GPU", 1200, 700, 0) orelse return error.CreateWindowFailed,
            .width = width,
            .height = heigt,
        };
    }
    fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(self.ptr);
    }
};
const Camera = struct {
    position: Vec3,
    target: Vec3,
};
// :appstate
const AppState = struct {
    window: Window,
    gpu: *c.SDL_GPUDevice,
    log: *Logger,
    sampler: *c.SDL_GPUSampler,

    camera: Camera,

    // :init
    fn init(log: *Logger) !AppState {
        // Giving logging to SDL
        c.SDL_SetLogPriorities(c.SDL_LOG_PRIORITY_VERBOSE);
        c.SDL_SetLogOutputFunction(&wrapped_log, log);

        // Initialising SDL
        try check_err(
            c.SDL_Init(c.SDL_INIT_VIDEO),
        );

        const window: Window = try .init();

        const gpu = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse return error.CreateGPUFailed;
        try check_err(
            c.SDL_ClaimWindowForGPUDevice(gpu, window.ptr),
        );
        try log.info("Window and GPU setup", .{});

        const sampler = c.SDL_CreateGPUSampler(gpu, &.{}) orelse return error.CreateSamplerFailed;

        // Causes weird bugs. Check out in future
        // try check_err(
        //     c.SDL_SetWindowRelativeMouseMode(window.ptr, true),
        // );

        return .{
            .window = window,
            .gpu = gpu,
            .log = log,
            .sampler = sampler,
            .camera = .{
                .position = .fromSlice(&.{ 0, 1, 3 }),
                .target = .fromSlice(&.{ 0, 1, 0 }),
            },
        };
    }

    fn deinit(self: *AppState) void {
        c.SDL_ReleaseGPUSampler(self.gpu, self.sampler);
        c.SDL_ReleaseWindowFromGPUDevice(self.gpu, self.window.ptr);
        c.SDL_DestroyGPUDevice(self.gpu);
        self.window.deinit();
        c.SDL_Quit();
    }
};

// :model
const Model = struct {
    vertex_buffer: *c.SDL_GPUBuffer,
    index_buffer: *c.SDL_GPUBuffer,
    texture: *c.SDL_GPUTexture,
    depth_texture: *c.SDL_GPUTexture,

    alloc: std.mem.Allocator,
    index_buffer_len: u32,

    fn init(alloc: std.mem.Allocator, state: AppState, mesh_file: []const u8, texture_file: []const u8) !Model {
        // Making the object model
        const obj = try obj_zig.Obj.from_file(alloc, mesh_file);

        var vertecies = try alloc.alloc(VertexData, obj.faces.len);
        var indicies = try alloc.alloc(u16, obj.faces.len);
        defer alloc.free(vertecies);
        defer alloc.free(indicies);

        const index_buffer_len = indicies.len;

        for (obj.faces, 0..) |face, i| {
            const uv = obj.uvs[face.uv];
            vertecies[i] = .{
                .position = obj.positions[face.pos],
                .color = WHITE,
                .uv = .fromSlice(&.{ uv.x(), 1 - uv.y() }),
            };
            indicies[i] = @intCast(i);
        }

        obj.deinit();

        // Creating vertex buffer and index buffer
        const vertex_buffer_size: u32 = @intCast(vertecies.len * @sizeOf(VertexData));
        const vertex_buffer = c.SDL_CreateGPUBuffer(state.gpu, &.{
            .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = vertex_buffer_size,
        }) orelse return error.CreateVBufFailed;
        const index_buffer_size: u32 = @intCast(indicies.len * @sizeOf(u16));
        const index_buffer = c.SDL_CreateGPUBuffer(state.gpu, &.{
            .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
            .size = index_buffer_size,
        }) orelse return error.CreateIBufFailed;

        const buffer_size = index_buffer_size + vertex_buffer_size;
        // Upload data to VBuf
        // - Create Transfer Buf
        const transfer_buffer = c.SDL_CreateGPUTransferBuffer(state.gpu, &.{
            .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = buffer_size,
        }) orelse return error.CreateTBufFailed;
        defer c.SDL_ReleaseGPUTransferBuffer(state.gpu, transfer_buffer);

        // - Map buffer to memory
        const transfer_mem: [*]u8 = @ptrCast(
            c.SDL_MapGPUTransferBuffer(state.gpu, transfer_buffer, false) orelse return error.MapTBufFailed,
        );

        // - Copy
        const vertex_bytes = std.mem.sliceAsBytes(vertecies);
        std.mem.copyForwards(u8, transfer_mem[0..vertex_bytes.len], vertex_bytes);
        const index_bytes = std.mem.sliceAsBytes(indicies);
        std.mem.copyForwards(u8, transfer_mem[vertex_bytes.len..buffer_size], index_bytes);
        c.SDL_UnmapGPUTransferBuffer(state.gpu, transfer_buffer);

        // - Begin Copy Pass
        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(state.gpu) orelse return error.GetCmdBufFailed;
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

        const f = try alloc.dupeZ(u8, texture_file);
        const texture = c.IMG_LoadGPUTexture(state.gpu, copy_pass, f, null, null) orelse return error.LoadTextureFailed;
        alloc.free(f);

        const depth_texture = c.SDL_CreateGPUTexture(state.gpu, &.{
            .format = DEPTH_FORMAT,
            .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            .width = state.window.width,
            .height = state.window.height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        }) orelse return error.DepthTextureFail;

        // - End Copy Pass and Submit
        c.SDL_EndGPUCopyPass(copy_pass);
        try check_err(
            c.SDL_SubmitGPUCommandBuffer(cmd_buf),
        );
        try state.log.info("Primed GPU buffers", .{});

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .texture = texture,
            .depth_texture = depth_texture,

            .alloc = alloc,
            .index_buffer_len = @intCast(index_buffer_len),
        };
    }

    fn deinit(self: *const Model, state: AppState) void {
        c.SDL_ReleaseGPUBuffer(state.gpu, self.vertex_buffer);
        c.SDL_ReleaseGPUBuffer(state.gpu, self.index_buffer);
        c.SDL_ReleaseGPUTexture(state.gpu, self.texture);
        c.SDL_ReleaseGPUTexture(state.gpu, self.depth_texture);
    }
};

// Helper function to check all SDL errors
fn check_err(b: bool) !void {
    if (b) return;
    std.log.err("SDL: {s}\r\n", .{c.SDL_GetError()});
    return error.SDL_Error;
}

// :alloc
var nalloc: usize = 0;
fn wrap_alloc() !void {
    const wa = struct {
        fn malloc(size: usize) callconv(.c) ?*anyopaque {
            nalloc += 1;
            return c.malloc(size);
        }
        fn calloc(num: usize, size: usize) callconv(.c) ?*anyopaque {
            nalloc += 1;
            return c.calloc(num, size);
        }
        fn realloc(ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
            if (ptr == null and new_size > 0) {
                nalloc += 1;
            } else if (ptr != null and new_size == 0) {
                nalloc -= 1;
            }
            return c.realloc(ptr, new_size);
        }
        fn free(ptr: ?*anyopaque) callconv(.c) void {
            nalloc -= 1;
            c.free(ptr);
        }
    };
    try check_err(
        c.SDL_SetMemoryFunctions(&wa.malloc, &wa.calloc, &wa.realloc, &wa.free),
    );
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

fn setup_pipeline(state: AppState) !*c.SDL_GPUGraphicsPipeline {
    // Create Shaders
    const vertex_shader = try load_shader(state.gpu, vert_shader, c.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0);
    const fragment_shader = try load_shader(state.gpu, frag_shader, c.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 1);
    defer c.SDL_ReleaseGPUShader(state.gpu, vertex_shader);
    defer c.SDL_ReleaseGPUShader(state.gpu, fragment_shader);

    try state.log.info("Shaders loaded", .{});

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
            .color_target_descriptions = &.{ .format = c.SDL_GetGPUSwapchainTextureFormat(state.gpu, state.window.ptr) },
            .has_depth_stencil_target = true,
            .depth_stencil_format = DEPTH_FORMAT,
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
        .rasterizer_state = .{
            .cull_mode = c.SDL_GPU_CULLMODE_BACK,
        },
    };
    return c.SDL_CreateGPUGraphicsPipeline(state.gpu, &pipeline_info) orelse return error.CreatePipelineFailed;
}

fn update_camera(state: *AppState, dt: f32, mouse_move: Vec2) void {
    // Get movement inputs
    const forewards_scale = @as(f32, @floatFromInt(keydown[c.SDL_SCANCODE_W])) - @as(f32, @floatFromInt(keydown[c.SDL_SCANCODE_S]));
    const right_scale = @as(f32, @floatFromInt(keydown[c.SDL_SCANCODE_D])) - @as(f32, @floatFromInt(keydown[c.SDL_SCANCODE_A]));

    const look_input = mouse_move.scale(MOUSE_SENSITIVITY);

    look.pitch = std.math.clamp(look.pitch - look_input.y(), -89, 89);
    look.yaw = std.math.wrap(look.yaw - look_input.x(), 360);

    const look_mat = zalg.Mat3.fromEulerAngles(.fromSlice(&.{ look.pitch, look.yaw, 0 }));

    const forwards: Vec3 = look_mat.mulByVec3(.fromSlice(&.{ 0, 0, -1 }));
    const right = look_mat.mulByVec3(.fromSlice(&.{ 1, 0, 0 }));

    // Calculate movement direction

    // Calculate movement motion
    var move_input = forwards.scale(forewards_scale).add(right.scale(right_scale));
    move_input.data[1] = 0;
    if (!move_input.eql(.zero())) move_input = move_input.norm().scale(SPEED * dt);

    // Apply movement
    state.camera.position = state.camera.position.add(move_input);
    // Update targe
    state.camera.target = state.camera.position.add(forwards);
}

// :main
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

    // Used to track SDL allocations through the process
    // try wrap_alloc();
    // defer log.info("SDL allocs: {}", .{nalloc}) catch {};

    var state: AppState = try .init(&log);
    defer state.deinit();

    const pipeline = try setup_pipeline(state);
    defer c.SDL_ReleaseGPUGraphicsPipeline(state.gpu, pipeline);

    // Setting up the projection matrix
    const x: f32 = @floatFromInt(state.window.width);
    const y: f32 = @floatFromInt(state.window.height);
    const proj_mat = Mat4.perspective(70, x / y, 0.0001, 1000);

    const rotation_speed = 90;
    var rotation: f32 = 0.0; // In Degrees

    const model: Model = try .init(alloc, state, OBJ_PATH, TEX_PATH);
    defer model.deinit(state);

    try state.log.info("Setup complete", .{});
    try state.log.flush();

    // Main Loop
    try state.log.info("Starting main loop", .{});
    var last_ticks = c.SDL_GetTicks();
    mainloop: while (true) {
        const this_ticks = c.SDL_GetTicks();
        const dt = @as(f32, @floatFromInt(this_ticks - last_ticks)) / 1000;
        last_ticks = this_ticks;

        var mouse_move: Vec2 = .zero();

        // :events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :mainloop,
                c.SDL_EVENT_KEY_DOWN => {
                    keydown[event.key.scancode] = 1;
                },
                c.SDL_EVENT_KEY_UP => {
                    keydown[event.key.scancode] = 0;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    mouse_move = mouse_move.add(.fromSlice(&.{ event.motion.xrel, event.motion.yrel }));
                },
                else => continue,
            }
        }

        update_camera(&state, dt, mouse_move);

        rotation += dt * rotation_speed;

        const view_mat = Mat4.lookAt(state.camera.position, state.camera.target, .up());
        const model_mat =
            Mat4.fromTranslate(.zero()).mul(
                Mat4.fromRotation(rotation, .up()),
            );
        const ubo: UBO = .{
            .mvp = proj_mat.mul(
                view_mat.mul(
                    model_mat,
                ),
            ),
        };

        // Render
        // - Aquire Command Buffer
        const cmd_buf = c.SDL_AcquireGPUCommandBuffer(state.gpu) orelse return error.AquireCmdBufFailed;

        // - Aquire Swapchain Texture
        var swp_texture: ?*c.SDL_GPUTexture = undefined;
        try check_err(
            c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, state.window.ptr, &swp_texture, 0, 0),
        );

        // - Begin Render Pass
        const colour_target_info: c.SDL_GPUColorTargetInfo = .{
            .texture = swp_texture,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .clear_color = .{ .r = 0, .g = 0.2, .b = 0.4, .a = 1 },
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const depth_target_info: c.SDL_GPUDepthStencilTargetInfo = .{
            .texture = model.depth_texture,
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
            .buffer = model.vertex_buffer,
        }, 1);

        // Bind the texture sampler
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &.{
            .texture = model.texture,
            .sampler = state.sampler,
        }, 1);

        // Bind Index Buffer
        c.SDL_BindGPUIndexBuffer(render_pass, &.{
            .offset = 0,
            .buffer = model.index_buffer,
        }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        // - - Bind Uniform Data
        c.SDL_PushGPUVertexUniformData(cmd_buf, 0, &ubo, @sizeOf(UBO));

        // - - Draw Calls
        c.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(model.index_buffer_len), 1, 0, 0, 0);

        // - End Render Pass
        c.SDL_EndGPURenderPass(render_pass);

        // - Repeat Render Passes

        // - Submit Command Buffer
        try check_err(
            c.SDL_SubmitGPUCommandBuffer(cmd_buf),
        );
        try state.log.flush();
    }
}

test "recurse" {
    std.testing.refAllDecls(@This());
}
