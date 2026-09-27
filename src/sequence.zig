const std = @import("std");
const Keyboard = @import("key.zig").Keyboard;

/// A shortcut contains one or more successive key presses.\
/// `keys` belongs to the bindings that returned this value.
pub const Sequence = struct {
    keys: []const Keyboard,

    /// Equal shortcuts and shortcuts sharing a complete prefix cannot select distinct actions.
    pub fn overlaps(a: Sequence, b: Sequence) bool {
        for (a.keys[0..@min(a.keys.len, b.keys.len)], b.keys[0..@min(a.keys.len, b.keys.len)]) |ak, bk| {
            if (!ak.equivalent(bk)) return false;
        }
        return true;
    }
};

/// Split a shortcut into key expressions. Use `Space` for a space inside a sequence.
pub const Steps = struct {
    tokens: std.mem.TokenIterator(u8, .scalar),
    single: ?[]const u8,

    pub fn init(expression: []const u8) Steps {
        const space = std.mem.indexOfScalar(u8, expression, ' ');
        const literal_space = std.mem.eql(u8, expression, " ") or
            (expression.len >= 2 and space == expression.len - 1 and expression[expression.len - 2] == '+');
        return .{ .tokens = std.mem.tokenizeScalar(u8, expression, ' '), .single = if (literal_space) expression else null };
    }

    pub fn next(self: *Steps) ?[]const u8 {
        if (self.single) |expression| {
            self.single = null;
            self.tokens.index = self.tokens.buffer.len;
            return expression;
        }
        return self.tokens.next();
    }
};

/// Create a resolver for successive events. The application supplies monotonic milliseconds.
pub fn Resolver(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();
        const Candidate = struct {
            context: Context,
            action: Action,
            keys: []const Keyboard,
            next_step: ?usize = null,
        };

        pub const Options = struct {
            /// A timeout restarts after each matched step. `null` disables expiration.
            timeout_ms: ?u64 = 1000,
        };

        pub const Result = union(enum) {
            none,
            pending,
            action: Action,
        };

        allocator: std.mem.Allocator,
        candidates: []Candidate,
        options: Options,
        deadline: ?u64 = null,

        pub fn init(allocator: std.mem.Allocator, entries: anytype, options: Options) std.mem.Allocator.Error!Self {
            var count: usize = 0;
            for (entries) |entry| count += entry.sequences.len;
            const candidates = try allocator.alloc(Candidate, count);
            var index: usize = 0;
            for (entries) |entry| {
                for (entry.sequences) |shortcut| {
                    candidates[index] = .{ .context = entry.context, .action = entry.action, .keys = shortcut.keys };
                    index += 1;
                }
            }
            return .{ .allocator = allocator, .candidates = candidates, .options = options };
        }

        /// Clear any partial sequence without selecting an action.
        pub fn cancel(self: *Self) void {
            for (self.candidates) |*candidate| candidate.next_step = null;
            self.deadline = null;
        }

        /// Expire pending input or remove candidates whose contexts are no longer active.\
        /// Call this when time or active contexts change, even if no key arrives.
        pub fn advance(self: *Self, active_contexts: []const Context, now_ms: u64) Result {
            if (self.deadline) |deadline| {
                if (now_ms >= deadline) {
                    self.cancel();
                    return .none;
                }
            }
            var pending = false;
            for (self.candidates) |*candidate| {
                if (candidate.next_step == null) continue;
                if (std.mem.indexOfScalar(Context, active_contexts, candidate.context) == null) {
                    candidate.next_step = null;
                } else {
                    pending = true;
                }
            }
            if (!pending) self.deadline = null;
            return if (pending) .pending else .none;
        }

        /// Match one event. A mismatch clears the prefix and tries that event as new input.\
        /// Native overlaps use active context order, then default declaration order.\
        /// After `.pending`, the application decides whether to withhold that event from text input.
        pub fn feed(self: *Self, active_contexts: []const Context, matcher: anytype, now_ms: u64) Result {
            if (self.advance(active_contexts, now_ms) == .pending) {
                var pending = false;
                for (active_contexts, 0..) |context, context_index| {
                    if (std.mem.indexOfScalar(Context, active_contexts[0..context_index], context) != null) continue;
                    for (self.candidates) |*candidate| {
                        if (candidate.context != context) continue;
                        const next = candidate.next_step orelse continue;
                        if (!matcher.matches(candidate.keys[next])) {
                            candidate.next_step = null;
                            continue;
                        }
                        if (next + 1 == candidate.keys.len) {
                            const action = candidate.action;
                            self.cancel();
                            return .{ .action = action };
                        }
                        candidate.next_step = next + 1;
                        pending = true;
                    }
                }
                if (pending) {
                    self.restartTimeout(now_ms);
                    return .pending;
                }
                self.cancel();
            }
            var pending = false;
            for (active_contexts, 0..) |context, context_index| {
                if (std.mem.indexOfScalar(Context, active_contexts[0..context_index], context) != null) continue;
                for (self.candidates) |*candidate| {
                    if (candidate.context != context or !matcher.matches(candidate.keys[0])) continue;
                    if (candidate.keys.len == 1) {
                        if (pending) continue;
                        const action = candidate.action;
                        self.cancel();
                        return .{ .action = action };
                    }
                    candidate.next_step = 1;
                    pending = true;
                }
            }
            if (!pending) return .none;
            self.restartTimeout(now_ms);
            return .pending;
        }

        fn restartTimeout(self: *Self, now_ms: u64) void {
            self.deadline = if (self.options.timeout_ms) |timeout| now_ms +| timeout else null;
        }

        /// Free resolver state before freeing the bindings used to create it.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.candidates);
            self.* = undefined;
        }
    };
}
