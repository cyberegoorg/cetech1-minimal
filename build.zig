const std = @import("std");
const builtin = @import("builtin");

const min_zig_version = std.SemanticVersion.parse("0.14.0-dev.1911") catch @panic("Where is .zigversion?");
const version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

const cetech1_build = @import("cetech1");

const enabled_cetech_modules = cetech1_build.core_modules ++ cetech1_build.editor_modules;

pub const modules = [_][]const u8{
    // Minimal
    "minimal",
};

pub fn build(b: *std.Build) !void {
    try ensureZigVersion();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // OPTIONS
    //

    const options = .{
        .externals_optimize = b.option(std.builtin.OptimizeMode, "externals_optimize", "Optimize for externals libs") orelse .ReleaseFast,
        .dynamic_modules = b.option(bool, "dynamic_modules", "build all modules in dynamic mode.") orelse true,
        //.static_modules = b.option(bool, "static_modules", "build all modules in static mode.") orelse false,

        // Tracy options
        .enable_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
        .tracy_on_demand = b.option(bool, "tracy_on_demand", "build tracy with TRACY_ON_DEMAND") orelse true,

        .enable_shaderc = b.option(bool, "with_shaderc", "build with shaderc support") orelse true,
    };

    const options_step = b.addOptions();
    options_step.addOption(std.SemanticVersion, "version", version);

    // add build args
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();
    _ = options_module; // autofix

    //
    // Extrnals
    //

    // Cetech1
    const cetech1 = b.dependency(
        "cetech1",
        .{
            .target = target,
            .optimize = optimize,
            .externals_optimize = options.externals_optimize,

            .with_tracy = options.enable_tracy,
            .tracy_on_demand = options.tracy_on_demand,

            .with_shaderc = options.enable_shaderc,

            //.static_modules = options.static_modules,
            .dynamic_modules = options.dynamic_modules,
        },
    );

    //
    // TOOLS
    //

    const generate_vscode_tool = b.addExecutable(.{
        .name = "generate_vscode",
        .root_source_file = b.path("tools/generate_vscode.zig"),
        .target = target,
    });
    generate_vscode_tool.root_module.addAnonymousImport("generate_vscode", .{
        .root_source_file = b.path("externals/cetech1/src/tools/generate_vscode.zig"),
    });

    //
    // Init repository step
    //
    const init_step = b.step("init", "init repository");
    cetech1_build.initStep(b, init_step, "externals/cetech1/");

    //
    // Gen vscode
    //
    const vscode_step = b.step("vscode", "init/update vscode configs");
    const gen_vscode = b.addRunArtifact(generate_vscode_tool);
    gen_vscode.addDirectoryArg(b.path(".vscode/"));
    vscode_step.dependOn(&gen_vscode.step);

    if (options.enable_shaderc) {
        b.installArtifact(cetech1.artifact("shaderc"));
    }

    if (options.dynamic_modules) {
        b.installArtifact(cetech1.artifact("cetech1"));

        var buff: [256:0]u8 = undefined;

        // CETech modules
        for (enabled_cetech_modules) |m| {
            const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
            const art = cetech1.artifact(artifact_name);
            const step = b.addInstallArtifact(art, .{});
            b.default_step.dependOn(&step.step);
        }

        // Project modules
        for (modules) |m| {
            const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
            const art = b.dependency(m, .{
                .target = target,
                .optimize = optimize,
            }).artifact(artifact_name);

            const step = b.addInstallArtifact(art, .{});
            b.default_step.dependOn(&step.step);
        }
    }
}

fn ensureZigVersion() !void {
    var installed_ver = builtin.zig_version;
    installed_ver.build = null;

    if (installed_ver.order(min_zig_version) == .lt) {
        std.log.err("\n" ++
            \\---------------------------------------------------------------------------
            \\
            \\Installed Zig compiler version is too old.
            \\
            \\Min. required version: {any}
            \\Installed version: {any}
            \\
            \\Please install newer version and try again.
            \\zig/get_zig.sh <ARCH>
            \\
            \\---------------------------------------------------------------------------
            \\
        , .{ min_zig_version, installed_ver });
        return error.ZigIsTooOld;
    }
}
