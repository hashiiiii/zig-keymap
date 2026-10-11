const std = @import("std");
const testing = std.testing;
const KeyPress = @import("key.zig").KeyPress;

/// An owned description of invalid configuration. Call deinit after reading it.
pub const Diagnostic = struct {
    pub const Kind = enum {
        invalid_json,
        unknown_context,
        unknown_action,
        invalid_type,
        invalid_key,
        duplicate_default,
        collision,
    };

    kind: Kind,
    message: []const u8,
    /// JSON syntax position, starting at 1; null for other configuration errors.
    line: ?u64 = null,
    column: ?u64 = null,
    allocator: std.mem.Allocator,

    /// Frees the diagnostic message.
    pub fn deinit(self: *Diagnostic) void {
        self.allocator.free(self.message);
        self.* = undefined;
    }

    fn init(allocator: std.mem.Allocator, kind: Kind, comptime format: []const u8, args: anytype) std.mem.Allocator.Error!Diagnostic {
        return .{ .allocator = allocator, .kind = kind, .message = try std.fmt.allocPrint(allocator, format, args) };
    }
};

/// JSON key bindings and input state for Context and Action enums.
/// Use one instance per input stream.
pub fn Bindings(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();

        /// Default keys for one context and action.
        pub const Default = struct {
            context: Context,
            action: Action,
            /// Aliases such as Down, Ctrl+n, or g g. Use Space for the space key.
            keys: []const []const u8,
        };

        /// Outcome of one input event.
        pub const Result = union(enum) {
            none,
            pending,
            action: Action,
        };

        const Binding = struct {
            context: Context,
            action: Action,
            keys: []const KeyPress,
            next_step: ?usize = null,
        };

        arena: std.heap.ArenaAllocator,
        bindings: []Binding,

        /// Loaded bindings or an owned configuration diagnostic.
        /// Call deinit on the selected payload.
        pub const LoadResult = union(enum) {
            bindings: Self,
            invalid: Diagnostic,
        };

        const ParsedBinding = struct {
            binding: Binding,
            expression: []const u8,
        };

        /// Loads defaults and JSON assignments; null keeps all defaults.
        /// Arrays replace aliases, [] disables an action, and omitted actions keep defaults.
        /// JSON accepts any Context and Action enum pair, including pairs without defaults.
        /// Invalid configuration returns .invalid; allocation failures return error.OutOfMemory.
        /// Both payloads own their data; callers may free defaults and text after loading.
        pub fn load(allocator: std.mem.Allocator, defaults: []const Default, text: ?[]const u8) std.mem.Allocator.Error!LoadResult {
            var arena = std.heap.ArenaAllocator.init(allocator);
            var retained = false;
            defer if (!retained) arena.deinit();
            const storage = arena.allocator();
            var parse_arena = std.heap.ArenaAllocator.init(allocator);
            defer parse_arena.deinit();
            const temporary = parse_arena.allocator();
            var root: ?std.json.ObjectMap = null;
            if (text) |contents| {
                var scanner = std.json.Scanner.initCompleteInput(temporary, contents);
                defer scanner.deinit();
                var position: std.json.Diagnostics = .{};
                scanner.enableDiagnostics(&position);
                const value = std.json.parseFromTokenSourceLeaky(std.json.Value, temporary, &scanner, .{}) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        var diagnostic = try Diagnostic.init(allocator, .invalid_json, "Invalid JSON: {s}", .{@errorName(err)});
                        diagnostic.line = position.getLine();
                        diagnostic.column = position.getColumn();
                        return .{ .invalid = diagnostic };
                    },
                };
                if (value != .object) return invalid(allocator, .invalid_type, "The JSON root must be an object", .{});
                root = value.object;
            }
            if (root) |object| {
                for (object.keys(), object.values()) |context_name, context_value| {
                    if (std.meta.stringToEnum(Context, context_name) == null)
                        return invalid(allocator, .unknown_context, "Unknown context '{s}'", .{context_name});
                    if (context_value != .object)
                        return invalid(allocator, .invalid_type, "Context '{s}' must be an object", .{context_name});
                    for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                        if (std.meta.stringToEnum(Action, action_name) == null)
                            return invalid(allocator, .unknown_action, "Unknown action '{s}.{s}'", .{ context_name, action_name });
                        if (value != .array)
                            return invalid(allocator, .invalid_type, "'{s}.{s}' must be an array of key strings", .{ context_name, action_name });
                        for (value.array.items, 0..) |item, index| {
                            if (item != .string)
                                return invalid(allocator, .invalid_type, "'{s}.{s}[{d}]' must be a key string", .{ context_name, action_name, index });
                        }
                    }
                }
            }
            var parsed: std.ArrayList(ParsedBinding) = .empty;
            for (defaults, 0..) |binding, index| {
                for (defaults[0..index]) |previous| {
                    if (previous.context == binding.context and previous.action == binding.action)
                        return invalid(allocator, .duplicate_default, "Duplicate default '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) });
                }
                const override = if (root) |object| blk: {
                    const context = object.get(@tagName(binding.context)) orelse break :blk null;
                    break :blk context.object.get(@tagName(binding.action));
                } else null;
                const count = if (override) |value| value.array.items.len else binding.keys.len;
                for (0..count) |key_index| {
                    const expression = if (override) |value| value.array.items[key_index].string else binding.keys[key_index];
                    if (try appendBinding(allocator, storage, temporary, &parsed, binding.context, binding.action, expression)) |diagnostic|
                        return .{ .invalid = diagnostic };
                }
            }
            if (root) |object| {
                for (object.keys(), object.values()) |context_name, context_value| {
                    const context = std.meta.stringToEnum(Context, context_name).?;
                    for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                        const action = std.meta.stringToEnum(Action, action_name).?;
                        for (defaults) |binding| {
                            if (binding.context == context and binding.action == action) break;
                        } else {
                            for (value.array.items) |item| {
                                if (try appendBinding(allocator, storage, temporary, &parsed, context, action, item.string)) |diagnostic|
                                    return .{ .invalid = diagnostic };
                            }
                        }
                    }
                }
            }
            for (parsed.items, 0..) |a, index| {
                for (parsed.items[index + 1 ..]) |b| {
                    if (a.binding.context != b.binding.context) continue;
                    if (a.binding.action == b.binding.action and a.binding.keys.len == b.binding.keys.len) continue;
                    if (overlaps(a.binding.keys, b.binding.keys))
                        return invalid(allocator, .collision, "Key collision: '{s}' ({s}.{s}) overlaps '{s}' ({s}.{s})", .{
                            a.expression, @tagName(a.binding.context), @tagName(a.binding.action),
                            b.expression, @tagName(b.binding.context), @tagName(b.binding.action),
                        });
                }
            }
            const bindings = try storage.alloc(Binding, parsed.items.len);
            for (bindings, parsed.items) |*binding, source| binding.* = source.binding;
            retained = true;
            return .{ .bindings = .{ .arena = arena, .bindings = bindings } };
        }

        fn invalid(allocator: std.mem.Allocator, kind: Diagnostic.Kind, comptime format: []const u8, args: anytype) std.mem.Allocator.Error!LoadResult {
            return .{ .invalid = try Diagnostic.init(allocator, kind, format, args) };
        }

        fn appendBinding(allocator: std.mem.Allocator, storage: std.mem.Allocator, temporary: std.mem.Allocator, parsed: *std.ArrayList(ParsedBinding), context: Context, action: Action, expression: []const u8) std.mem.Allocator.Error!?Diagnostic {
            var steps = std.mem.tokenizeScalar(u8, expression, ' ');
            var keys: std.ArrayList(KeyPress) = .empty;
            while (steps.next()) |step| {
                const key = KeyPress.parse(step) catch return try Diagnostic.init(allocator, .invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(context), @tagName(action) });
                try keys.append(storage, key);
            }
            if (keys.items.len == 0)
                return try Diagnostic.init(allocator, .invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(context), @tagName(action) });
            try parsed.append(temporary, .{
                .binding = .{ .context = context, .action = action, .keys = try keys.toOwnedSlice(storage) },
                .expression = expression,
            });
            return null;
        }

        /// Matches a KeyPress or a matcher whose matches(KeyPress) method returns bool.
        /// Earlier active contexts win, then defaults and new JSON pairs in declaration order.
        /// Earlier pending bindings take priority.
        /// A mismatch clears pending keys and retries the event as a new binding.
        /// Pending keys in inactive contexts are discarded. Sequences have no timeout.
        pub fn receive(self: *Self, active_contexts: []const Context, matcher: anytype) Result {
            var was_pending = false;
            for (self.bindings) |*binding| {
                if (std.mem.indexOfScalar(Context, active_contexts, binding.context) == null) {
                    binding.next_step = null;
                }
                if (binding.next_step != null) was_pending = true;
            }
            if (was_pending) {
                var pending = false;
                for (active_contexts, 0..) |context, context_index| {
                    if (std.mem.indexOfScalar(Context, active_contexts[0..context_index], context) != null) continue;
                    for (self.bindings) |*binding| {
                        if (binding.context != context) continue;
                        const next = binding.next_step orelse continue;
                        if (!matcher.matches(binding.keys[next])) {
                            binding.next_step = null;
                            continue;
                        }
                        if (next + 1 == binding.keys.len) {
                            binding.next_step = null;
                            if (pending) continue;
                            const action = binding.action;
                            self.cancel();
                            return .{ .action = action };
                        }
                        binding.next_step = next + 1;
                        pending = true;
                    }
                }
                if (pending) return .pending;
                self.cancel();
            }
            var pending = false;
            for (active_contexts, 0..) |context, context_index| {
                if (std.mem.indexOfScalar(Context, active_contexts[0..context_index], context) != null) continue;
                for (self.bindings) |*binding| {
                    if (binding.context != context or !matcher.matches(binding.keys[0])) continue;
                    if (binding.keys.len == 1) {
                        if (pending) continue;
                        const action = binding.action;
                        self.cancel();
                        return .{ .action = action };
                    }
                    binding.next_step = 1;
                    pending = true;
                }
            }
            return if (pending) .pending else .none;
        }

        /// Clears pending keys. Call when focus changes without a key event.
        pub fn cancel(self: *Self) void {
            for (self.bindings) |*binding| binding.next_step = null;
        }

        /// Frees the bindings and input state.
        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined;
        }
    };
}

