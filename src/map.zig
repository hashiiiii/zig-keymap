const std = @import("std");
const testing = std.testing;
const KeySpec = @import("key.zig").KeySpec;

pub const Diagnostic = struct {
    pub const Kind = enum { syntax, unknown_context, unknown_action, invalid_type, invalid_key, collision, invalid_specification };
    kind: Kind,
    line: ?u32 = null,
    column: ?u32 = null,
    buffer: [512]u8 = undefined,
    length: usize,

    pub fn message(self: *const Diagnostic) []const u8 {
        return self.buffer[0..self.length];
    }

    fn init(kind: Kind, comptime format: []const u8, args: anytype) Diagnostic {
        var result: Diagnostic = .{ .kind = kind, .length = 0 };
        const text = std.fmt.bufPrint(&result.buffer, format, args) catch &result.buffer;
        result.length = text.len;
        return result;
    }
};

pub fn Keymap(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();
        pub const Default = struct { context: Context, action: Action, keys: []const []const u8 };
        pub const Specification = struct { defaults: []const Default, context_groups: []const []const Context };
        pub const LoadResult = union(enum) { bindings: Self, invalid: Diagnostic };
        const Entry = struct { context: Context, action: Action, keys: []const KeySpec, hint: []const u8 };

        arena: std.heap.ArenaAllocator,
        entries: []Entry,

        pub fn load(allocator: std.mem.Allocator, specification: Specification, text: ?[]const u8) std.mem.Allocator.Error!LoadResult {
            var arena = std.heap.ArenaAllocator.init(allocator);
            var retained = false;
            defer if (!retained) arena.deinit();
            const storage = arena.allocator();
            var parse_arena = std.heap.ArenaAllocator.init(allocator);
            defer parse_arena.deinit();
            var root: ?std.json.ObjectMap = null;
            if (text) |contents| {
                var scanner = std.json.Scanner.initCompleteInput(parse_arena.allocator(), contents);
                defer scanner.deinit();
                var info: std.json.Diagnostics = .{};
                scanner.enableDiagnostics(&info);
                const value = std.json.parseFromTokenSourceLeaky(std.json.Value, parse_arena.allocator(), &scanner, .{}) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        var diagnostic = Diagnostic.init(.syntax, "Invalid JSON: {s}", .{@errorName(err)});
                        diagnostic.line = std.math.cast(u32, info.getLine());
                        diagnostic.column = std.math.cast(u32, info.getColumn());
                        return .{ .invalid = diagnostic };
                    },
                };
                if (value != .object) return .{ .invalid = Diagnostic.init(.invalid_type, "Configuration must be an object", .{}) };
                root = value.object;
            }
            if (root) |object| {
                for (object.keys(), object.values()) |context_name, context_value| {
                    const context = std.meta.stringToEnum(Context, context_name) orelse return .{ .invalid = Diagnostic.init(.unknown_context, "Unknown context '{s}'", .{context_name}) };
                    var known = false;
                    for (specification.defaults) |binding| {
                        if (binding.context == context) known = true;
                    }
                    if (!known) return .{ .invalid = Diagnostic.init(.unknown_context, "Unknown context '{s}'", .{context_name}) };
                    if (context_value != .object) return .{ .invalid = Diagnostic.init(.invalid_type, "Context '{s}' must be an object", .{context_name}) };
                    for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                        var allowed = false;
                        for (specification.defaults) |binding| {
                            if (binding.context == context and std.mem.eql(u8, @tagName(binding.action), action_name)) allowed = true;
                        }
                        if (!allowed) return .{ .invalid = Diagnostic.init(.unknown_action, "Unknown action '{s}.{s}'", .{ context_name, action_name }) };
                        if (value != .array) return .{ .invalid = Diagnostic.init(.invalid_type, "'{s}.{s}' must be an array of keys", .{ context_name, action_name }) };
                        for (value.array.items) |item| {
                            if (item != .string) return .{ .invalid = Diagnostic.init(.invalid_type, "'{s}.{s}' must contain strings", .{ context_name, action_name }) };
                        }
                    }
                }
            }
            const entries = try storage.alloc(Entry, specification.defaults.len);
            for (specification.defaults, 0..) |binding, index| {
                for (specification.defaults[0..index]) |previous| {
                    if (previous.context == binding.context and previous.action == binding.action) return .{ .invalid = Diagnostic.init(.invalid_specification, "Duplicate default '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) }) };
                }
                const override = if (root) |object| blk: {
                    const context = object.get(@tagName(binding.context)) orelse break :blk null;
                    break :blk context.object.get(@tagName(binding.action));
                } else null;
                const count = if (override) |value| value.array.items.len else binding.keys.len;
                const parsed_keys = try storage.alloc(KeySpec, count);
                for (parsed_keys, 0..) |*key, key_index| {
                    const expression = if (override) |value| value.array.items[key_index].string else binding.keys[key_index];
                    key.* = KeySpec.parse(expression) catch return .{ .invalid = Diagnostic.init(.invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(binding.context), @tagName(binding.action) }) };
                }
                var label_buffer: [96]u8 = undefined;
                entries[index] = .{ .context = binding.context, .action = binding.action, .keys = parsed_keys, .hint = if (parsed_keys.len == 0) "" else try storage.dupe(u8, parsed_keys[0].format(&label_buffer)) };
            }
            for (entries, 0..) |a, index| {
                for (entries[index + 1 ..]) |b| {
                    if (!canOverlap(specification.context_groups, a.context, b.context)) continue;
                    for (a.keys) |ak| {
                        for (b.keys) |bk| {
                            if (ak.equivalent(bk)) return .{ .invalid = Diagnostic.init(.collision, "Key collision between '{s}.{s}' and '{s}.{s}'", .{ @tagName(a.context), @tagName(a.action), @tagName(b.context), @tagName(b.action) }) };
                        }
                    }
                }
            }
            retained = true;
            return .{ .bindings = .{ .arena = arena, .entries = entries } };
        }

        fn canOverlap(groups: []const []const Context, a: Context, b: Context) bool {
            if (a == b) return true;
            for (groups) |group| {
                var has_a = false;
                var has_b = false;
                for (group) |context| {
                    has_a = has_a or context == a;
                    has_b = has_b or context == b;
                }
                if (has_a and has_b) return true;
            }
            return false;
        }

        /// Returns the first matching action, or `null` when no binding matches.
        /// The order of `active_contexts`, then default declaration order, decides which action wins when several bindings match.
        /// Matchers must provide `matches(KeySpec) bool`; use `vaxisMatcher` for libvaxis keys.
        pub fn resolve(self: *const Self, active_contexts: []const Context, matcher: anytype) ?Action {
            for (active_contexts) |context| {
                for (self.entries) |entry| {
                    if (entry.context != context) continue;
                    for (entry.keys) |key| {
                        if (matcher.matches(key)) return entry.action;
                    }
                }
            }
            return null;
        }

        /// Returns configured keys, or an empty slice for an unbound action.
        /// The keymap owns this slice; it remains valid until `deinit()` and must not be freed separately.
        pub fn keys(self: *const Self, context: Context, action: Action) []const KeySpec {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.keys;
            }
            return &.{};
        }

        /// Returns the first configured key as a label, or an empty string for an unbound action.
        /// The keymap owns this label; it remains valid until `deinit()` and must not be freed separately.
        pub fn hint(self: *const Self, context: Context, action: Action) []const u8 {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.hint;
            }
            return "";
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined;
        }
    };
}

