const std = @import("std");
const io = std.io;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListAligned = std.ArrayListAligned;

fn readSrc(alloc: Allocator, filename: [:0]const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    return file.readToEndAlloc(alloc, 256 * 1024 * 1024);
}

pub fn main() anyerror!void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = std.process.args();
    _ = args.skip();

    const filename = args.next() orelse return error.Failure;

    const src = try readSrc(allocator, filename);
    var srcPtr: usize = 0;

    var data = ArrayListAligned(u8, @alignOf(u8)).init(allocator);
    var dataPtr: usize = 0;
    try data.append(0);

    var jumpStack = ArrayListAligned(usize, @alignOf(usize)).init(allocator);

    const stdout = io.getStdOut().writer();
    const stdin = io.getStdIn().reader();

    var nesting: u32 = 0;
    var target_nesting: ?u32 = null;

    while (true) {
        if (srcPtr >= src.len) {
            break;
        }
        const c = src[srcPtr];
        srcPtr += 1;

        if (target_nesting) |target| {
            switch (c) {
                '[' => {
                    nesting += 1;
                },
                ']' => {
                    nesting -= 1;
                },
                else => {},
            }
            if (target == nesting) {
                target_nesting = null;
            }

            continue;
        }

        switch (c) {
            '+' => data.items[dataPtr] +%= 1,
            '-' => data.items[dataPtr] -%= 1,
            '<' => dataPtr -= 1,
            '>' => {
                dataPtr += 1;
                if (dataPtr >= data.items.len) {
                    try data.append(0);
                }
            },
            '.' => try stdout.writeAll(&[1]u8{data.items[dataPtr]}),
            ',' => {
                var buf = [1]u8{undefined};
                _ = try stdin.readAll(&buf);
                data.items[dataPtr] = buf[0];
            },
            '[' => {
                nesting += 1;
                if (data.items[dataPtr] != 0) {
                    try jumpStack.append(srcPtr - 1);
                } else {
                    target_nesting = nesting - 1;
                }
            },
            ']' => {
                nesting -= 1;
                srcPtr = jumpStack.pop();
            },
            else => {},
        }
    }
}
