#!/usr/bin/env bash
# Stand-in for clang-tidy: apply a fix without requiring any host utilities.
[[ $1 == --fix ]] || exit 2
printf 'fixed\n' > "$2"
printf '1 warning generated.\n'
