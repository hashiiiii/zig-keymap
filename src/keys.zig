const std = @import("std");
const KeyPress = @import("key.zig").KeyPress;

/// True when the key lists are equal or one is a prefix of the other.
pub fn overlaps(a: []const KeyPress, b: []const KeyPress) bool {
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |ak, bk| {
        if (!ak.equivalent(bk)) return false;
    }
    return true;
}

/// Splits a key binding into key expressions.\
/// Use `Space` for a space inside a sequence.
pub const Steps = struct {
    /// Remaining words in the key binding string.
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
