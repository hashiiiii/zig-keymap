const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const toml = b.dependency("z_toml", .{ .target = target, .optimize = optimize }).module("toml");
    const vaxis = b.dependency("vaxis", .{ .target = target, .optimize = optimize }).module("vaxis");
    const keymap = b.addModule("keymap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "toml", .module = toml }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "toml", .module = toml },
            .{ .name = "vaxis", .module = vaxis },
        },
    }) });
    const e2e = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("e2e/keymap.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "keymap", .module = keymap },
            .{ .name = "vaxis", .module = vaxis },
        },
    }) });
    const test_step = b.step("test", "Run unit and end-to-end tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(e2e).step);
}
