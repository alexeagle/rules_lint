#!/usr/bin/env bash
set -euo pipefail

expected_exit_code="$1"
shift
test "$#" = 3
for report in "$@"; do
    case "$report" in
        *.out)
            if [[ "$expected_exit_code" == 0 ]]; then
                test ! -s "$report"
            else
                diff -u <(printf 'ruff stdout\nruff configuration error\n') "$report"
            fi
            ;;
        *.exit_code) test "$(cat "$report")" = "$expected_exit_code" ;;
        *.patch) test ! -s "$report" ;;
        *) exit 1 ;;
    esac
done
