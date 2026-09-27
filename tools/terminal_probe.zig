const std = @import("std");
const builtin = @import("builtin");
const keymap = @import("keymap");
const vaxis = @import("vaxis");

const Context = enum { global };
const Action = enum { exit, lowercase_a, uppercase_a, unicode, alt_k, ctrl_k, super_k, ctrl_alt_at, colon, shifted_semicolon };
const Bindings = keymap.Bindings(Context, Action);

const Metadata = struct {
    os: []const u8,
    os_version: []const u8,
    terminal_program: ?[]const u8,
    terminal_version: ?[]const u8,
    term: ?[]const u8,
    keyboard_protocol: []const u8,
    layout: []const u8,
};

const Input = struct {
    kind: []const u8,
    codepoint: ?u21 = null,
    text: ?[]const u8 = null,
    shifted_codepoint: ?u21 = null,
    base_layout_codepoint: ?u21 = null,
    modifiers: ?vaxis.Key.Modifiers = null,
    paste_bytes: ?usize = null,
};

const Record = struct {
    os: []const u8,
    os_version: []const u8,
    terminal_program: ?[]const u8,
    terminal_version: ?[]const u8,
    term: ?[]const u8,
    keyboard_protocol: []const u8,
    layout: []const u8,
    event: Input,
    action: ?[]const u8,
    label: ?[]const u8,
};

const definition: Bindings.Definition = .{
    .defaults = &.{
        .{ .context = .global, .action = .exit, .keys = &.{"Escape"} },
        .{ .context = .global, .action = .lowercase_a, .keys = &.{"a"} },
        .{ .context = .global, .action = .uppercase_a, .keys = &.{"A"} },
        .{ .context = .global, .action = .unicode, .keys = &.{"あ"} },
        .{ .context = .global, .action = .alt_k, .keys = &.{"Alt+k"} },
        .{ .context = .global, .action = .ctrl_k, .keys = &.{"Ctrl+k"} },
        .{ .context = .global, .action = .super_k, .keys = &.{"Super+k"} },
        .{ .context = .global, .action = .ctrl_alt_at, .keys = &.{"Ctrl+Alt+@"} },
        .{ .context = .global, .action = .colon, .keys = &.{":"} },
        .{ .context = .global, .action = .shifted_semicolon, .keys = &.{"Shift+;"} },
    },
    .context_groups = &.{},
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5 or
        !std.mem.eql(u8, args[1], "--os-version") or
        !std.mem.eql(u8, args[3], "--layout"))
    {
        var output_buffer: [256]u8 = undefined;
        var output_file = std.Io.File.stderr().writer(init.io, &output_buffer);
        try output_file.interface.writeAll("Usage: terminal-probe --os-version <version> --layout <name>\n");
        try output_file.interface.flush();
        return error.InvalidArguments;
    }

    const metadata: Metadata = .{
        .os = @tagName(builtin.os.tag),
        .os_version = args[2],
        .terminal_program = init.environ_map.get("TERM_PROGRAM"),
        .terminal_version = init.environ_map.get("TERM_PROGRAM_VERSION"),
        .term = init.environ_map.get("TERM"),
        .keyboard_protocol = "not-detected-by-libvaxis",
        .layout = args[4],
    };

    var tty_buffer: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(init.io, &tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(init.io, init.gpa, init.environ_map, .{});
    defer vx.deinit(init.gpa, tty.writer());

    var loop: vaxis.Loop(vaxis.Event) = .init(init.io, &tty, &vx);
    try loop.installResizeHandler();
    defer loop.uninstallResizeHandler();
    try loop.start();
    defer loop.stop();

    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    var negotiated = metadata;
    if (vx.caps.kitty_keyboard) negotiated.keyboard_protocol = "kitty";
    try tty.writer().writeAll("Terminal input probe. Press Escape to finish.\r\n");
    try tty.writer().flush();

    const result = try Bindings.load(init.gpa, definition, null);
    var bindings = switch (result) {
        .bindings => |value| value,
        .invalid => return error.InvalidProbeBindings,
    };
    defer bindings.deinit();

    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                const action = bindings.resolve(&.{.global}, keymap.vaxisMatcher(key));
                try emit(init.gpa, tty.writer(), negotiated, .{
                    .kind = "key_press",
                    .codepoint = key.codepoint,
                    .text = key.text,
                    .shifted_codepoint = key.shifted_codepoint,
                    .base_layout_codepoint = key.base_layout_codepoint,
                    .modifiers = key.mods,
                }, action, &bindings);
                if (action) |selected| {
                    if (selected == .exit) break;
                }
            },
            .paste_start => try emit(init.gpa, tty.writer(), negotiated, .{ .kind = "paste_start" }, null, &bindings),
            .paste => |contents| try emit(init.gpa, tty.writer(), negotiated, .{ .kind = "paste", .paste_bytes = contents.len }, null, &bindings),
            .paste_end => try emit(init.gpa, tty.writer(), negotiated, .{ .kind = "paste_end" }, null, &bindings),
            else => {},
        }
    }
}

fn emit(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    metadata: Metadata,
    event: Input,
    action: ?Action,
    bindings: *const Bindings,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const record: Record = .{
        .os = metadata.os,
        .os_version = metadata.os_version,
        .terminal_program = metadata.terminal_program,
        .terminal_version = metadata.terminal_version,
        .term = metadata.term,
        .keyboard_protocol = metadata.keyboard_protocol,
        .layout = metadata.layout,
        .event = event,
        .action = if (action) |value| @tagName(value) else null,
        .label = if (action) |value| bindings.hint(.global, value) else null,
    };
    const json = try std.json.Stringify.valueAlloc(arena.allocator(), record, .{});
    try writer.writeAll(json);
    try writer.writeAll("\r\n");
    try writer.flush();
}
