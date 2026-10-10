const std = @import("std");
const testing = std.testing;
const KeyPress = @import("key.zig").KeyPress;
const key_lists = @import("keys.zig");

/// JSON key bindings and input state for Context and Action enums.
/// Use one instance per input stream.
pub fn Bindings(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();

        /// Default keys for one context and action.
        pub const Default = struct {
            context: Context,
            action: Action,
            /// Aliases such as Down, Ctrl+n, or g g. Use Space within a sequence.
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

        /// Loads defaults with optional JSON overrides; null keeps all defaults.
        /// Arrays replace aliases, [] disables an action, and omitted actions keep defaults.
        /// Rejects malformed JSON, unknown pairs, invalid keys, duplicate defaults, and collisions within a context.
        /// Owns the parsed keys; callers may free defaults and text after loading.
        pub fn load(allocator: std.mem.Allocator, defaults: []const Default, text: ?[]const u8) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            errdefer arena.deinit();
            const storage = arena.allocator();
            var parse_arena = std.heap.ArenaAllocator.init(allocator);
            defer parse_arena.deinit();
            var root: ?std.json.ObjectMap = null;
            if (text) |contents| {
                var scanner = std.json.Scanner.initCompleteInput(parse_arena.allocator(), contents);
                defer scanner.deinit();
                const value = std.json.parseFromTokenSourceLeaky(std.json.Value, parse_arena.allocator(), &scanner, .{}) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.InvalidJson,
                };
                if (value != .object) return error.InvalidType;
                root = value.object;
            }
            if (root) |object| {
                for (object.keys(), object.values()) |context_name, context_value| {
                    const context = std.meta.stringToEnum(Context, context_name) orelse return error.UnknownContext;
                    var known = false;
                    for (defaults) |binding| {
                        if (binding.context == context) known = true;
                    }
                    if (!known) return error.UnknownContext;
                    if (context_value != .object) return error.InvalidType;
                    for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                        var allowed = false;
                        for (defaults) |binding| {
                            if (binding.context == context and std.mem.eql(u8, @tagName(binding.action), action_name)) allowed = true;
                        }
                        if (!allowed) return error.UnknownAction;
                        if (value != .array) return error.InvalidType;
                        for (value.array.items) |item| {
                            if (item != .string) return error.InvalidType;
                        }
                    }
                }
            }
            var bindings: std.ArrayList(Binding) = .empty;
            for (defaults, 0..) |binding, index| {
                for (defaults[0..index]) |previous| {
                    if (previous.context == binding.context and previous.action == binding.action) return error.DuplicateDefault;
                }
                const override = if (root) |object| blk: {
                    const context = object.get(@tagName(binding.context)) orelse break :blk null;
                    break :blk context.object.get(@tagName(binding.action));
                } else null;
                const count = if (override) |value| value.array.items.len else binding.keys.len;
                for (0..count) |key_index| {
                    const expression = if (override) |value| value.array.items[key_index].string else binding.keys[key_index];
                    var steps = key_lists.Steps.init(expression);
                    var keys: std.ArrayList(KeyPress) = .empty;
                    while (steps.next()) |step| try keys.append(storage, try KeyPress.parse(step));
                    if (keys.items.len == 0) return error.InvalidKey;
                    try bindings.append(storage, .{
                        .context = binding.context,
                        .action = binding.action,
                        .keys = try keys.toOwnedSlice(storage),
                    });
                }
            }
            for (bindings.items, 0..) |a, index| {
                for (bindings.items[index + 1 ..]) |b| {
                    if (a.context != b.context) continue;
                    if (a.action == b.action and a.keys.len == b.keys.len) continue;
                    if (key_lists.overlaps(a.keys, b.keys)) return error.Collision;
                }
            }
            const owned = try bindings.toOwnedSlice(storage);
            return .{ .arena = arena, .bindings = owned };
        }

        /// Matches a KeyPress or a matcher whose matches(KeyPress) method returns bool.
        /// Earlier active contexts win, then earlier defaults; earlier pending bindings take priority.
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

test "load rejects unknown context and action pairs" {
    // Misspelled or undeclared pairs must not silently keep defaults.
    const Map = Bindings(enum { list, dialog }, enum { down, cancel });
    const defaults: []const Map.Default = &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
    };
    try testing.expectError(error.UnknownContext, Map.load(testing.allocator, defaults,
        \\{"unknown": {"down": []}}
    ));
    try testing.expectError(error.UnknownContext, Map.load(testing.allocator, defaults,
        \\{"dialog": {"cancel": []}}
    ));
    try testing.expectError(error.UnknownAction, Map.load(testing.allocator, defaults,
        \\{"list": {"unknown": []}}
    ));
    try testing.expectError(error.UnknownAction, Map.load(testing.allocator, defaults,
        \\{"list": {"cancel": []}}
    ));
}

