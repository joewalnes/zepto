// Complete Zig example demonstrating syntax highlighting
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

// Constants
const MAX_SIZE: usize = 1024;
const PI: f64 = 3.14159265358979;

// Error set
const FileError = error{
    NotFound,
    AccessDenied,
    IoError,
};

// Struct definition
const Point = struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub fn init(x: f32, y: f32) Self {
        return Self{ .x = x, .y = y };
    }

    pub fn distance(self: Self, other: Self) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

// Union type
const Value = union(enum) {
    int: i64,
    float: f64,
    boolean: bool,
    none: void,

    pub fn format(self: Value) void {
        switch (self) {
            .int => |i| std.debug.print("int: {}\n", .{i}),
            .float => |f| std.debug.print("float: {d}\n", .{f}),
            .boolean => |b| std.debug.print("bool: {}\n", .{b}),
            .none => std.debug.print("none\n", .{}),
        }
    }
};

// Enum
const Status = enum(u8) {
    pending = 0,
    active = 1,
    completed = 2,

    pub fn isActive(self: Status) bool {
        return self == .active;
    }
};

// Generic function
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

// Function with error handling
fn divide(a: i32, b: i32) !i32 {
    if (b == 0) return error.DivisionByZero;
    return @divTrunc(a, b);
}

// Async function
fn asyncFetch(url: []const u8) ![]u8 {
    _ = url;
    return error.NotImplemented;
}

// Comptime function
fn fibonacci(comptime n: u32) u32 {
    if (n <= 1) return n;
    return comptime fibonacci(n - 1) + fibonacci(n - 2);
}

// Main function
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Variable declarations
    const count: i32 = 42;
    var mutable: i32 = 0;
    const name: []const u8 = "Zig";
    const float_val: f64 = 3.14159;
    const flag: bool = true;
    const char: u8 = 'A';

    // Numbers
    const hex: u32 = 0xFF;
    const binary: u8 = 0b1010_1010;
    const octal: u32 = 0o777;

    // Arrays and slices
    var array = [_]i32{ 1, 2, 3, 4, 5 };
    const slice: []i32 = array[0..3];

    // Pointer operations
    const ptr: *i32 = &mutable;
    ptr.* = 100;

    // Optional type
    var optional: ?i32 = null;
    optional = 42;
    if (optional) |value| {
        try stdout.print("Value: {}\n", .{value});
    }

    // Error union
    const result: FileError!i32 = divide(10, 2);
    const value = result catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };

    // Control flow
    if (count > 0) {
        try stdout.print("Positive\n", .{});
    } else if (count < 0) {
        try stdout.print("Negative\n", .{});
    } else {
        try stdout.print("Zero\n", .{});
    }

    // Switch expression
    const status = Status.active;
    const message = switch (status) {
        .pending => "Waiting...",
        .active => "Running",
        .completed => "Done",
    };

    // Loops
    for (array) |item, index| {
        if (index == 2) continue;
        try stdout.print("{}: {}\n", .{ index, item });
    }

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        if (i == 5) continue;
        if (i == 8) break;
    }

    // Defer
    defer try stdout.print("Cleanup\n", .{});

    // Errdefer
    errdefer try stdout.print("Error occurred\n", .{});

    // Inline assembly
    const result_asm = asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@as(usize, 1)),
        : "rcx", "r11", "memory"
    );
    _ = result_asm;

    // Comptime evaluation
    const fib10 = comptime fibonacci(10);
    try stdout.print("Fib(10) = {}\n", .{fib10});

    // Struct usage
    const p1 = Point.init(0, 0);
    const p2 = Point.init(3, 4);
    const dist = p1.distance(p2);
    try stdout.print("Distance: {d}\n", .{dist});

    // Memory allocation
    const buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);

    try stdout.print("Success!\n", .{});
}

// Multi-line string
const multi_line =
    \\This is a
    \\multi-line string
    \\in Zig
;

// Tests
test "basic test" {
    const x: i32 = 1;
    const y: i32 = 2;
    try std.testing.expect(x + y == 3);
}
