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
var scale: f32 = 1.0;
var wireframe: bool = false;
var gouraud_shading: bool = false;
var animation: ?*j3d.Animation = null;
var animation_names: std.ArrayList([:0]u8) = undefined;
var animation_idx: i32 = -1;
var animation_playtime: f32 = 0;

fn openModel(ctx: jok.Context) !void {
    defer loading_model.store(false, .release);

    if (try nfd.openFileDialog("glb,gltf", null)) |path| {
        errdefer sdl.showSimpleMessageBox(
            .{ .@"error" = true },
            "ERROR",
            "Unable to open model file, wrong format?",
            null,
        ) catch unreachable;
        const m = try j3d.Mesh.fromGltf(
            ctx,
            path.path,
            .{},
        );

        if (model_path) |p| {
            p.deinit();
            mesh.destroy();
            if (animation) |a| a.destroy();
        }
        model_path = path;
        mesh = m;
        animation = null;
        for (animation_names.items) |n| ctx.allocator().free(n);
        animation_names.clearRetainingCapacity();
        var anim_it = m.animations.keyIterator();
        while (anim_it.next()) |a| {
            try animation_names.append(try std.fmt.allocPrintZ(ctx.allocator(), "{s}", .{a.*}));
        }
        animation_idx = -1;
        animation_playtime = 0.0;
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
        ctx,
        .{
            .size = .{ .width = 200, .height = 200 },
        },
    );

    animation_names = std.ArrayList([:0]u8).init(ctx.allocator());
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

pub fn update(_: jok.Context) !void {}

pub fn draw(ctx: jok.Context) !void {
    imgui.beginDisabled(.{ .disabled = loading_model.load(.acquire) });
    {
        if (imgui.begin("Browser", .{
            .flags = .{ .always_auto_resize = true },
        })) {
            if (imgui.button("open", .{})) {
                loading_model.store(true, .monotonic);
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

                _ = imgui.dragFloat("scale", .{
                    .v = &scale,
                    .speed = 0.01,
                    .min = 0.01,
                    .max = 100,
                });
                _ = imgui.checkbox("wireframe", .{ .v = &wireframe });
                _ = imgui.checkbox("gouraud shading", .{ .v = &gouraud_shading });

                if (imgui.beginCombo(
                    "animations",
                    .{
                        .preview_value = if (animation_idx == -1)
                            "none"
                        else
                            animation_names.items[@as(usize, @intCast(animation_idx))],
                    },
                )) {
                    for (animation_names.items, 0..) |n, idx| {
                        if (imgui.selectable(n, .{})) {
                            animation_idx = @intCast(idx);
                            if (animation) |a| a.destroy();
                            animation = try j3d.Animation.create(
                                ctx.allocator(),
                                mesh.getAnimation(std.mem.sliceTo(n, 0)).?,
                            );
                        }
                    }
                    imgui.endCombo();
                }
            }
        }
        imgui.end();
    }
    imgui.endDisabled();

    _ = try jok.utils.gfx.renderToTexture(
        ctx,
        struct {
            pub fn draw(_: @This(), _: jok.Context, _: sdl.PointF) !void {
                j3d.begin(.{ .camera = axis_camera });
                try j3d.axises(.{ .radius = 0.1, .length = 3 });
                j3d.end();
            }
        }{},
        .{
            .target = axis_tex,
            .clear_color = sdl.Color.rgba(255, 0, 0, 0),
        },
    );

    try ctx.renderer().clear();
    if (!loading_model.load(.acquire) and model_path != null) {
        j3d.begin(.{
            .camera = model_camera,
            .wireframe_color = if (wireframe) sdl.Color.green else null,
            .triangle_sort = .simple,
        });
        defer j3d.end();

        const mat = zmath.mul(
            zmath.scalingV(zmath.f32x4s(scale)),
            zmath.translation(0.0, -1.0, 0.0),
        );
        if (animation) |a| {
            try j3d.animation(
                a,
                mat,
                .{
                    .lighting = .{},
                    .shading_method = if (gouraud_shading) .gouraud else .flat,
                    .playtime = animation_playtime,
                },
            );
            animation_playtime += ctx.deltaSeconds();
            if (animation_playtime > a.getDuration()) animation_playtime = 0.0;
        } else {
            try j3d.mesh(
                mesh,
                mat,
                .{
                    .lighting = .{},
                    .shading_method = if (gouraud_shading) .gouraud else .flat,
                },
            );
        }
    }

    {
        j2d.begin(.{});
        defer j2d.end();

        var axis_pos = ctx.getCanvasSize();
        axis_pos.x -= 200;
        axis_pos.y = 0;
        try j2d.image(
            axis_tex,
            axis_pos,
            .{},
        );
    }

    ctx.displayStats(.{ .collapsible = true });
}

pub fn quit(ctx: jok.Context) void {
    if (model_path) |p| {
        p.deinit();
        mesh.destroy();
        if (animation) |a| a.destroy();
        for (animation_names.items) |n| ctx.allocator().free(n);
        animation_names.deinit();
    }
}