test "load uses default aliases and the first key as the hint" {
    // Applications need every default alias, even though hints show only the first key.
    const Map = Keymap(enum { tree }, enum { move_down, move_up });
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } }},
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();

    try testing.expectEqual(@as(usize, 2), map.keys(.tree, .move_down).len);
    try testing.expectEqual(KeySpec{ .key = .{ .named = .down } }, map.keys(.tree, .move_down)[0]);
    try testing.expectEqual(KeySpec{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1]);
    try testing.expectEqualStrings("Down", map.hint(.tree, .move_down));
    try testing.expectEqual(@as(usize, 0), map.keys(.tree, .move_up).len);
    try testing.expectEqualStrings("", map.hint(.tree, .move_up));
}

test "load rejects unknown contexts and actions" {
    // Misspelled or misplaced actions must not silently fall back to defaults.
    const Map = Keymap(enum { tree, dialog }, enum { move_down, cancel });
    const specification: Map.Specification = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    const context = (try Map.load(testing.allocator, specification,
        \\{"unknown": {"move_down": []}}
    )).invalid;
    try testing.expectEqual(Diagnostic.Kind.unknown_context, context.kind);
    try testing.expectEqualStrings("Unknown context 'unknown'", context.message());
    try testing.expectEqual(Diagnostic.Kind.unknown_context, (try Map.load(testing.allocator, specification,
        \\{"dialog": {"cancel": []}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.unknown_action, (try Map.load(testing.allocator, specification,
        \\{"tree": {"unknown_action": []}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.unknown_action, (try Map.load(testing.allocator, specification,
        \\{"tree": {"cancel": []}}
    )).invalid.kind);
}

test "load requires context objects and arrays of strings" {
    // Valid JSON can still have a shape that cannot describe key bindings.
    const Map = Keymap(enum { tree }, enum { move_down });
    const specification: Map.Specification = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, specification, "null")).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, specification, "[]")).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, specification,
        \\{"tree": 1}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, specification,
        \\{"tree": {"move_down": 1}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, specification,
        \\{"tree": {"move_down": [1]}}
    )).invalid.kind);
}