fn overlaps(a: []const KeyPress, b: []const KeyPress) bool {
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |ak, bk| {
        if (!ak.matches(bk)) return false;
    }
    return true;
}

test "load identifies unknown context and action names" {
    // Enum typos must identify the name users need to correct.
    const Map = Bindings(enum { list, dialog }, enum { down, cancel });
    var context = (try Map.load(testing.allocator, &.{},
        \\{"unknown": {"down": []}}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.unknown_context, context.kind);
    try testing.expect(std.mem.indexOf(u8, context.message, "unknown") != null);

    var action = (try Map.load(testing.allocator, &.{},
        \\{"list": {"unknown": []}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.unknown_action, action.kind);
    try testing.expect(std.mem.indexOf(u8, action.message, "list.unknown") != null);
}

test "load locates wrong JSON value types" {
    // A type error must identify the configuration level that needs correction.
    const Map = Bindings(enum { list }, enum { down });
    var root = (try Map.load(testing.allocator, &.{}, "null")).invalid;
    defer root.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, root.kind);
    try testing.expect(std.mem.indexOf(u8, root.message, "root") != null);

    var context = (try Map.load(testing.allocator, &.{},
        \\{"list": 1}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, context.kind);
    try testing.expect(std.mem.indexOf(u8, context.message, "list") != null);

    var action = (try Map.load(testing.allocator, &.{},
        \\{"list": {"down": 1}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, action.kind);
    try testing.expect(std.mem.indexOf(u8, action.message, "list.down") != null);

    var item = (try Map.load(testing.allocator, &.{},
        \\{"list": {"down": ["j", 1]}}
    )).invalid;
    defer item.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, item.kind);
    try testing.expect(std.mem.indexOf(u8, item.message, "list.down[1]") != null);
}

test "load owns complete invalid key diagnostics" {
    // Diagnostics must survive released inputs and preserve long or escaped expressions.
    const Map = Bindings(enum { list }, enum { down });
    const expression = "Unknown+j" ** 100;
    var default = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{expression} },
    }, null)).invalid;
    defer default.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, default.kind);
    try testing.expect(std.mem.indexOf(u8, default.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, default.message, expression) != null);

    var override = blk: {
        const text = try testing.allocator.dupe(u8,
            \\{"list": {"down": ["g Ctrl+Ctrl+\u0078"]}}
        );
        defer testing.allocator.free(text);
        break :blk (try Map.load(testing.allocator, &.{}, text)).invalid;
    };
    defer override.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, override.kind);
    try testing.expect(std.mem.indexOf(u8, override.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, override.message, "g Ctrl+Ctrl+x") != null);

    var empty = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{" "} },
    }, null)).invalid;
    defer empty.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, empty.kind);
}

