const std = @import("std");
const testing = std.testing;
const key_module = @import("key.zig");
const KeyPress = key_module.KeyPress;
const Platform = key_module.Platform;
const ModifierName = key_module.ModifierName;
const key_lists = @import("keys.zig");
const validation = @import("validation.zig");

/// A problem found while loading bindings.\
/// `message` returns the description.\
/// For JSON syntax errors, `line` and `column` locate the problem.
pub const Diagnostic = struct {
    /// `Kind` identifies why `load` failed.
    pub const Kind = enum {
        /// The JSON is invalid or contains duplicate fields.
        syntax,
        /// The JSON names a context that has no defaults.
        unknown_context,
        /// The JSON names an action that has no default in that context.
        unknown_action,
        /// A JSON value has the wrong type.
        invalid_type,
        /// A default or configured key string is invalid.
        invalid_key,
        /// Equivalent key bindings belong to contexts that can be active together.
        collision,
        /// The defaults repeat a context and action pair.
        invalid_definition,
    };
    /// Which problem `load` found.
    kind: Kind,
    /// JSON syntax line, starting at 1.
    line: ?u32 = null,
    /// JSON syntax column, starting at 1.
    column: ?u32 = null,
    /// Bytes read by `message`.
    buffer: [512]u8 = undefined,
    /// Number of bytes `message` returns.
    length: usize,

    /// Returns the description.\
    /// Keep this diagnostic alive and unchanged while using the text.
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

/// Bindings for one `Context` enum and one `Action` enum.
pub fn Bindings(
    /// An enum of places where bindings apply, such as `global` or `list`.
    comptime Context: type,
    /// An enum of operations, such as `quit` or `move_down`.
    comptime Action: type,
) type {
    return struct {
        const Self = @This();
        /// State for matching key presses in one input stream.
        pub const Receiver = key_lists.Receiver(Context, Action);
        /// `Default` assigns default key strings to one context and action.
        pub const Default = struct {
            /// Context where this default applies.
            context: Context,
            /// Action selected when the keys match.
            action: Action,
            /// Key strings for this action, such as `Down` or `Ctrl+b n`.\
            /// Separate successive presses with spaces.\
            /// Use `Space` to bind the space key.\
            /// An empty slice declares no default keys.
            keys: []const []const u8,
        };
        /// Defaults and the contexts that can be active together.
        pub const Definition = struct {
            /// Context and action pairs, with their default keys.\
            /// JSON can change keys only for these pairs.\
            /// An omitted JSON action keeps its default keys.\
            /// A key string may use `Mod` only when `loadWithOptions` sets `platform`.
            defaults: []const Default,
            /// Contexts that can be active together.\
            /// An empty slice checks key binding conflicts only within one context.\
            /// Each group lists contexts that can be active at the same time.\
            /// `load` rejects conflicting key bindings inside a context and inside each group.\
            /// Contexts that share no group are not compared.\
            /// One context may belong to more than one group.\
            /// A group of one context adds no comparison.\
            /// `receive` selects active contexts from its argument.
            context_groups: []const []const Context,
        };

        /// Checks these defaults at compile time for macOS, Windows, and Linux.\
        /// Invalid keys, duplicate pairs, and overlapping key bindings fail compilation.
        pub fn validateDefaults(comptime definition: Definition) void {
            validation.validateDefaults(Context, Action, definition);
        }

        /// How `Mod` resolves and how `hint` labels are spelled.
        pub const LoadOptions = struct {
            /// Client platform used to resolve `Mod`.\
            /// `null` rejects `Mod` and does not read the build target.
            platform: ?Platform = null,
            /// Modifier names used by `hint`.\
            /// This does not change matching or collision checks.
            modifier_name: ModifierName = .common,
        };
        /// Loaded bindings, or a diagnostic.
        pub const LoadResult = union(enum) {
            /// Owns the loaded bindings. Call `deinit` to free them.
            bindings: Self,
            /// The configuration or defaults are unusable.\
            /// `load` has already freed the bindings.
            invalid: Diagnostic,
        };
        const Entry = struct {
            context: Context,
            action: Action,
            /// Parsed key lists returned by `keys`, including successive presses.
            keys: []const []const KeyPress,
            /// First label returned by `hint`, or an empty string.
            hint: []const u8,
        };

        /// Memory owned by these bindings. `deinit` frees it.
        arena: std.heap.ArenaAllocator,
        /// Loaded bindings. Read them through `keys` and `hint`.
        entries: []Entry,

        /// Creates bindings from `definition` and optional JSON text.\
        /// Pass `null` to keep `definition.defaults`.\
        /// A JSON array replaces that action's default keys.\
        /// `[]` removes every key for that action.\
        /// An omitted action keeps its default keys.\
        /// Key strings must use concrete modifiers. Use `loadWithOptions` for `Mod`.\
        /// Returns `.invalid` for invalid configuration, invalid defaults, or conflicting key bindings.\
        /// The bindings own their memory.\
        /// The caller may free `text` and the definition slices.
        pub fn load(allocator: std.mem.Allocator, definition: Definition, text: ?[]const u8) std.mem.Allocator.Error!LoadResult {
            return loadWithOptions(allocator, definition, text, .{});
        }

        /// Creates bindings with a client platform and modifier names.\
        /// `platform` resolves `Mod` in defaults and JSON before conflict checks.\
        /// A `null` platform accepts only concrete modifiers.\
        /// `modifier_name` changes `hint` labels only.\
        /// JSON replacement rules match `load`.\
        /// Returns `.invalid` for invalid configuration, invalid defaults, or conflicting key bindings.\
        /// The bindings own their keys and labels until `deinit`.\
        /// The caller may free `text` and the definition slices.
        pub fn loadWithOptions(allocator: std.mem.Allocator, definition: Definition, text: ?[]const u8, options: LoadOptions) std.mem.Allocator.Error!LoadResult {
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
                    for (definition.defaults) |binding| {
                        if (binding.context == context) known = true;
                    }
                    if (!known) return .{ .invalid = Diagnostic.init(.unknown_context, "Unknown context '{s}'", .{context_name}) };
                    if (context_value != .object) return .{ .invalid = Diagnostic.init(.invalid_type, "Context '{s}' must be an object", .{context_name}) };
                    for (context_value.object.keys(), context_value.object.values()) |action_name, value| {
                        var allowed = false;
                        for (definition.defaults) |binding| {
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
            const entries = try storage.alloc(Entry, definition.defaults.len);
            for (definition.defaults, 0..) |binding, index| {
                for (definition.defaults[0..index]) |previous| {
                    if (previous.context == binding.context and previous.action == binding.action) return .{ .invalid = Diagnostic.init(.invalid_definition, "Duplicate default '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) }) };
                }
                const override = if (root) |object| blk: {
                    const context = object.get(@tagName(binding.context)) orelse break :blk null;
                    break :blk context.object.get(@tagName(binding.action));
                } else null;
                const count = if (override) |value| value.array.items.len else binding.keys.len;
                const parsed_keys = try storage.alloc([]const KeyPress, count);
                for (parsed_keys, 0..) |*shortcut, key_index| {
                    const expression = if (override) |value| value.array.items[key_index].string else binding.keys[key_index];
                    var steps = key_lists.Steps.init(expression);
                    var parsed: std.ArrayList(KeyPress) = .empty;
                    while (steps.next()) |step| {
                        const parsed_step = if (options.platform) |platform|
                            KeyPress.parseForPlatform(step, platform)
                        else
                            KeyPress.parse(step);
                        const key = parsed_step catch return .{ .invalid = Diagnostic.init(.invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(binding.context), @tagName(binding.action) }) };
                        try parsed.append(storage, key);
                    }
                    if (parsed.items.len == 0) return .{ .invalid = Diagnostic.init(.invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(binding.context), @tagName(binding.action) }) };
                    shortcut.* = try parsed.toOwnedSlice(storage);
                    for (parsed_keys[0..key_index]) |previous| {
                        if (previous.len != shortcut.len and key_lists.overlaps(previous, shortcut.*)) return .{ .invalid = Diagnostic.init(.collision, "Prefix collision for '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) }) };
                    }
                }
                var label_buffer: [96]u8 = undefined;
                var label: std.ArrayList(u8) = .empty;
                if (parsed_keys.len != 0) {
                    for (parsed_keys[0], 0..) |key, step_index| {
                        if (step_index != 0) try label.append(storage, ' ');
                        try label.appendSlice(storage, key.formatWithModifierName(&label_buffer, options.modifier_name));
                    }
                }
                entries[index] = .{ .context = binding.context, .action = binding.action, .keys = parsed_keys, .hint = try label.toOwnedSlice(storage) };
            }
            for (entries, 0..) |a, index| {
                for (entries[index + 1 ..]) |b| {
                    if (!validation.canOverlap(Context, definition.context_groups, a.context, b.context)) continue;
                    for (a.keys) |ak| {
                        for (b.keys) |bk| {
                            if (key_lists.overlaps(ak, bk)) return .{ .invalid = Diagnostic.init(.collision, "Key collision between '{s}.{s}' and '{s}.{s}'", .{ @tagName(a.context), @tagName(a.action), @tagName(b.context), @tagName(b.action) }) };
                        }
                    }
                }
            }
            retained = true;
            return .{ .bindings = .{ .arena = arena, .entries = entries } };
        }

        /// Returns every key binding for the action.\
        /// Each result is one or more key presses.\
        /// The bindings own the result until `deinit`.
        pub fn keys(self: *const Self, context: Context, action: Action) []const []const KeyPress {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.keys;
            }
            return &.{};
        }

        /// Creates independent input state over these bindings.\
        /// `io` supplies the monotonic awake clock for pending input timeouts.\
        /// Use one receiver for each independent input stream.\
        /// Free the receiver before `deinit` on these bindings.
        pub fn receiver(self: *const Self, allocator: std.mem.Allocator, io: std.Io, options: Receiver.Options) std.mem.Allocator.Error!Receiver {
            return Receiver.init(allocator, io, self.entries, options);
        }

        /// Returns the first key binding as a label, or an empty string when the action has no keys.\
        /// The bindings own the result until `deinit`.
        pub fn hint(self: *const Self, context: Context, action: Action) []const u8 {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.hint;
            }
            return "";
        }

        /// Frees memory owned by these bindings.\
        /// After this call, results from `keys` and `hint` are invalid.
        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined;
        }
    };
}

test "load uses default aliases and the first key as the hint" {
    // Applications need every default alias, even though hints show only the first key.
    const Map = Bindings(enum { tree }, enum { move_down, move_up });
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } }},
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();

    try testing.expectEqual(@as(usize, 2), map.keys(.tree, .move_down).len);
    try testing.expectEqual(KeyPress{ .key = .{ .named = .down } }, map.keys(.tree, .move_down)[0][0]);
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1][0]);
    try testing.expectEqualStrings("Down", map.hint(.tree, .move_down));
    try testing.expectEqual(@as(usize, 0), map.keys(.tree, .move_up).len);
    try testing.expectEqualStrings("", map.hint(.tree, .move_up));
}

