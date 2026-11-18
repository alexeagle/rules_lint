"""Make the flags of a C/C++ toolchain usable for clang-tidy."""

def update_flag(flag, msvc):
    """Translate one flag of the C/C++ toolchain for clang-tidy.

    Args:
        flag: one item of a compiler command line.
        msvc: whether the toolchain targets Windows, so the command line can
            have MSVC-style options.

    Returns:
        The items to pass to clang-tidy instead of the flag; empty to drop it.
    """
    if flag.startswith("/") and not msvc:
        # Not an MSVC option, but an absolute path, for example the directory
        # after `-isystem`.
        return [flag]

    # update from MSVC C++ standard to clang C++ standard
    unsupported_flags = [
        "-fno-canonical-system-headers",
        "-fstack-usage",
        "/nologo",
        "/COMPILER_MSVC",
        "/showIncludes",
        "/experimental:external",
    ]
    unsupported_prefixes = [
        "/wd",
        "-W",
        "/W",
        "/external",
    ]
    if (flag in unsupported_flags):
        return []
    for prefix in unsupported_prefixes:
        if flag.startswith(prefix):
            return []

    flags = [flag]

    # remap MSVC flags to clang-style
    if (flag.startswith("/std:")):
        # remap c++ standard to clang
        flags = ["-std=" + flag.removeprefix("/std:")]
    elif (flag.startswith("/D")):
        # remap defines
        flags = ["-" + flag[1:]]
    elif (flag.startswith("/FI")):
        flags = ["-include", flag.removeprefix("/FI")]
    elif (flag.startswith("/I")):
        flags = ["-iquote", flag.removeprefix("/I")]
    elif (flag in ["/MD", "/MDd", "/MT", "/MTd"]):
        # mimic microsoft's behaviour and add a define
        flags = ["-D_MT"]
    elif (flag.startswith("/")):
        # strip all other microsoft params
        return []
    return flags
