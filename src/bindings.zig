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
        collision,
    };

    pub const Position = struct {
        line: u64,
        column: u64,
    };

    kind: Kind,
    message: []const u8,
    /// JSON syntax position, starting at 1; null for other configuration errors.
    position: ?Position = null,
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

        /// Loads all bindings from JSON using Context and Action enum names.
        /// Empty arrays and omitted actions leave keys unbound.
        /// Invalid configuration returns .invalid; allocation failures return error.OutOfMemory.
        /// Both payloads own their data; callers may free text after loading.
        /// Rejects sequence prefixes and equivalent keys assigned to different actions within a context.
        /// Backend-specific text or layout overlaps follow context priority and JSON declaration order.
        pub fn load(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!LoadResult {
            var arena = std.heap.ArenaAllocator.init(allocator);
            var retained = false;
            defer if (!retained) arena.deinit();
            const storage = arena.allocator();
            var parse_arena = std.heap.ArenaAllocator.init(allocator);
            defer parse_arena.deinit();
            const temporary = parse_arena.allocator();
            var scanner = std.json.Scanner.initCompleteInput(temporary, text);
            defer scanner.deinit();
            var position: std.json.Diagnostics = .{};
            scanner.enableDiagnostics(&position);
            const root = std.json.parseFromTokenSourceLeaky(std.json.Value, temporary, &scanner, .{}) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    var diagnostic = try Diagnostic.init(allocator, .invalid_json, "Invalid JSON: {s}", .{@errorName(err)});
                    diagnostic.position = .{ .line = position.getLine(), .column = position.getColumn() };
                    return .{ .invalid = diagnostic };
                },
            };
            if (root != .object) return invalid(allocator, .invalid_type, "The JSON root must be an object", .{});
            var parsed: std.ArrayList(ParsedBinding) = .empty;
            for (root.object.keys(), root.object.values()) |context_name, context_value| {
                const context = std.meta.stringToEnum(Context, context_name) orelse
                    return invalid(allocator, .unknown_context, "Unknown context '{s}'", .{context_name});
                if (context_value != .object)
                    return invalid(allocator, .invalid_type, "Context '{s}' must be an object", .{context_name});
                for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                    const action = std.meta.stringToEnum(Action, action_name) orelse
                        return invalid(allocator, .unknown_action, "Unknown action '{s}.{s}'", .{ context_name, action_name });
                    if (value != .array)
                        return invalid(allocator, .invalid_type, "'{s}.{s}' must be an array of key strings", .{ context_name, action_name });
                    for (value.array.items, 0..) |item, index| {
                        if (item != .string)
                            return invalid(allocator, .invalid_type, "'{s}.{s}[{d}]' must be a key string", .{ context_name, action_name, index });
                        var steps = std.mem.tokenizeScalar(u8, item.string, ' ');
                        var keys: std.ArrayList(KeyPress) = .empty;
                        while (steps.next()) |step| {
                            const key = KeyPress.parse(step) catch
                                return invalid(allocator, .invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ item.string, context_name, action_name });
                            try keys.append(storage, key);
                        }
                        if (keys.items.len == 0)
                            return invalid(allocator, .invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ item.string, context_name, action_name });
                        try parsed.append(temporary, .{
                            .binding = .{ .context = context, .action = action, .keys = try keys.toOwnedSlice(storage) },
                            .expression = item.string,
                        });
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

        /// Matches a KeyPress or a matcher whose matches(KeyPress) method returns bool.
        /// Pass only the contexts enabled for the current input, in priority order.
        /// Bindings in omitted contexts are inactive; include shared contexts explicitly.
        /// Earlier active contexts win, then bindings in JSON declaration order.
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
    var context = (try Map.load(testing.allocator,
        \\{"unknown": {"down": []}}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.unknown_context, context.kind);
    try testing.expect(std.mem.indexOf(u8, context.message, "unknown") != null);

    var action = (try Map.load(testing.allocator,
        \\{"list": {"unknown": []}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.unknown_action, action.kind);
    try testing.expect(std.mem.indexOf(u8, action.message, "list.unknown") != null);
}

test "load locates wrong JSON value types" {
    // A type error must identify the configuration level that needs correction.
    const Map = Bindings(enum { list }, enum { down });
    var root = (try Map.load(testing.allocator, "null")).invalid;
    defer root.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, root.kind);
    try testing.expect(std.mem.indexOf(u8, root.message, "root") != null);

    var context = (try Map.load(testing.allocator,
        \\{"list": 1}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, context.kind);
    try testing.expect(std.mem.indexOf(u8, context.message, "list") != null);

    var action = (try Map.load(testing.allocator,
        \\{"list": {"down": 1}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_type, action.kind);
    try testing.expect(std.mem.indexOf(u8, action.message, "list.down") != null);

    var item = (try Map.load(testing.allocator,
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
    var long = (try Map.load(testing.allocator, "{\"list\": {\"down\": [\"" ++ expression ++ "\"]}}")).invalid;
    defer long.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, long.kind);
    try testing.expect(std.mem.indexOf(u8, long.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, long.message, expression) != null);

    var escaped = blk: {
        const text = try testing.allocator.dupe(u8,
            \\{"list": {"down": ["g Ctrl+Ctrl+\u0078"]}}
        );
        defer testing.allocator.free(text);
        break :blk (try Map.load(testing.allocator, text)).invalid;
    };
    defer escaped.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, escaped.kind);
    try testing.expect(std.mem.indexOf(u8, escaped.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, escaped.message, "g Ctrl+Ctrl+x") != null);

    var empty = (try Map.load(testing.allocator,
        \\{"list": {"down": [" "]}}
    )).invalid;
    defer empty.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_key, empty.kind);
}

test "load reports syntax locations and rejects duplicate fields" {
    // Strict parsing must expose a useful location without accepting ambiguous JSON.
    const Map = Bindings(enum { list }, enum { down });
    var syntax = (try Map.load(testing.allocator,
        \\{
        \\"list": ?
        \\}
    )).invalid;
    defer syntax.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, syntax.kind);
    try testing.expectEqual(Diagnostic.Position{ .line = 2, .column = 9 }, syntax.position.?);

    var context = (try Map.load(testing.allocator,
        \\{"list": {}, "list": {}}
    )).invalid;
    defer context.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, context.kind);

    var action = (try Map.load(testing.allocator,
        \\{"list": {"down": [], "down": []}}
    )).invalid;
    defer action.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, action.kind);

    var comment = (try Map.load(testing.allocator,
        \\{/* comment */ "list": {}}
    )).invalid;
    defer comment.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, comment.kind);

    var comma = (try Map.load(testing.allocator,
        \\{"list": {},}
    )).invalid;
    defer comma.deinit();
    try testing.expectEqual(Diagnostic.Kind.invalid_json, comma.kind);
}

