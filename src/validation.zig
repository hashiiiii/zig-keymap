const std = @import("std");
const key_module = @import("key.zig");
const Keyboard = key_module.Keyboard;
const Platform = key_module.Platform;
const sequence = @import("sequence.zig");

/// `canOverlap` reports whether `a` and `b` can be active at the same time.
/// Contexts always overlap themselves, even when no group names them.
pub fn canOverlap(comptime Context: type, groups: []const []const Context, a: Context, b: Context) bool {
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

/// `validateDefaults` checks application defaults for every supported client platform.
pub fn validateDefaults(comptime Context: type, comptime Action: type, comptime definition: anytype) void {
    comptime {
        // Parsing each binding for three platforms exceeds Zig's default budget in ordinary maps.
        @setEvalBranchQuota(100_000);
        _ = Action;
        const duplicate = findDuplicateDefault(Context, definition);
        if (duplicate) |message| @compileError(message);

        const failures = .{
            validatePlatform(Context, definition, .macos),
            validatePlatform(Context, definition, .windows),
            validatePlatform(Context, definition, .linux),
        };
        const message = joinDiagnostics(failures);
        if (message.len != 0) @compileError(message);
    }
}

fn findDuplicateDefault(comptime Context: type, comptime definition: anytype) ?[]const u8 {
    _ = Context;
    for (definition.defaults, 0..) |binding, index| {
        for (definition.defaults[0..index]) |previous| {
            if (previous.context == binding.context and previous.action == binding.action) {
                return std.fmt.comptimePrint("Duplicate default '{s}.{s}'", .{ @tagName(binding.context), @tagName(binding.action) });
            }
        }
    }
    return null;
}

fn validatePlatform(comptime Context: type, comptime definition: anytype, comptime platform: Platform) ?[]const u8 {
    for (definition.defaults) |binding| {
        for (binding.keys) |expression| {
            const parsed = parseShortcut(expression, platform);
            if (parsed.invalid_step) |step| {
                return std.fmt.comptimePrint("Invalid key step '{s}' in default '{s}.{s}' on {s}", .{
                    step,
                    @tagName(binding.context),
                    @tagName(binding.action),
                    @tagName(platform),
                });
            }
        }
    }

    for (definition.defaults, 0..) |binding, binding_index| {
        for (binding.keys, 0..) |expression, expression_index| {
            const current = parseShortcut(expression, platform);
            for (binding.keys[0..expression_index]) |previous_expression| {
                const previous = parseShortcut(previous_expression, platform);
                if (previous.len != current.len and sequence.Sequence.overlaps(asSequence(previous), asSequence(current))) {
                    return std.fmt.comptimePrint("Shortcut prefix collision between '{s}.{s}' shortcuts '{s}' and '{s}' on {s}", .{
                        @tagName(binding.context),
                        @tagName(binding.action),
                        previous_expression,
                        expression,
                        @tagName(platform),
                    });
                }
            }

            for (definition.defaults[binding_index + 1 ..]) |other| {
                if (!canOverlap(Context, definition.context_groups, binding.context, other.context)) continue;
                for (other.keys) |other_expression| {
                    const other_shortcut = parseShortcut(other_expression, platform);
                    if (sequence.Sequence.overlaps(asSequence(current), asSequence(other_shortcut))) {
                        return std.fmt.comptimePrint("Key collision between '{s}.{s}' shortcut '{s}' and '{s}.{s}' shortcut '{s}' on {s}", .{
                            @tagName(binding.context),
                            @tagName(binding.action),
                            expression,
                            @tagName(other.context),
                            @tagName(other.action),
                            other_expression,
                            @tagName(platform),
                        });
                    }
                }
            }
        }
    }
    return null;
}

fn ParsedShortcut(comptime capacity: usize) type {
    return struct {
        keys: [capacity]Keyboard = undefined,
        len: usize = 0,
        invalid_step: ?[]const u8 = null,
    };
}

fn parseShortcut(comptime expression: []const u8, comptime platform: Platform) ParsedShortcut(expression.len) {
    var result: ParsedShortcut(expression.len) = .{};
    var steps = sequence.Steps.init(expression);
    while (steps.next()) |step| {
        const key = Keyboard.parseForPlatform(step, platform) catch {
            result.invalid_step = step;
            return result;
        };
        result.keys[result.len] = key;
        result.len += 1;
    }
    if (result.len == 0) result.invalid_step = expression;
    return result;
}

fn asSequence(shortcut: anytype) sequence.Sequence {
    return .{ .keys = shortcut.keys[0..shortcut.len] };
}

fn joinDiagnostics(diagnostics: anytype) []const u8 {
    var result: []const u8 = "";
    inline for (diagnostics) |diagnostic| {
        if (diagnostic) |message| {
            result = if (result.len == 0)
                message
            else
                std.fmt.comptimePrint("{s}\n{s}", .{ result, message });
        }
    }
    return result;
}