test "load rejects unknown contexts and actions" {
    // Misspelled or misplaced actions must not silently fall back to defaults.
    const Map = Bindings(enum { tree, dialog }, enum { move_down, cancel });
    const definition: Map.Definition = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    const context = (try Map.load(testing.allocator, definition,
        \\{"unknown": {"move_down": []}}
    )).invalid;
    try testing.expectEqual(Diagnostic.Kind.unknown_context, context.kind);
    try testing.expectEqualStrings("Unknown context 'unknown'", context.message());
    try testing.expectEqual(Diagnostic.Kind.unknown_context, (try Map.load(testing.allocator, definition,
        \\{"dialog": {"cancel": []}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.unknown_action, (try Map.load(testing.allocator, definition,
        \\{"tree": {"unknown_action": []}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.unknown_action, (try Map.load(testing.allocator, definition,
        \\{"tree": {"cancel": []}}
    )).invalid.kind);
}

test "load requires context objects and arrays of strings" {
    // Valid JSON can still have a shape that cannot describe key bindings.
    const Map = Bindings(enum { tree }, enum { move_down });
    const definition: Map.Definition = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, definition, "null")).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, definition, "[]")).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, definition,
        \\{"tree": 1}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, definition,
        \\{"tree": {"move_down": 1}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.invalid_type, (try Map.load(testing.allocator, definition,
        \\{"tree": {"move_down": [1]}}
    )).invalid.kind);
}

test "load rejects invalid default and override keys" {
    // Both application defaults and user overrides must pass key validation.
    const Map = Bindings(enum { tree }, enum { move_down });
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
    const Map = Bindings(enum { tree }, enum { move_down });
    const definition: Map.Definition = .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"j"} }},
        .context_groups = &.{},
    };
    const syntax = (try Map.load(testing.allocator, definition,
        \\{
        \\"tree": ?
        \\}
    )).invalid;
    try testing.expectEqual(Diagnostic.Kind.syntax, syntax.kind);
    try testing.expectEqual(@as(?u32, 2), syntax.line);
    try testing.expectEqual(@as(?u32, 9), syntax.column);
    try testing.expectEqualStrings("Invalid JSON: SyntaxError", syntax.message());
    try testing.expectEqual(Diagnostic.Kind.syntax, (try Map.load(testing.allocator, definition,
        \\{"tree": {}, "tree": {}}
    )).invalid.kind);
    try testing.expectEqual(Diagnostic.Kind.syntax, (try Map.load(testing.allocator, definition,
        \\{"tree": {"move_down": [], "move_down": []}}
    )).invalid.kind);
}

