const std = @import("std");
const builtin = @import("builtin");

const generate_vscode = @import("generate_vscode");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allcator = gpa.allocator();

    const args = try std.process.argsAlloc(allcator);
    defer std.process.argsFree(allcator, args);

    if (args.len != 2) fatal("wrong number of arguments {d}", .{args.len});

    const vscode_path = args[1];

    var vscode_dir = try std.fs.openDirAbsolute(vscode_path, .{});
    defer vscode_dir.close();

    try generate_vscode.createLauchJson(allcator, vscode_dir, .{
        .configurations = &.{},
    });

    try generate_vscode.createOrUpdateSettingsJson(allcator, vscode_dir, true);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