test "load requires objects and arrays of key strings" {
    // Valid JSON must still describe keys for declared actions.
    const Map = Bindings(enum { list }, enum { down });
    const defaults: []const Map.Default = &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
    };
    try testing.expectError(error.InvalidType, Map.load(testing.allocator, defaults, "null"));
    try testing.expectError(error.InvalidType, Map.load(testing.allocator, defaults, "[]"));
    try testing.expectError(error.InvalidType, Map.load(testing.allocator, defaults,
        \\{"list": 1}
    ));
    try testing.expectError(error.InvalidType, Map.load(testing.allocator, defaults,
        \\{"list": {"down": 1}}
    ));
    try testing.expectError(error.InvalidType, Map.load(testing.allocator, defaults,
        \\{"list": {"down": [1]}}
    ));
}

test "load rejects invalid default and override keys" {
    // Defaults and overrides both need validation before accepting input.
    const Map = Bindings(enum { list }, enum { down });
    try testing.expectError(error.InvalidKey, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"Unknown+j"} },
    }, null));
    try testing.expectError(error.InvalidKey, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
    },
        \\{"list": {"down": ["Ctrl+Ctrl+x"]}}
    ));
    try testing.expectError(error.InvalidKey, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{""} },
    }, null));
}

test "load rejects malformed JSON and duplicate fields" {
    // Duplicate fields, comments, and trailing commas can hide configuration mistakes.
    const Map = Bindings(enum { list }, enum { down });
    const defaults: []const Map.Default = &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
    };
    try testing.expectError(error.InvalidJson, Map.load(testing.allocator, defaults,
        \\{"list": ?}
    ));
    try testing.expectError(error.InvalidJson, Map.load(testing.allocator, defaults,
        \\{"list": {}, "list": {}}
    ));
    try testing.expectError(error.InvalidJson, Map.load(testing.allocator, defaults,
        \\{"list": {"down": [], "down": []}}
    ));
    try testing.expectError(error.InvalidJson, Map.load(testing.allocator, defaults,
        \\{/* comment */ "list": {}}
    ));
    try testing.expectError(error.InvalidJson, Map.load(testing.allocator, defaults,
        \\{"list": {},}
    ));
}

test "load rejects duplicate defaults" {
    // Repeated pairs make JSON replacement ambiguous.
    const Map = Bindings(enum { list }, enum { down });
    try testing.expectError(error.DuplicateDefault, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"j"} },
        .{ .context = .list, .action = .down, .keys = &.{"Down"} },
    }, null));
}

test "load rejects equivalent keys within one context" {
    // Aliases must not assign one key to different actions.
    const Map = Bindings(enum { list }, enum { down, up });
    try testing.expectError(error.Collision, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"Cmd+j"} },
        .{ .context = .list, .action = .up, .keys = &.{"k"} },
    },
        \\{"list": {"up": ["Super+j"]}}
    ));
    try testing.expectError(error.Collision, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{"Shift+j"} },
        .{ .context = .list, .action = .up, .keys = &.{"J"} },
    }, null));
}

test "load rejects sequence prefixes" {
    // A complete binding must not require waiting for a longer binding in the same context.
    const Map = Bindings(enum { list }, enum { top, next });
    try testing.expectError(error.Collision, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{ "g", "g g" } },
    }, null));
    try testing.expectError(error.Collision, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .next, .keys = &.{"g n"} },
    },
        \\{"list": {"next": ["g"]}}
    ));
    try testing.expectError(error.Collision, Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .next, .keys = &.{"g g"} },
    }, null));
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
        const defaults = try testing.allocator.alloc(Map.Default, 2);
        defer testing.allocator.free(defaults);
        defaults[0] = .{ .context = .list, .action = .down, .keys = aliases };
        defaults[1] = .{ .context = .list, .action = .up, .keys = &.{} };
        const text = try testing.allocator.dupe(u8,
            \\{"list": {"up": ["Ctrl+\u3042"]}}
        );
        defer testing.allocator.free(text);
        break :blk try Map.load(testing.allocator, defaults, text);
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
