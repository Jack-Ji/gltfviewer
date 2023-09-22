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
var loading_model = std.atomic.Atomic(bool).init(false);
var axis_tex: sdl.Texture = undefined;

fn openModel(ctx: jok.Context) !void {
    defer loading_model.store(false, .Monotonic);

    if (try nfd.openFileDialog("glb,gltf", null)) |path| {
        if (model_path) |p| {
            p.deinit();
            mesh.destroy();
        }

        model_path = path;
        mesh = try j3d.Mesh.fromGltf(
            ctx.allocator(),
            ctx.renderer(),
            path.path,
            .{},
        );
    }
}

pub fn init(ctx: jok.Context) !void {
    try ctx.renderer().setColorRGB(166, 205, 231);

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
        null,
    );
    model_camera = axis_camera;

    axis_tex = try jok.utils.gfx.createTextureAsTarget(
        ctx.renderer(),
        .{ .x = 200, .y = 200 },
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
    imgui.beginDisabled(.{ .disabled = loading_model.loadUnchecked() });
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
            }
        }
        imgui.end();
    }
    imgui.endDisabled();
}

pub fn draw(ctx: jok.Context) !void {
    try ctx.renderer().setTarget(axis_tex);
    try ctx.renderer().clear();
    try j3d.begin(.{ .camera = axis_camera });
    try j3d.axises(.{ .radius = 0.1, .length = 3 });
    try j3d.end();
    try ctx.renderer().setTarget(null);

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

    if (loading_model.load(.Monotonic) or model_path == null) return;

    try j3d.begin(.{ .camera = model_camera });
    try j3d.mesh(
        mesh,
        zmath.identity(),
        .{ .lighting = .{} },
    );
    try j3d.end();
}

pub fn quit(ctx: jok.Context) void {
    _ = ctx;

    if (model_path) |p| {
        p.deinit();
        mesh.destroy();
    }
}
