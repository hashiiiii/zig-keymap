const std = @import("std");
const Keyboard = @import("key.zig").Keyboard;

/// One shortcut: one or more presses, in order.\
/// The bindings that returned this value own `keys`.
pub const Sequence = struct {
    /// Presses in order. A single press is one shortcut.
    keys: []const Keyboard,

    /// True when the shortcuts are equal or one is a prefix of the other.
    pub fn overlaps(a: Sequence, b: Sequence) bool {
        for (a.keys[0..@min(a.keys.len, b.keys.len)], b.keys[0..@min(a.keys.len, b.keys.len)]) |ak, bk| {
            if (!ak.equivalent(bk)) return false;
        }
        return true;
    }
};

/// Splits a shortcut into key expressions.\
/// Use `Space` for a space inside a sequence.
pub const Steps = struct {
    /// Remaining words in the shortcut string.
    tokens: std.mem.TokenIterator(u8, .scalar),
    /// Set when the whole expression is a space key.
    single: ?[]const u8,

    /// Splits `expression` on spaces and keeps a literal space key intact.
    pub fn init(expression: []const u8) Steps {
        const space = std.mem.indexOfScalar(u8, expression, ' ');
        const literal_space = std.mem.eql(u8, expression, " ") or
            (expression.len >= 2 and space == expression.len - 1 and expression[expression.len - 2] == '+');
        return .{ .tokens = std.mem.tokenizeScalar(u8, expression, ' '), .single = if (literal_space) expression else null };
    }

    /// Returns the next key expression, or `null` when none remain.
    pub fn next(self: *Steps) ?[]const u8 {
        if (self.single) |expression| {
            self.single = null;
            self.tokens.index = self.tokens.buffer.len;
            return expression;
        }
        return self.tokens.next();
    }
};

/// State for matching key events to actions.\
/// `now_ms` is monotonic milliseconds supplied by the application.
pub fn Resolver(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();
        const Candidate = struct {
            context: Context,
            action: Action,
            keys: []const Keyboard,
            next_step: ?usize = null,
        };

        /// Timeout for a partial shortcut.
        pub const Options = struct {
            /// Restarts after each matched step.\
            /// `null` disables expiration.
            timeout_ms: ?u64 = 1000,
        };

        /// Outcome of `feed` or `advance`.
        pub const Result = union(enum) {
            /// No shortcut matched.
            none,
            /// A shortcut is incomplete.
            pending,
            /// The matched action.
            action: Action,
        };

        /// Owns `candidates`.
        allocator: std.mem.Allocator,
        /// Shortcuts taken from the bindings.
        candidates: []Candidate,
        /// Timeout settings from `init`.
        options: Options,
        /// Deadline of the current timeout, when one is active.
        deadline: ?u64 = null,

        /// Creates a resolver over the bindings' shortcuts.
        pub fn init(allocator: std.mem.Allocator, entries: anytype, options: Options) std.mem.Allocator.Error!Self {
            var count: usize = 0;
            for (entries) |entry| count += entry.keys.len;
            const candidates = try allocator.alloc(Candidate, count);
            var index: usize = 0;
            for (entries) |entry| {
                for (entry.keys) |shortcut| {
                    candidates[index] = .{ .context = entry.context, .action = entry.action, .keys = shortcut.keys };
                    index += 1;
                }
            }
            return .{ .allocator = allocator, .candidates = candidates, .options = options };
        }

        /// Clears a partial sequence without returning an action.
        pub fn cancel(self: *Self) void {
            for (self.candidates) |*candidate| candidate.next_step = null;
            self.deadline = null;
        }

        /// Expires pending input, or drops input whose context is no longer active.\
        /// Call it when time or the active contexts change and no key arrived.
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

        /// Matches one event.\
        /// A mismatch clears the prefix and tries that event as a new shortcut.\
        /// When shortcuts overlap, earlier active contexts win, then earlier declarations.\
        /// An earlier pending shortcut wins over a later completed one.\
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
                            candidate.next_step = null;
                            // A native overlap must not interrupt an earlier pending shortcut.
                            if (pending) continue;
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

        /// Frees this resolver. Call it before freeing the bindings.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.candidates);
            self.* = undefined;
        }
    };
}
