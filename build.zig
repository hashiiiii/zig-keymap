const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const toml = b.dependency("z_toml", .{ .target = target, .optimize = optimize }).module("toml");
    const keymap = b.addModule("keymap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "toml", .module = toml }},
    });
    const vaxis = b.dependency("vaxis", .{ .target = target, .optimize = optimize }).module("vaxis");
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "keymap", .module = keymap },
            .{ .name = "vaxis", .module = vaxis },
        },
    }) });
    b.step("test", "Run keymap tests").dependOn(&b.addRunArtifact(tests).step);
}
