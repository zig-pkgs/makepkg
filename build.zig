const std = @import("std");
const BuildPkg = Step.BuildPkg;
const CreatePkg = Step.CreatePkg;

pub const root = @import("src/root.zig");
pub const Step = root.Step;

pub fn addCreatePkg(b: *std.Build, options: CreatePkg.Options) *CreatePkg {
    var options_copy = options;
    if (options_copy.first_ret_addr == null)
        options_copy.first_ret_addr = @returnAddress();
    return CreatePkg.create(b, options_copy);
}

pub fn addBuildPkg(b: *std.Build, options: BuildPkg.Options) *BuildPkg {
    var options_copy = options;
    if (options_copy.first_ret_addr == null)
        options_copy.first_ret_addr = @returnAddress();
    return BuildPkg.create(b, options_copy);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const archive_dep = b.dependency("archive", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("makepkg", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "archive", .module = archive_dep.module("archive") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "pkggen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "makepkg", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
