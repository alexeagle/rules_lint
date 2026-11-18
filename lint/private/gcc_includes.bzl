"Compile flags from a GCC toolchain, adapted for clang-tidy"

_INCLUDE_OPTIONS = ["-isystem", "-idirafter"]

def _is_gcc_builtin_include(path):
    # <prefix>/lib/gcc/<target>/<version>/include
    parts = path.split("/")
    return len(parts) >= 5 and parts[-5] == "lib" and parts[-4] == "gcc" and parts[-1] == "include"

def with_gcc_builtin_includes_last(flags):
    """Moves GCC's own header directory last, turning -nostdinc into -nostdlibinc.

    clang can't parse GCC's intrinsics headers, such as <immintrin.h>.
    -nostdlibinc lets clang add its own compiler headers, ahead of GCC's, and
    keeps the host's system headers out. GCC's directory still serves headers
    clang lacks, such as <quadmath.h>.

    Args:
        flags: compile flags from the C++ toolchain

    Returns:
        the flags, changed only if they name GCC's own header directory
    """
    kept = []
    moved = []
    for flag in flags:
        if kept and kept[-1] in _INCLUDE_OPTIONS and _is_gcc_builtin_include(flag):
            kept.pop()
            moved.append(flag)
            continue
        paths = [flag.removeprefix(option) for option in _INCLUDE_OPTIONS if flag.startswith(option)]
        if paths and _is_gcc_builtin_include(paths[0]):
            moved.append(paths[0])
        else:
            kept.append(flag)
    if not moved:
        return flags
    return ["-nostdlibinc" if flag == "-nostdinc" else flag for flag in kept] + ["-idirafter" + path for path in moved]
