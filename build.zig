const std = @import("std");
const Build = std.Build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_logging = b.option(bool, "enable-logging", "Should logging be enabled") orelse (optimize == .Debug);

    const srt_dep = b.dependency("srt", .{});

    const mbedtls_dep = b.dependency("mbedtls", .{
        .target = target,
        .optimize = optimize,
    });

    const googletest_dep = b.dependency("googletest", .{
        .target = target,
        .optimize = optimize,
    });

    const srt_version_string = "1.5.4";
    const version = std.SemanticVersion.parse(srt_version_string) catch unreachable;

    // TODO:
    // ENABLE_BONDING
    // ENABLE_CXX11
    // ENABLE_DEBUG
    // ENABLE_ENCRYPTION
    // ENABLE_GETNAMEINFO
    // ENABLE_HAICRYPT_LOGGING
    // ENABLE_HEAVY_LOGGING
    // ENABLE_INET_PTON
    // ENABLE_MONOTONIC_CLOCK
    // ENABLE_STDCXX_SYNC
    // ENABLE_THREAD_CHECK
    // ENABLE_TESTING
    // USE_CXX_STD
    // USE_ENCLIB
    // USE_STATIC_LIBSTDCXX

    const haicrypt = b.addStaticLibrary(.{
        .name = "haicrypt",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    setDefines(b, srt_version_string, haicrypt, target, enable_logging);
    haicrypt.linkLibCpp();
    haicrypt.linkLibrary(mbedtls_dep.artifact("mbedtls"));
    haicrypt.installHeader(srt_dep.path("haicrypt/haicrypt.h"), "haicrypt.h");
    haicrypt.installHeader(srt_dep.path("haicrypt/hcrypt_ctx.h"), "hcrypt_ctx.h");
    haicrypt.installHeader(srt_dep.path("haicrypt/hcrypt_msg.h"), "hcrypt_msg.h");
    haicrypt.installLibraryHeaders(mbedtls_dep.artifact("mbedtls"));
    haicrypt.addIncludePath(srt_dep.path("common"));
    haicrypt.addCSourceFiles(.{
        .root = srt_dep.path("haicrypt"),
        .flags = &.{
            "-fno-sanitize=undefined",
        },
        .files = &.{
            "cryspr.c",
            "cryspr-mbedtls.c",
            "hcrypt.c",
            "hcrypt_ctx_rx.c",
            "hcrypt_ctx_tx.c",
            "hcrypt_rx.c",
            "hcrypt_sa.c",
            "hcrypt_tx.c",
            "hcrypt_xpt_srt.c",
            "haicrypt_log.cpp",
        },
    });

    const version_header = b.addConfigHeader(.{
        .style = .{
            .cmake = srt_dep.path("srtcore/version.h.in"),
        },
    }, .{
        .SRT_VERSION_MAJOR = std.fmt.allocPrint(b.allocator, "{}", .{version.major}) catch unreachable,
        .SRT_VERSION_MINOR = std.fmt.allocPrint(b.allocator, "{}", .{version.minor}) catch unreachable,
        .SRT_VERSION_PATCH = std.fmt.allocPrint(b.allocator, "{}", .{version.patch}) catch unreachable,
        .SRT_VERSION = srt_version_string,
        .CI_BUILD_NUMBER_STRING = "0",
    });

    const srtcore = b.addStaticLibrary(.{
        .name = "srt",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    srtcore.linkLibCpp();
    srtcore.linkLibrary(haicrypt);
    setDefines(b, srt_version_string, srtcore, target, enable_logging);
    srtcore.addIncludePath(version_header.getOutput().dirname());
    srtcore.addIncludePath(srt_dep.path("haicrypt"));
    srtcore.addIncludePath(srt_dep.path("srtcore"));
    srtcore.addIncludePath(srt_dep.path("common"));
    srtcore.installHeader(srt_dep.path("srtcore/srt.h"), "srt.h");
    srtcore.installHeader(srt_dep.path("srtcore/logging_api.h"), "logging_api.h");
    srtcore.installHeader(srt_dep.path("srtcore/platform_sys.h"), "platform_sys.h");
    srtcore.installHeader(srt_dep.path("srtcore/access_control.h"), "access_control.h");
    if (target.result.os.tag == .windows) {
        srtcore.linkSystemLibrary("wsock32");
        srtcore.linkSystemLibrary("ws2_32");
        srtcore.installHeader(srt_dep.path("common/win/syslog_defs.h"), "win/syslog_defs.h");
        srtcore.installHeader(srt_dep.path("common/win/unistd.h"), "win/unistd.h");
        srtcore.installHeader(srt_dep.path("common/win/wintime.h"), "win/wintime.h");
        srtcore.addCSourceFile(.{
            .file = srt_dep.path("common/win_time.cpp"),
            .flags = &.{
                "-std=c++11",
                "-fno-sanitize=undefined",
            },
        });
    }
    srtcore.installConfigHeader(version_header);
    srtcore.addCSourceFiles(.{
        .root = srt_dep.path("srtcore"),
        .flags = &.{
            "-std=c++11",

            "-fno-sanitize=undefined",
        },
        .files = &.{
            "api.cpp",
            "buffer_snd.cpp",
            "buffer_rcv.cpp",
            "buffer_tools.cpp",
            "cache.cpp",
            "channel.cpp",
            "common.cpp",
            "core.cpp",
            "crypto.cpp",
            "epoll.cpp",
            "fec.cpp",
            "handshake.cpp",
            "list.cpp",
            "logger_default.cpp",
            "logger_defs.cpp",
            "sync_cxx11.cpp",
            "md5.cpp",
            "packet.cpp",
            "packetfilter.cpp",
            "queue.cpp",
            "congctl.cpp",
            "socketconfig.cpp",
            "srt_c_api.cpp",
            "strerror_defs.cpp",
            "sync.cpp",
            "tsbpd_time.cpp",
            "window.cpp",
        },
    });
    srtcore.addCSourceFile(.{
        .file = srt_dep.path("srtcore/srt_compat.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
        },
    });

    if (enable_logging) {
        srtcore.addCSourceFile(.{
            .file = srt_dep.path("srtcore/logging.cpp"),
            .flags = &.{
                "-fno-sanitize=undefined",
            },
        });
    }

    b.installArtifact(srtcore);

    const live_transmit = b.addExecutable(.{
        .name = "srt-live-transmit",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    live_transmit.addCSourceFiles(.{
        .root = srt_dep.path("apps"),
        .flags = &.{
            "-std=c++11",
            "-fno-sanitize=undefined",
        },
        .files = &.{
            "srt-live-transmit.cpp",
            "apputil.cpp",
            "uriparser.cpp",
            "logsupport.cpp",
            "logsupport_appdefs.cpp",
            "socketoptions.cpp",
            "transmitmedia.cpp",
            "statswriter.cpp",
            "verbose.cpp",
        },
    });
    live_transmit.linkLibCpp();
    live_transmit.linkLibrary(srtcore);
    live_transmit.addIncludePath(srt_dep.path("apps"));
    live_transmit.addIncludePath(srt_dep.path("srtcore"));
    setDefines(b, srt_version_string, live_transmit, target, enable_logging);
    b.installArtifact(live_transmit);

    const file_transmit = b.addExecutable(.{
        .name = "srt-file-transmit",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    file_transmit.addCSourceFiles(.{
        .root = srt_dep.path("apps"),
        .flags = &.{
            "-std=c++11",

            "-fno-sanitize=undefined",
        },
        .files = &.{
            "srt-file-transmit.cpp",
            "apputil.cpp",
            "uriparser.cpp",
            "logsupport.cpp",
            "logsupport_appdefs.cpp",
            "socketoptions.cpp",
            "transmitmedia.cpp",
            "statswriter.cpp",
            "verbose.cpp",
        },
    });
    file_transmit.linkLibCpp();
    file_transmit.linkLibrary(srtcore);
    file_transmit.addIncludePath(srt_dep.path("apps"));
    file_transmit.addIncludePath(srt_dep.path("srtcore"));
    live_transmit.addIncludePath(srt_dep.path("core"));
    setDefines(b, srt_version_string, file_transmit, target, enable_logging);
    b.installArtifact(file_transmit);

    const tests = b.addExecutable(.{
        .name = "tests",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    setDefines(b, srt_version_string, tests, target, enable_logging);
    tests.linkLibCpp();
    tests.linkLibrary(googletest_dep.artifact("gtest"));
    tests.linkLibrary(srtcore);
    tests.linkLibrary(haicrypt);
    tests.addIncludePath(srt_dep.path("srtcore"));
    tests.addIncludePath(srt_dep.path("haicrypt"));
    //tests.addIncludePath(srt_dep.path("common"));
    tests.addCSourceFiles(.{
        .root = srt_dep.path("test"),
        .flags = &.{"-fno-sanitize=undefined"},
        .files = &.{
            "test_main.cpp",
            "test_buffer_rcv.cpp",
            "test_common.cpp",
            "test_connection_timeout.cpp",
            "test_crypto.cpp",
            "test_cryspr.cpp",
            "test_enforced_encryption.cpp",
            "test_epoll.cpp",
            "test_fec_rebuilding.cpp",
            "test_file_transmission.cpp",
            "test_ipv6.cpp",
            "test_listen_callback.cpp",
            "test_losslist_rcv.cpp",
            "test_losslist_snd.cpp",
            "test_many_connections.cpp",
            "test_muxer.cpp",
            "test_seqno.cpp",
            "test_socket_options.cpp",
            "test_sync.cpp",
            "test_threadname.cpp",
            "test_timer.cpp",
            "test_unitqueue.cpp",
            "test_utilities.cpp",
            "test_reuseaddr.cpp",
            "test_socketdata.cpp",
            "test_snd_rate_estimator.cpp",
        },
    });
    b.getInstallStep().dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

fn setDefines(
    b: *std.Build,
    version_string: []const u8,
    lib: *Build.Step.Compile,
    target: Build.ResolvedTarget,
    enable_logging: bool,
) void {
    switch (target.result.os.tag) {
        .macos => {},
        .linux => {
            lib.root_module.addCMacro("LINUX", "1");
            lib.root_module.addCMacro("SRT_ENABLE_BINDTODEVICE", "1");
        },
        .windows => {
            lib.root_module.addCMacro("WIN32", "1");
            lib.root_module.addCMacro("PTW32_STATIC_LIB", "1");
        },
        .freebsd, .netbsd, .openbsd, .dragonfly => {
            lib.root_module.addCMacro("BSD", "1");
        },
        else => {},
    }

    if (enable_logging) {
        lib.root_module.addCMacro("ENABLE_LOGGING", "1");
    }
    lib.root_module.addCMacro("HAVE_INET_PTON", "1");
    lib.root_module.addCMacro("ENABLE_STDCXX_SYNC", "1");
    lib.root_module.addCMacro("HAVE_CXX_STD_PUT_TIME", "1");
    lib.root_module.addCMacro("USE_MBEDTLS", "1");
    lib.root_module.addCMacro("SRT_ENABLE_ENCRYPTION", "1");
    lib.root_module.addCMacro("_GNU_SOURCE", "1");
    lib.root_module.addCMacro("HAI_PATCH", "1");
    lib.root_module.addCMacro("HAI_ENABLE_SRT", "1");
    lib.root_module.addCMacro("SRT_VERSION", std.fmt.allocPrint(b.allocator, "\"{s}\"", .{version_string}) catch unreachable);
}
