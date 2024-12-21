const std = @import("std");
const builtin = @import("builtin");

const build_zon = @import("build.zig.zon");

const min_zig_version = std.SemanticVersion.parse("0.14.0-dev.1911") catch @panic("Where is .zigversion?");
const version = std.SemanticVersion.parse(@embedFile(".version")) catch @panic("Where is .version?");

const cetech1_build = @import("cetech1");
const generate_ide = cetech1_build.generate_ide;

const APP_NAME = "minimal";
const BIN_NAME = "minimal";

pub const modules = [_][]const u8{
    // Minimal
    "minimal",
};

const enabled_cetech_modules: []const []const u8 = &(cetech1_build.core_modules ++ cetech1_build.studio_modules ++ cetech1_build.runner_modules);
const all_modules: []const []const u8 = enabled_cetech_modules ++ modules;

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
        .static_modules = b.option(bool, "static_modules", "build all modules in static mode.") orelse false,

        // Tracy options
        .enable_tracy = b.option(bool, "with_tracy", "build with tracy.") orelse true,
        .tracy_on_demand = b.option(bool, "tracy_on_demand", "build tracy with TRACY_ON_DEMAND") orelse true,

        .enable_shaderc = b.option(bool, "with_shaderc", "build with shaderc support") orelse true,
        .ide = b.option(generate_ide.EditorType, "ide", "IDE for gen-ide command") orelse .vscode,
    };

    // const options_step = b.addOptions();
    // options_step.addOption(std.SemanticVersion, "version", version);
    // // add build args
    // inline for (std.meta.fields(@TypeOf(options))) |field| {
    //     options_step.addOption(field.type, field.name, @field(options, field.name));
    // }
    // const options_module = options_step.createModule();
    // _ = options_module; // autofix

    //
    // Extrnals
    //

    // Cetech1
    const app_name: []const u8 = APP_NAME;
    const external_credits: []const std.Build.LazyPath = &.{b.path(".externals.zon")};
    const cetech1 = b.dependency(
        "cetech1",
        .{
            .target = target,
            .optimize = optimize,
            .externals_optimize = options.externals_optimize,

            .app_name = app_name,
            .external_credits = external_credits,
            .authors = b.path("AUTHORS.md"),

            .with_module = all_modules,
            .with_tracy = options.enable_tracy,
            .tracy_on_demand = options.tracy_on_demand,
            .with_shaderc = options.enable_shaderc,
            .static_modules = options.static_modules,
            .dynamic_modules = options.dynamic_modules,
        },
    );

    //
    // TOOLS
    //
    const generate_ide_tool = cetech1.artifact("generate_ide");

    //
    // Init repository step
    //
    const init_step = b.step("init", "init repository");
    cetech1_build.initStep(b, init_step, "externals/cetech1/");

    const sync_remote_step = b.step("update-cetech1", "Upgrade submodule with cetech to latest");
    cetech1_build.updateCectechStep(b, sync_remote_step, "externals/cetech1/");

    //
    // Studio exe
    //
    _ = try cetech1_build.createStudioExe(
        b,
        BIN_NAME,
        b.path("externals/cetech1/src/main.zig"),
        cetech1.module("kernel"),
        cetech1.artifact("cetech1_kernel"),
        version,
        &.{},
        target,
        optimize,
    );

    //
    // Runner exe
    //
    _ = try cetech1_build.createRunnerExe(
        b,
        BIN_NAME,
        b.path("externals/cetech1/src/main.zig"),
        cetech1.module("kernel"),
        cetech1.artifact("cetech1_kernel"),
        version,
        &.{},
        target,
        optimize,
    );

    //
    // Gen IDE config
    //
    const gen_ide_step = b.step("gen-ide", "init/update IDE configs");
    const gen_ide = b.addRunArtifact(generate_ide_tool);
    gen_ide.addArgs(&.{ "--ide", @tagName(options.ide) });
    gen_ide.addArg("--is-project");

    gen_ide.addArg("--bin-path");
    gen_ide.addDirectoryArg(b.path("zig-out/bin/" ++ BIN_NAME));

    gen_ide.addArg("--project-path");
    gen_ide.addDirectoryArg(b.path(""));

    // gen_ide.addArg("--fixtures");
    // gen_ide.addDirectoryArg(b.path("fixtures/"));

    gen_ide.addArg("--config");
    gen_ide.addDirectoryArg(b.path(".ide.zon"));

    gen_ide_step.dependOn(&gen_ide.step);

    if (options.enable_shaderc) {
        b.installArtifact(cetech1.artifact("shaderc"));
    }

    if (options.dynamic_modules) {
        var buff: [256:0]u8 = undefined;

        // CETech modules
        for (enabled_cetech_modules) |m| {
            // TODO: Problem with debugdraw in dll on windows.
            if (target.result.os.tag == .windows and std.mem.eql(u8, m, "gpu_bgfx")) continue;

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
                .link_mode = .dynamic,
            }).artifact(artifact_name);

            const step = b.addInstallArtifact(art, .{});
            b.default_step.dependOn(&step.step);
        }
    }

    // if (options.static_modules) {
    //     var buff: [256:0]u8 = undefined;

    //     // Project modules
    //     for (modules) |m| {
    //         const artifact_name = try std.fmt.bufPrintZ(&buff, "ct_{s}", .{m});
    //         exe.linkLibrary(b.dependency(m, .{
    //             .target = target,
    //             .optimize = optimize,
    //             .link_mode = .static,
    //         }).artifact(artifact_name));
    //     }
    // }
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