test "load identifies equivalent key collisions" {
    // Both assignments must be named so users can resolve aliases that overlap.
    const Map = Bindings(enum { list }, enum { down, up });
    var collision = (try Map.load(testing.allocator,
        \\{"list": {"down": ["Cmd+j"], "up": ["Super+j"]}}
    )).invalid;
    defer collision.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, collision.kind);
    try testing.expect(std.mem.indexOf(u8, collision.message, "list.down") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "list.up") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "Cmd+j") != null);
    try testing.expect(std.mem.indexOf(u8, collision.message, "Super+j") != null);

    var shift = (try Map.load(testing.allocator,
        \\{"list": {"down": ["Shift+j"], "up": ["J"]}}
    )).invalid;
    defer shift.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, shift.kind);
}

test "load identifies sequence prefix collisions" {
    // A complete binding must not require waiting for a longer binding in the same context.
    const Map = Bindings(enum { list }, enum { top, next });
    var aliases = (try Map.load(testing.allocator,
        \\{"list": {"top": ["g", "g g"]}}
    )).invalid;
    defer aliases.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, aliases.kind);
    try testing.expect(std.mem.indexOf(u8, aliases.message, "'g'") != null);
    try testing.expect(std.mem.indexOf(u8, aliases.message, "'g g'") != null);

    var actions = (try Map.load(testing.allocator,
        \\{"list": {"top": ["g g"], "next": ["g"]}}
    )).invalid;
    defer actions.deinit();
    try testing.expectEqual(Diagnostic.Kind.collision, actions.kind);
}

test "load owns keys after JSON is freed" {
    // Applications may release their configuration buffers after loading.
    const Action = enum { down, up };
    const Map = Bindings(enum { list }, Action);
    var bindings = blk: {
        const text = try testing.allocator.dupe(u8,
            \\{"list": {"down": ["Ctrl+n"], "up": ["Ctrl+\u3042"]}}
        );
        defer testing.allocator.free(text);
        break :blk (try Map.load(testing.allocator, text)).bindings;
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
            var bindings = (try Map.load(allocator,
                \\{"global": {"quit": ["q"]}, "list": {"top": ["Cmd+\u3042 Space", "g g"]}}
            )).bindings;
            defer bindings.deinit();
            var invalid = (try Map.load(allocator,
                \\{"list": {"top": ["g g", "g"]}}
            )).invalid;
            defer invalid.deinit();
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, Fixture.load, .{});
}
