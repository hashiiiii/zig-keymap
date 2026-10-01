const std = @import("std");
const KeyPress = @import("key.zig").KeyPress;

/// State for matching key events to actions.\
/// Pending input expires on the monotonic awake clock from `io`.
pub fn Receiver(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();
        const Candidate = struct {
            context: Context,
            action: Action,
            keys: []const KeyPress,
            next_step: ?usize = null,
        };

        /// Timeout between successive key presses.
        pub const Options = struct {
            /// Restarts after each matched step.\
            /// `null` disables expiration.
            timeout_ms: ?u64 = 1000,
        };

        /// Outcome of `receive` or `advance`.
        pub const Result = union(enum) {
            /// No key binding matched.
            none,
            /// More key presses are needed to match a binding.
            pending,
            /// The matched action.
            action: Action,
        };

        /// Owns `candidates`.
        allocator: std.mem.Allocator,
        /// Monotonic awake clock used for pending input timeouts.
        io: std.Io,
        /// Key bindings taken from the configuration.
        candidates: []Candidate,
        /// Timeout settings from `init`.
        options: Options,
        /// Deadline of the current timeout, when one is active.
        deadline: ?std.Io.Timestamp = null,

        /// Creates input state over the bindings' keys.
        pub fn init(allocator: std.mem.Allocator, io: std.Io, entries: anytype, options: Options) std.mem.Allocator.Error!Self {
            var count: usize = 0;
            for (entries) |entry| count += entry.keys.len;
            const candidates = try allocator.alloc(Candidate, count);
            var index: usize = 0;
            for (entries) |entry| {
                for (entry.keys) |shortcut| {
                    candidates[index] = .{ .context = entry.context, .action = entry.action, .keys = shortcut };
                    index += 1;
                }
            }
            return .{ .allocator = allocator, .io = io, .candidates = candidates, .options = options };
        }

        /// Clears a partial sequence without returning an action.
        pub fn cancel(self: *Self) void {
            for (self.candidates) |*candidate| candidate.next_step = null;
            self.deadline = null;
        }

        /// Expires pending input, or drops input whose context is no longer active.\
        /// Call it when the active contexts change and no key arrived.\
        /// Pending input also expires here after `timeout_ms` on the awake clock.
        pub fn advance(self: *Self, active_contexts: []const Context) Result {
            if (self.deadline) |deadline| {
                if (std.Io.Clock.awake.now(self.io).nanoseconds >= deadline.nanoseconds) {
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
        /// A mismatch clears the prefix and tries that event as the start of a key binding.\
        /// When key bindings overlap, earlier active contexts win, then earlier declarations.\
        /// An earlier pending binding wins over a later completed one.\
        /// After `.pending`, the application decides whether to withhold that event from text input.
        pub fn receive(self: *Self, active_contexts: []const Context, matcher: anytype) Result {
            if (self.advance(active_contexts) == .pending) {
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
                            // A native overlap must not interrupt earlier pending input.
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
                    self.restartTimeout();
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
            self.restartTimeout();
            return .pending;
        }

        fn restartTimeout(self: *Self) void {
            const timeout = self.options.timeout_ms orelse {
                self.deadline = null;
                return;
            };
            const now = std.Io.Clock.awake.now(self.io);
            self.deadline = now.addDuration(.fromMilliseconds(@intCast(timeout)));
        }

        /// Frees this receiver. Call it before freeing the bindings.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.candidates);
            self.* = undefined;
        }
    };
}