test "load reports syntax locations and rejects duplicate fields" {
    // Strict parsing must expose a useful location without accepting ambiguous JSON.
    const Map = Bindings(enum { list }, enum { down });
    var syntax = (try Map.load(testing.allocator, &.{},
        \\{
        \\"list": ?
        \\}
    )).invalid;
    defer syntax.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, syntax.kind);
    try testing.expectEqual(@as(?u64, 2), syntax.line);
    try testing.expectEqual(@as(?u64, 9), syntax.column);

    var context = (try Map.load(testing.allocator, &.{},
        \\{"list": {}, "list": {}}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, context.kind);

    var action = (try Map.load(testing.allocator, &.{},
        \\{"list": {"down": [], "down": []}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, action.kind);

    var comment = (try Map.load(testing.allocator, &.{},
        \\{/* comment */ "list": {}}
    )).invalid;
    defer comment.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, comment.kind);

    var comma = (try Map.load(testing.allocator, &.{},
        \\{"list": {},}
    )).invalid;
    defer comma.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, comma.kind);
}

test "load identifies duplicate defaults" {
    // Repeated pairs make JSON replacement ambiguous.
    const Map = Bindings(enum { list }, enum { down });
    var duplicate = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
        .{ .context = .list, .action = .down, .keys = &.{"Down"} },
    }, null)).invalid;
    defer duplicate.deinit();
    try testing.expectEqual(Diagnostic.Kind.duplicate_default, duplicate.kind);
    try testing.expect(std.mem.indexOf(u8, duplicate.message, "list.down") != null);
}

