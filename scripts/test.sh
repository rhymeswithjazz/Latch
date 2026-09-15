#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift test --disable-sandbox "$@"
python3 -m unittest discover -s scripts/tests
