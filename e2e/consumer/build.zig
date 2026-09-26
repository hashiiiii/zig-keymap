const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const keymap = b.dependency("zig_keymap", .{ .target = target, .optimize = optimize }).module("keymap");
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("consumer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "keymap", .module = keymap }},
    }) });
    b.step("test", "Check the consumer without external dependencies").dependOn(&b.addRunArtifact(tests).step);
}