test "load rejects duplicate default actions" {
    // Duplicate actions make override and hint selection ambiguous.
    const Map = Bindings(enum { tree }, enum { move_down });
    try testing.expectEqual(Diagnostic.Kind.invalid_definition, (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"Down"} },
        },
        .context_groups = &.{},
    }, null)).invalid.kind);
}

test "load rejects collisions within a context" {
    // One key must not select two actions in the same context.
    const Map = Bindings(enum { tree }, enum { move_down, move_up });
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
    // Global key bindings must not shadow navigation in a declared active group.
    const Map = Bindings(enum { global, tree }, enum { quit, move_down });
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
    const Map = Bindings(enum { tree }, enum { move_down, move_up });
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
    const Map = Bindings(enum { tree }, enum { move_down });
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
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'n' }, .modifiers = .{ .ctrl = true } }, map.keys(.tree, .move_down)[0][0]);
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1][0]);
    try testing.expectEqualStrings("Ctrl+n", map.hint(.tree, .move_down));
}

test "loadWithOptions expands Mod and uses selected modifier names in hints" {
    // Definitions and JSON must resolve portable modifiers with the same selected platform.
    const Map = Bindings(enum { tree }, enum { move_down, quit });
    const override_text =
        \\{"tree": {"quit": ["Mod+q"]}}
    ;
    var map = (try Map.loadWithOptions(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_down, .keys = &.{"Mod+K"} },
            .{ .context = .tree, .action = .quit, .keys = &.{"q"} },
        },
        .context_groups = &.{},
    }, override_text, .{ .platform = .macos, .modifier_name = .macos })).bindings;
    defer map.deinit();

    try testing.expectEqual(KeyPress{ .key = .{ .character = 'K' }, .modifiers = .{ .super = true } }, map.keys(.tree, .move_down)[0][0]);
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'q' }, .modifiers = .{ .super = true } }, map.keys(.tree, .quit)[0][0]);
    try testing.expectEqualStrings("Command+K", map.hint(.tree, .move_down));
    try testing.expectEqualStrings("Command+q", map.hint(.tree, .quit));
}

test "loadWithOptions detects Mod collisions in overlapping contexts" {
    // Platform expansion must happen before conflict checks for active context groups.
    const Map = Bindings(enum { global, tree }, enum { quit, move_down });
    const override_text =
        \\{"tree": {"move_down": ["Mod+s"]}}
    ;
    const result = try Map.loadWithOptions(testing.allocator, .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{"Ctrl+s"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
        },
        .context_groups = &.{&.{ .global, .tree }},
    }, override_text, .{ .platform = .linux });
    switch (result) {
        .invalid => |diagnostic| try testing.expectEqual(Diagnostic.Kind.collision, diagnostic.kind),
        .bindings => |bindings| {
            var map = bindings;
            defer map.deinit();
            return error.TestUnexpectedResult;
        },
    }
}
