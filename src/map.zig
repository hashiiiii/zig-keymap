const std = @import("std");
const toml = @import("toml");
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
        pub const Specification = struct { defaults: []const Default, active_contexts: []const []const Context };
        pub const LoadResult = union(enum) { bindings: Self, invalid: Diagnostic };
        const Entry = struct { context: Context, action: Action, keys: []const KeySpec, hint: []const u8 };

        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        entries: []Entry,

        pub fn load(allocator: std.mem.Allocator, specification: Specification, text: ?[]const u8) std.mem.Allocator.Error!LoadResult {
            const arena = try allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(allocator);
            var retained = false;
            defer if (!retained) {
                arena.deinit();
                allocator.destroy(arena);
            };
            const storage = arena.allocator();
            var parse_arena = std.heap.ArenaAllocator.init(allocator);
            defer parse_arena.deinit();
            var root: ?*toml.Table = null;
            if (text) |contents| {
                var info: toml.ErrorInfo = .{};
                root = toml.parseSlice(parse_arena.allocator(), contents, &info) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        var diagnostic = Diagnostic.init(.syntax, "{s}", .{info.message()});
                        diagnostic.line = info.line;
                        diagnostic.column = info.col;
                        return .{ .invalid = diagnostic };
                    },
                };
            }
            if (root) |table| {
                for (table.keys(), table.values()) |context_name, context_value| {
                    const context = std.meta.stringToEnum(Context, context_name) orelse return .{ .invalid = Diagnostic.init(.unknown_context, "Unknown context '{s}'", .{context_name}) };
                    var known = false;
                    for (specification.defaults) |binding| {
                        if (binding.context == context) known = true;
                    }
                    if (!known) return .{ .invalid = Diagnostic.init(.unknown_context, "Unknown context '{s}'", .{context_name}) };
                    if (context_value != .table) return .{ .invalid = Diagnostic.init(.invalid_type, "Context '{s}' must be a table", .{context_name}) };
                    for (context_value.table.keys(), context_value.table.values()) |action_name, value| {
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
                const override = if (root) |table| blk: {
                    const context = table.get(@tagName(binding.context)) orelse break :blk null;
                    break :blk context.table.get(@tagName(binding.action));
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
                    if (!canOverlap(specification.active_contexts, a.context, b.context)) continue;
                    for (a.keys) |ak| {
                        for (b.keys) |bk| {
                            if (ak.equivalent(bk)) return .{ .invalid = Diagnostic.init(.collision, "Key collision between '{s}.{s}' and '{s}.{s}'", .{ @tagName(a.context), @tagName(a.action), @tagName(b.context), @tagName(b.action) }) };
                        }
                    }
                }
            }
            retained = true;
            return .{ .bindings = .{ .allocator = allocator, .arena = arena, .entries = entries } };
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

        pub fn resolve(self: *const Self, contexts: []const Context, matcher: anytype) ?Action {
            for (contexts) |context| {
                for (self.entries) |entry| {
                    if (entry.context != context) continue;
                    for (entry.keys) |key| {
                        if (matcher.matches(key)) return entry.action;
                    }
                }
            }
            return null;
        }

        pub fn keys(self: *const Self, context: Context, action: Action) []const KeySpec {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.keys;
            }
            return &.{};
        }

        pub fn hint(self: *const Self, context: Context, action: Action) []const u8 {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.hint;
            }
            return "";
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.allocator.destroy(self.arena);
            self.* = undefined;
        }
    };
}
