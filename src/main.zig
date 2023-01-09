const std = @import("std");
const io = std.io;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

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

    const filename = args.next() orelse return error.NoArgumentGiven;

    const src = try readSrc(allocator, filename);
    defer allocator.free(src);
    var srcPtr: usize = 0;

    var data = ArrayList(u8).init(allocator);
    defer data.deinit();
    var dataPtr: usize = 0;
    try data.append(0);

    var jumpStack = ArrayList(usize).init(allocator);
    defer jumpStack.deinit();

    var stdout_buf = io.bufferedWriter(io.getStdOut().writer());
    const stdout = stdout_buf.writer();
    var stdin_buf = io.bufferedReader(io.getStdIn().reader());
    const stdin = stdin_buf.reader();

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
            '<' => {
                if (dataPtr == 0) {
                    return error.DataPointerBeforeStart;
                }
                dataPtr -= 1;
            },
            '>' => {
                dataPtr += 1;
                if (dataPtr >= data.items.len) {
                    try data.append(0);
                }
            },
            '.' => try stdout.writeByte(data.items[dataPtr]),
            ',' => data.items[dataPtr] = (stdin.readByte()) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
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
                const jmpTarget = jumpStack.popOrNull() orelse return error.UnmatchedEndLoop;
                srcPtr = jmpTarget;
            },
            else => {},
        }
    }

    try stdout_buf.flush();
}
