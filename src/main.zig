const std = @import("std");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const j3d = jok.j3d;
const zmath = jok.zmath;
const imgui = jok.imgui;
const nfd = jok.nfd;

pub const jok_window_title: [:0]const u8 = "glTF-Viewer";
pub const jok_window_size = jok.config.WindowSize{
    .custom = .{ .width = 1024, .height = 768 },
};
pub const jok_window_resizable = false;
pub const jok_exit_on_recv_esc = false;

var axis_camera: j3d.Camera = undefined;
var model_camera: j3d.Camera = undefined;
var model_path: ?nfd.FilePath = null;
var mesh: *j3d.Mesh = undefined;
var loading_model = std.atomic.Value(bool).init(false);
var axis_tex: sdl.Texture = undefined;
var wireframe: bool = false;
var gouraud_shading: bool = false;

fn openModel(ctx: jok.Context) !void {
    defer loading_model.store(false, .Release);

    if (try nfd.openFileDialog("glb,gltf", null)) |path| {
        errdefer sdl.showSimpleMessageBox(
            .{ .@"error" = true },
            "ERROR",
            "Unable to open model file, wrong format?",
            null,
        ) catch unreachable;
        const m = try j3d.Mesh.fromGltf(
            ctx.allocator(),
            ctx.renderer(),
            path.path,
            .{},
        );

        if (model_path) |p| {
            p.deinit();
            mesh.destroy();
        }
        model_path = path;
        mesh = m;
    }
}

pub fn init(ctx: jok.Context) !void {
    try ctx.renderer().setColorRGB(100, 100, 100);

    axis_camera = j3d.Camera.fromPositionAndTarget(
        .{
            .perspective = .{
                .fov = jok.utils.math.degreeToRadian(70),
                .aspect_ratio = ctx.getAspectRatio(),
                .near = 0.1,
                .far = 1000,
            },
        },
        [_]f32{ 5, 5, 5 },
        [_]f32{ 0, 0, 0 },
    );
    model_camera = axis_camera;

    axis_tex = try jok.utils.gfx.createTextureAsTarget(
        ctx.renderer(),
        .{
            .size = .{ .x = 200, .y = 200 },
        },
    );
}

pub fn event(ctx: jok.Context, e: sdl.Event) !void {
    if (imgui.io.getWantCaptureMouse()) return;

    switch (e) {
        .mouse_motion => |me| {
            const mouse_state = ctx.getMouseState();
            if (!mouse_state.buttons.getPressed(.left)) {
                return;
            }

            axis_camera.rotateAroundBy(
                null,
                @as(f32, @floatFromInt(me.delta_x)) * 0.01,
                @as(f32, @floatFromInt(me.delta_y)) * 0.01,
            );

            model_camera.rotateAroundBy(
                null,
                @as(f32, @floatFromInt(me.delta_x)) * 0.01,
                @as(f32, @floatFromInt(me.delta_y)) * 0.01,
            );
        },
        .mouse_wheel => |me| {
            model_camera.zoomBy(@as(f32, @floatFromInt(me.delta_y)) * -0.05);
        },
        else => {},
    }
}

pub fn update(ctx: jok.Context) !void {
    _ = ctx;
}

pub fn draw(ctx: jok.Context) !void {
    imgui.beginDisabled(.{ .disabled = loading_model.load(.Acquire) });
    {
        if (imgui.begin("Browser", .{
            .flags = .{ .always_auto_resize = true },
        })) {
            if (imgui.button("open", .{})) {
                loading_model.store(true, .Monotonic);
                var handle = try std.Thread.spawn(
                    .{},
                    openModel,
                    .{ctx},
                );
                handle.detach();
            }

            if (model_path) |p| {
                imgui.sameLine(.{ .spacing = 10 });
                imgui.text(
                    comptime "{s}",
                    .{p.path},
                );

                _ = imgui.checkbox("wireframe", .{ .v = &wireframe });
                _ = imgui.checkbox("gouraud shading", .{ .v = &gouraud_shading });
            }
        }
        imgui.end();
    }
    imgui.endDisabled();

    _ = try jok.utils.gfx.renderToTexture(
        ctx.renderer(),
        struct {
            pub fn draw(_: @This(), _: sdl.Renderer, _: sdl.PointF) !void {
                try j3d.begin(.{ .camera = axis_camera });
                try j3d.axises(.{ .radius = 0.1, .length = 3 });
                try j3d.end();
            }
        }{},
        .{
            .target = axis_tex,
            .clear_color = sdl.Color.rgba(255, 0, 0, 0),
        },
    );

    try ctx.renderer().clear();
    if (!loading_model.load(.Acquire) and model_path != null) {
        try j3d.begin(.{
            .camera = model_camera,
            .wireframe_color = if (wireframe) sdl.Color.green else null,
            .triangle_sort = .simple,
        });
        try j3d.mesh(
            mesh,
            zmath.identity(),
            .{
                .lighting = .{},
                .shading_method = if (gouraud_shading) .gouraud else .flat,
            },
        );
        try j3d.end();
    }

    var axis_pos = ctx.getFramebufferSize();
    axis_pos.x -= 200;
    axis_pos.y = 0;
    try j2d.begin(.{});
    try j2d.image(
        axis_tex,
        axis_pos,
        .{},
    );
    try j2d.end();

    ctx.displayStats(.{ .collapsible = true });
}

pub fn quit(ctx: jok.Context) void {
    _ = ctx;

    if (model_path) |p| {
        p.deinit();
        mesh.destroy();
    }
}