test "load identifies equivalent key collisions" {
    // Both assignments must be named so users can resolve aliases that overlap.
    const Map = Bindings(enum { list }, enum { down, up });
    var collision = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"Cmd+j"} },
    },
        \\{"list": {"up": ["Super+j"]}}
    )).invalid;
    defer collision.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, collision.kind);
    try testing.expect(std.mem.indexOf(u8, collision.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "list.up") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "Cmd+j") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "Super+j") != null);

    var shift = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"Shift+j"} },
        .{ .context = .list, .action = .up, .keys = &.{"J"} },
    }, null)).invalid;
    defer shift.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, shift.kind);
}

test "load identifies sequence prefix collisions" {
    // A complete binding must not require waiting for a longer binding in the same context.
    const Map = Bindings(enum { list }, enum { top, next });
    var aliases = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{ "g", "g g" } },
    }, null)).invalid;
    defer aliases.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, aliases.kind);
    try testing.expect(std.mem.indexOf(u8, aliases.message, "'g'") != null);
    try testing.expect(std.mem.indexOf(u8, aliases.message, "'g g'") != null);

    var actions = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .next, .keys = &.{"g n"} },
    },
        \\{"list": {"next": ["g"]}}
    )).invalid;
    defer actions.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, actions.kind);
}

test "load owns keys after defaults and JSON are freed" {
    // Applications may release their configuration buffers after loading.
    const Action = enum { down, up };
    const Map = Bindings(enum { list }, Action);
    var bindings = blk: {
        const key = try testing.allocator.dupe(u8, "Ctrl+n");
        defer testing.allocator.free(key);
        const aliases = try testing.allocator.alloc([]const u8, 1);
        defer testing.allocator.free(aliases);
        aliases[0] = key;
        const defaults = try testing.allocator.alloc(Map.Default, 1);
        defer testing.allocator.free(defaults);
        defaults[0] = .{ .context = .list, .action = .down, .keys = aliases };
        const text = try testing.allocator.dupe(u8,
            \\{"list": {"up": ["Ctrl+\u3042"]}}
        );
        defer testing.allocator.free(text);
        break :blk (try Map.load(testing.allocator, defaults, text)).bindings;
    };
    defer bindings.deinit();

    try testing.expectEqual(Action.down, bindings.receive(&.{.list}, KeyPress{
        .key = .{ .character = 'n' },
        .modifiers = .{ .ctrl = true },
    }).action);
    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, KeyPress{
        .key = .{ .character = 'あ' },
        .modifiers = .{ .ctrl = true },
    }).action);
}

test "load frees partial state when allocation fails" {
    // Exhaustion must not leak successful bindings, partial configuration, or diagnostics.
    const Fixture = struct {
        fn load(allocator: std.mem.Allocator) !void {
            const Map = Bindings(enum { global, list }, enum { quit, top });
            var bindings = (try Map.load(allocator, &.{
                .{ .context = .global, .action = .quit, .keys = &.{"q"} },
            },
                \\{"list": {"top": ["Cmd+\u3042 Space", "g g"]}}
            )).bindings;
            defer bindings.deinit();
            var invalid = (try Map.load(allocator, &.{},
                \\{"list": {"top": ["g g", "g"]}}
            )).invalid;
            defer invalid.deinit();
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, Fixture.load, .{});
}
