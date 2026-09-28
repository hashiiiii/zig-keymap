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

    const ExpectedCompileErrors = std.Build.Step.Compile.ExpectedCompileErrors;
    const compile_failures = .{
        .{ .path = "e2e/compile_fail/invalid_key.zig", .expect = ExpectedCompileErrors{ .contains = "Invalid key step 'Unknown+j' in default 'tree.move_down' on macos" } },
        .{ .path = "e2e/compile_fail/duplicate_modifiers.zig", .expect = ExpectedCompileErrors{ .contains = "Invalid key step 'Ctrl+Mod+j' in default 'tree.move_down' on linux" } },
        .{ .path = "e2e/compile_fail/duplicate_default.zig", .expect = ExpectedCompileErrors{ .contains = "Duplicate default 'tree.move_down'" } },
        .{ .path = "e2e/compile_fail/context_group_prefix.zig", .expect = ExpectedCompileErrors{ .contains = "Key collision between 'global.quit' shortcut 'g' and 'tree.move_down' shortcut 'g g' on macos" } },
        .{ .path = "e2e/compile_fail/action_prefix.zig", .expect = ExpectedCompileErrors{ .contains = "Shortcut prefix collision between 'tree.move_down' shortcuts 'g' and 'g g' on macos" } },
        .{ .path = "e2e/compile_fail/mod_macos_collision.zig", .expect = ExpectedCompileErrors{ .contains = "Key collision between 'tree.quit' shortcut 'Mod+q' and 'tree.move_down' shortcut 'Super+q' on macos" } },
        .{ .path = "e2e/compile_fail/mod_windows_linux_collision.zig", .expect = ExpectedCompileErrors{ .exact = &.{
            ":?:?: error: Key collision between 'tree.quit' shortcut 'Mod+q' and 'tree.move_down' shortcut 'Ctrl+q' on windows",
            "Key collision between 'tree.quit' shortcut 'Mod+q' and 'tree.move_down' shortcut 'Ctrl+q' on linux",
        } } },
    };
    inline for (compile_failures) |fixture| {
        const compile = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(fixture.path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "keymap", .module = keymap }},
        }) });
        compile.expect_errors = fixture.expect;
        test_step.dependOn(&compile.step);
    }
}
