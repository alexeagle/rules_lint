"""Generate a shared-dependency analysis workload in a lint example.

Run from any directory: python3 tools/memory_profile_fixture.py cpp
Remove examples/<language>/_memory_profile after profiling. No actions need run.
"""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("language", choices=("cpp", "java"))
    args = parser.parse_args()
    fixture = Path(__file__).resolve().parent.parent / "examples" / args.language / "_memory_profile"
    # Refuse to overwrite an existing workload or unrelated files.
    fixture.mkdir()
    if args.language == "cpp":
        (fixture / "sample.cc").write_text("int sample() { return 0; }\n")
        lines = ['load("@rules_cc//cc:defs.bzl", "cc_library")']
        for i in range(100):
            includes = [f"include/{i}/{j}" for j in range(20)]
            lines.append(f'cc_library(name="dep{i}", includes={includes!r})')
        rule, source = "cc_library", "sample.cc"
    else:
        (fixture / "Sample.java").write_text("class Sample {}\n")
        lines = ['load("@rules_java//java:defs.bzl", "java_library")']
        for i in range(100):
            lines.append(f'java_library(name="dep{i}", srcs=["Sample.java"])')
        rule, source = "java_library", "Sample.java"
    dependencies = [f":dep{i}" for i in range(100)]
    for i in range(100):
        lines.append(f'{rule}(name="target{i}", srcs=["{source}"], deps={dependencies!r})')
    (fixture / "BUILD.bazel").write_text("\n".join(lines) + "\n")
    print(fixture)


if __name__ == "__main__":
    main()
