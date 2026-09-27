const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const keymap = b.addModule("keymap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Only repository tests need terminal packages; consumers supply their own key types.
    if (b.dep_prefix.len != 0) return;
    const docs = b.addObject(.{
        .name = "keymap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Generate API documentation").dependOn(&install_docs.step);

    const vaxis = (b.lazyDependency("vaxis", .{ .target = target, .optimize = optimize }) orelse return).module("vaxis");
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "vaxis", .module = vaxis }},
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
