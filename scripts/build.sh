#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
exec python3 scripts/build_app.py "$@"