test "load rejects invalid default and override keys" {
    // Both application defaults and user overrides must pass key validation.
    const Map = Keymap(enum { tree }, enum { move_down });
    try testing.expectEqual(Diagnostic.Kind.invalid_key, (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"Unknown+j"} }},
        .context_groups = &.{},
    }, null)).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_key, (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    },
        \\{"tree": {"move_down": ["Ctrl+Ctrl+x"]}}
    )).invalid.kind);
}

test "load reports JSON syntax locations and rejects duplicate fields" {
    // Syntax diagnostics must identify where users can fix their configuration.
    const Map = Keymap(enum { tree }, enum { move_down });
    const specification: Map.Specification = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    const syntax = (try Map.load(testing.allocator, specification,
        \\{
        \\"tree": ?
        \\}
    )).invalid;
    try testing.expectEqual(Diagnostic.Kind.syntax, syntax.kind);
    try testing.expectEqual(@as(?u32, 2), syntax.line);
    try testing.expectEqual(@as(?u32, 9), syntax.column);
    try testing.expectEqualStrings("Invalid JSON: SyntaxError", syntax.message());
    try testing.expectEqual(Diagnostic.Kind.syntax, (try Map.load(testing.allocator, specification,
        \\{"tree": {}, "tree": {}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.syntax, (try Map.load(testing.allocator, specification,
        \\{"tree": {"move_down": [], "move_down": []}}
    )).invalid.kind);
}

test "load rejects duplicate default actions" {
    // Duplicate actions make override and hint selection ambiguous.
    const Map = Keymap(enum { tree }, enum { move_down });
    try testing.expectEqual(Diagnostic.Kind.invalid_specification, (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"Down"} },
        },
        .context_groups = &.{},
    }, null)).invalid.kind);
}

test "load rejects collisions within a context" {
    // One key must not select two actions in the same context.
    const Map = Keymap(enum { tree }, enum { move_down, move_up });
    try testing.expectEqual(Diagnostic.Kind.collision, (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
            .{ .context = .tree, .action = .move_up, .keys = &.{"k"} },
        },
        .context_groups = &.{},
    },
        \\{"tree": {"move_up": ["j"]}}
    )).invalid.kind);
}

test "load rejects collisions across context groups" {
    // Global shortcuts must not shadow navigation in a declared active group.
    const Map = Keymap(enum { global, tree }, enum { quit, move_down });
    const collision = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{"q"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
        },
        .context_groups = &.{&.{ .global, .tree }},
    },
        \\{"global": {"quit": ["j"]}}
    )).invalid;
    try testing.expectEqual(Diagnostic.Kind.collision, collision.kind);
    try testing.expectEqualStrings("Key collision between 'global.quit' and 'tree.move_down'", collision.message());
}

test "load rejects equivalent ASCII Shift bindings" {
    // Alternate spellings must not evade collision validation.
    const Map = Keymap(enum { tree }, enum { move_down, move_up });
    try testing.expectEqual(Diagnostic.Kind.collision, (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_down, .keys = &.{"Shift+j"} },
            .{ .context = .tree, .action = .move_up, .keys = &.{"J"} },
        },
        .context_groups = &.{},
    }, null)).invalid.kind);
}

test "load owns bindings after the input is freed" {
    // Applications can release configuration text immediately after loading.
    const Map = Keymap(enum { tree }, enum { move_down });
    var map = blk: {
        const text = try testing.allocator.dupe(u8,
            \\{"tree": {"move_down": ["Ctrl+\u006e", "j"]}}
        );
        defer testing.allocator.free(text);
        break :blk (try Map.load(testing.allocator, .{
            .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
            .context_groups = &.{},
        }, text)).bindings;
    };
    defer map.deinit();
    try testing.expectEqual(KeySpec{ .key = .{ .character = 'n' }, .modifiers = .{ .ctrl = true } }, map.keys(.tree, .move_down)[0]);
    try testing.expectEqual(KeySpec{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1]);
    try testing.expectEqualStrings("Ctrl+n", map.hint(.tree, .move_down));
}
