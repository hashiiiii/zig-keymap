const std = @import("std");
const testing = std.testing;
const key_module = @import("key.zig");
const Keyboard = key_module.Keyboard;
const Platform = key_module.Platform;
const DisplayStyle = key_module.DisplayStyle;
const sequence = @import("sequence.zig");

/// `Diagnostic` describes a problem in the JSON configuration or keymap definition.\
/// Read `message()` for the description.\
/// For JSON syntax errors, `line` and `column` give the location when available.
pub const Diagnostic = struct {
    /// `Kind` identifies the problem that `load` found.
    pub const Kind = enum {
        /// The JSON is invalid or contains duplicate fields.
        syntax,
        /// The JSON names a context with no declared bindings.
        unknown_context,
        /// The JSON names an action not declared for its context.
        unknown_action,
        /// A JSON value has the wrong type.
        invalid_type,
        /// A default key string or a key string from the configuration is invalid.
        invalid_key,
        /// Two bindings use equivalent keys in contexts that can be active together.
        collision,
        /// The defaults repeat a context and action pair.
        invalid_definition,
    };
    /// This field identifies the problem.
    kind: Kind,
    /// This field holds the JSON line number when available. Line numbers start at 1.
    line: ?u32 = null,
    /// This field holds the JSON column number when available. Column numbers start at 1.
    column: ?u32 = null,
    /// This buffer stores the diagnostic message.
    buffer: [512]u8 = undefined,
    /// This field holds the number of message bytes in `buffer`.
    length: usize,

    /// `message` returns the text stored in this diagnostic.\
    /// While you use the text, keep this diagnostic alive and unchanged.
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

/// `Bindings` creates a type for the application's `Context` and `Action` enums.\
/// A binding assigns keys to a context and action.\
/// Each binding holds a list of `Keyboard` values.\
/// Use `load()` to create bindings.\
/// Use `resolve()` to select an action.\
/// Use `deinit()` to free the memory for the bindings.
pub fn Bindings(
    /// Use an enum of application contexts, such as global, list, or dialog.
    comptime Context: type,
    /// Use an enum of application actions, such as quit or move_down.
    comptime Action: type,
) type {
    return struct {
        const Self = @This();
        /// `SequenceResolver` tracks pending key presses without owning the loaded shortcuts.
        pub const SequenceResolver = sequence.Resolver(Context, Action);
        /// `Default` assigns default key strings to one context and action.
        pub const Default = struct {
            /// The binding applies to this context.
            context: Context,
            /// A key match selects this action.
            action: Action,
            /// Each string contains a key or successive keys separated by spaces, such as `Down` or `Ctrl+b n`.\
            /// Use `Space` for a space inside a sequence.\
            /// An empty slice declares an action with no default keys.
            keys: []const []const u8,
        };
        /// `Definition` declares bindings, their defaults, and the contexts that can be active together.
        pub const Definition = struct {
            /// This list declares context and action pairs with their default keys.\
            /// JSON configuration can change keys only for these pairs.\
            /// Actions missing from the JSON keep their default keys.\
            /// Use `Mod` only when `loadWithOptions` selects a platform.
            defaults: []const Default,
            /// Each group lists contexts that can be active together.\
            /// `load()` checks for key conflicts between bindings in these contexts.\
            /// It always checks for conflicts within each context.\
            /// Pass the current active contexts to `resolve()`.
            context_groups: []const []const Context,
        };
        /// `LoadOptions` selects how portable modifiers are resolved and how hints are displayed.
        pub const LoadOptions = struct {
            /// The client platform used to resolve `Mod`.\
            /// `null` leaves keys concrete-only, so a `Mod` expression is invalid.\
            /// Select the client keyboard platform explicitly; the build target may differ.
            platform: ?Platform = null,
            /// The modifier names used for `hint()` labels.\
            /// This setting does not change matching or collision checks.
            display_style: DisplayStyle = .common,
        };
        /// `LoadResult` contains loaded bindings or a diagnostic that describes invalid configuration or defaults.
        pub const LoadResult = union(enum) {
            /// This value owns the loaded bindings. Use `deinit()` to free their memory.
            bindings: Self,
            /// This diagnostic describes a configuration or definition problem.\
            /// `load()` frees all memory for the bindings before it returns this value.
            invalid: Diagnostic,
        };
        /// `Entry` stores one loaded binding.
        const Entry = struct {
            /// The binding applies to this context.
            context: Context,
            /// A key match selects this action.
            action: Action,
            /// These single-key shortcuts preserve the `keys()` API.
            keys: []const Keyboard,
            /// These shortcuts include single keys and successive key presses.
            sequences: []const sequence.Sequence,
            /// This field holds the first key label, or an empty string if the action has no keys.
            hint: []const u8,
        };

        /// The bindings own this memory. `deinit()` frees it.
        arena: std.heap.ArenaAllocator,
        /// This list stores the loaded bindings.\
        /// Use `keys()`, `hint()`, and `resolve()` to read them.
        entries: []Entry,

        /// `load` creates bindings from `definition` and optional JSON configuration.\
        /// To use the keys in `definition.defaults`, pass `null`.\
        /// A JSON array replaces the default keys for that action.\
        /// `[]` removes all keys for that action.\
        /// Actions missing from the JSON keep their default keys.\
        /// Keys must use concrete modifier names; use `loadWithOptions` to enable `Mod`.
        ///
        /// `load` returns `.invalid` for invalid configuration, invalid defaults, or key conflicts.\
        /// If memory allocation fails, `load` returns `error.OutOfMemory`.
        ///
        /// The loaded bindings own their memory.\
        /// After this call, you can free the input text and definition slices.
        pub fn load(allocator: std.mem.Allocator, definition: Definition, text: ?[]const u8) std.mem.Allocator.Error!LoadResult {
            return loadWithOptions(allocator, definition, text, .{});
        }

        /// `loadWithOptions` creates bindings with an explicit platform and hint display style.\
        /// The selected platform resolves `Mod` in both defaults and JSON overrides before collision checks.\
        /// The display style affects only labels returned by `hint()`.\
        /// A `null` platform keeps parsing concrete-only; it never infers a platform from the build target.\
        /// Omitted JSON actions keep their defaults, while `[]` disables the action.
        ///
        /// `loadWithOptions` returns `.invalid` for invalid configuration, invalid defaults, or key conflicts.\
        /// If memory allocation fails, it returns `error.OutOfMemory`.
        ///
        /// The loaded bindings own their keys and labels until `deinit()`.\
        /// After this call, you can free the input text and definition slices.
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
                const shortcuts = try storage.alloc(sequence.Sequence, count);
                var single_keys: std.ArrayList(Keyboard) = .empty;
                for (shortcuts, 0..) |*shortcut, key_index| {
                    const expression = if (override) |value| value.array.items[key_index].string else binding.keys[key_index];
                    var steps = sequence.Steps.init(expression);
                    var parsed: std.ArrayList(Keyboard) = .empty;
                    while (steps.next()) |step| {
                        const parsed_step = if (options.platform) |platform|
                            Keyboard.parseForPlatform(step, platform)
                        else
                            Keyboard.parse(step);
                        const key = parsed_step catch return .{ .invalid = Diagnostic.init(.invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(binding.context), @tagName(binding.action) }) };
                        try parsed.append(storage, key);
                    }
                    if (parsed.items.len == 0) return .{ .invalid = Diagnostic.init(.invalid_key, "Invalid key '{s}' for '{s}.{s}'", .{ expression, @tagName(binding.context), @tagName(binding.action) }) };
                    shortcut.* = .{ .keys = try parsed.toOwnedSlice(storage) };
                    if (shortcut.keys.len == 1) try single_keys.append(storage, shortcut.keys[0]);
                    for (shortcuts[0..key_index]) |previous| {
                        if (previous.keys.len != shortcut.keys.len and previous.overlaps(shortcut.*)) return .{ .invalid = Diagnostic.init(.collision, "Prefix collision for '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) }) };
                    }
                }
                var label_buffer: [96]u8 = undefined;
                var label: std.ArrayList(u8) = .empty;
                if (shortcuts.len != 0) {
                    for (shortcuts[0].keys, 0..) |key, step_index| {
                        if (step_index != 0) try label.append(storage, ' ');
                        try label.appendSlice(storage, key.formatWithStyle(&label_buffer, options.display_style));
                    }
                }
                entries[index] = .{ .context = binding.context, .action = binding.action, .keys = try single_keys.toOwnedSlice(storage), .sequences = shortcuts, .hint = try label.toOwnedSlice(storage) };
            }
            for (entries, 0..) |a, index| {
                for (entries[index + 1 ..]) |b| {
                    if (!canOverlap(definition.context_groups, a.context, b.context)) continue;
                    for (a.sequences) |ak| {
                        for (b.sequences) |bk| {
                            if (ak.overlaps(bk)) return .{ .invalid = Diagnostic.init(.collision, "Key collision between '{s}.{s}' and '{s}.{s}'", .{ @tagName(a.context), @tagName(a.action), @tagName(b.context), @tagName(b.action) }) };
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

        /// `resolve` returns the first matching action, or `null` if no binding matches.\
        /// Pass the current active contexts in `active_contexts`.\
        /// `resolve` checks contexts in that order, then bindings in the order of `definition.defaults`.\
        /// A matcher must provide `matches(Keyboard) bool`.\
        /// For libvaxis keys, use `vaxisMatcher`.
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

        /// `keys` returns single-key shortcuts. Use `sequences()` to include successive key presses.\
        /// The bindings own the result. It remains valid until `deinit()`.\
        /// Do not free it separately.
        pub fn keys(self: *const Self, context: Context, action: Action) []const Keyboard {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.keys;
            }
            return &.{};
        }

        /// Return every configured shortcut, including successive key presses.\
        /// The bindings own the returned sequences and their keys until `deinit()`.
        pub fn sequences(self: *const Self, context: Context, action: Action) []const sequence.Sequence {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.sequences;
            }
            return &.{};
        }

        /// Create state for successive events. Free it before `bindings.deinit()`.\
        /// `resolve()` remains available for single-key shortcuts.
        pub fn sequenceResolver(self: *const Self, allocator: std.mem.Allocator, options: SequenceResolver.Options) std.mem.Allocator.Error!SequenceResolver {
            return SequenceResolver.init(allocator, self.entries, options);
        }

        /// `hint` returns the first configured key as a label, or an empty string if the action has no keys.\
        /// The bindings own the result. It remains valid until `deinit()`.\
        /// Do not free it separately.
        pub fn hint(self: *const Self, context: Context, action: Action) []const u8 {
            for (self.entries) |entry| {
                if (entry.context == context and entry.action == action) return entry.hint;
            }
            return "";
        }

        /// `deinit` frees all memory that these bindings own.\
        /// After this call, do not use the results from `keys()` or `hint()`.
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
    try testing.expectEqual(Keyboard{ .key = .{ .named = .down } }, map.keys(.tree, .move_down)[0]);
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1]);
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
    // Global shortcuts must not shadow navigation in a declared active group.
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
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'n' }, .modifiers = .{ .ctrl = true } }, map.keys(.tree, .move_down)[0]);
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'j' } }, map.keys(.tree, .move_down)[1]);
    try testing.expectEqualStrings("Ctrl+n", map.hint(.tree, .move_down));
}

test "loadWithOptions expands Mod in defaults and overrides and styles hints" {
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
    }, override_text, .{ .platform = .macos, .display_style = .macos })).bindings;
    defer map.deinit();

    try testing.expectEqual(Keyboard{ .key = .{ .character = 'K' }, .modifiers = .{ .super = true } }, map.keys(.tree, .move_down)[0]);
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'q' }, .modifiers = .{ .super = true } }, map.keys(.tree, .quit)[0]);
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
