#!/bin/sh
# Run a command inside a proper MSYS2 CLANG64 login shell.
# Usage: tools/clang64.sh "<command>"
exec /c/msys64/usr/bin/env MSYSTEM=CLANG64 CHERE_INVOKING=1 /c/msys64/usr/bin/bash -lc "$*"
