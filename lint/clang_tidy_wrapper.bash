#!/usr/bin/env bash
# This is a wrapper for clang-tidy which gives us control over error handling
# Usage: clang_tidy_wrapper.bash <coreutils-path> <clang-tidy-path> <file1> <file2> ... -- <compiler-args>
#
# Controls:
# - CLANG_TIDY__VERBOSE: If set, be verbose
# - CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE: If set, write stdout and stderr to this file
# - CLANG_TIDY__EXIT_CODE_OUTPUT_FILE: If set, write the highest exit code 
# to this file and return success

# Both tools are declared Bazel inputs; never look up utilities on PATH.
coreutils=$1
clang_tidy=$2
shift 2

if [[ -n $CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE ]]; then
    # Create or truncate the report without a host touch dependency.
    > "$CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE"
    if [[ -n $CLANG_TIDY__VERBOSE ]]; then
        echo "Output > ${CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE}"
    fi
fi
if [[ -n $CLANG_TIDY__EXIT_CODE_OUTPUT_FILE ]]; then
    if [[ -n $CLANG_TIDY__VERBOSE ]]; then
        echo "Exit Code -> ${CLANG_TIDY__EXIT_CODE_OUTPUT_FILE}"
    fi
fi

if [[ -n $CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE ]]; then
    out_file=$CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE
else
    out_file=$("$coreutils" mktemp)
fi
# Capture raw output here; statistics get filtered into $out_file below.
raw_out_file=$("$coreutils" mktemp)
# include stderr in output file; it contains some of the diagnostics
# NB: do NOT collapse "$@" into a single string and eval it — args containing
# shell metacharacters such as `__attribute__((deprecated))` then get re-parsed
# by the shell ("syntax error near unexpected token `('"). Run clang-tidy
# directly with "$@" so each argument is preserved verbatim.
if [[ -n $CLANG_TIDY__VERBOSE ]]; then
    echo "$@"
    echo "cwd: " `pwd`
    echo "$clang_tidy $@ > $raw_out_file 2>&1"
fi
"$clang_tidy" "$@" > "$raw_out_file" 2>&1
exit_code=$?
# Drop clang-tidy summary statistics (e.g. "N warnings generated.") that it
# prints even on a clean, exit-0 run thus tripping in fail_on_violation mode.
# Diagnostics are kept. With --use-color, a summary line can carry the SGR
# reset left over from the preceding diagnostic.
sgr=$'(\033\\[[0-9;]*m)*'
summary="^${sgr}([0-9]+ (warnings?|errors?)( and [0-9]+ errors?)? generated\.|Suppressed [0-9]+ warnings? \(.*\)\.|Use -header-filter=.*|[0-9]+ warnings? treated as errors?)${sgr}\$"
# Bash can filter the report without adding a host grep dependency.
if ! (
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ $summary ]]; then
            printf '%s\n' "$line" || exit 1
        fi
    done < "$raw_out_file"
) > "$out_file"; then
    echo "clang_tidy_wrapper: failed to filter clang-tidy output" >&2
    exit 1
fi
"$coreutils" rm -f "$raw_out_file"
if [[ -z $CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE ]]; then
    "$coreutils" cat "$out_file"
fi
# distinguish between compile (fatal) errors and warnings-as-errors errors
fatal_error=0
if [ $exit_code -eq 126 ] || [ $exit_code -eq 127 ]; then
    # 126/127 mean clang-tidy never ran (not executable, or a shared library
    # the loader could not resolve). With no diagnostics to capture, recording
    # the code would leave the report indistinguishable from a clean lint.
    fatal_error=1
elif [ $exit_code -ne 0 ] && [ -s $out_file ]; then
    while read line
    do
        if [[ $line == *"clang-diagnostic-error"* ]]; then
            fatal_error=1
            break
        fi
    done < "$out_file"
fi
if [ $fatal_error -ne 0 ]; then
    "$coreutils" cat "$out_file"
    # only a temp file is ours to delete; when the env var is set this is a
    # declared Bazel output, and the diagnostics in it are the whole evidence
    if [[ -z $CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE ]]; then
        "$coreutils" rm "$out_file"
    fi
    if [[ -n $CLANG_TIDY__VERBOSE ]]; then
        echo "regarding exit $exit_code as fatal"
        echo "exit $exit_code"
    fi
    exit $exit_code
fi
if [[ -z $CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE ]]; then
    "$coreutils" rm "$out_file"
fi

# if CLANG_TIDY__EXIT_CODE_FILE is set, write the max exit code to that file and return success
if [[ -n $CLANG_TIDY__EXIT_CODE_OUTPUT_FILE ]]; then
    if [[ -n $CLANG_TIDY__VERBOSE ]]; then  
        echo "echo $exit_code > $CLANG_TIDY__EXIT_CODE_OUTPUT_FILE"
        echo "exit 0"
    fi
    echo $exit_code > $CLANG_TIDY__EXIT_CODE_OUTPUT_FILE
    exit 0
fi

if [[ -n $CLANG_TIDY__VERBOSE ]]; then
    echo exit $exit_code
fi
# Surface the captured diagnostics on the action's stderr when we are about
# to exit non-zero. Without this, fail_on_violation builds report
# `Linting //x:y failed` with no body — the diagnostic text sits in the
# .out file (CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE) and never reaches the
# user. The fatal_error branch above already cats to stdout for
# clang-diagnostic-error; this covers the warnings-as-errors case
# (e.g. WarningsAsErrors: "*") where there is no clang-diagnostic-error
# string in the output.
if [ $exit_code -ne 0 ] && [ -n "$CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE" ] && [ -s "$out_file" ]; then
    "$coreutils" cat "$out_file" >&2
fi
exit $exit_code
