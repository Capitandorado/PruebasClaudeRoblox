#!/usr/bin/env bash
# Full verification: format, lint, type-check, build the place file and run the tests.
# Tools: rojo, stylua, selene, luau-lsp, lune (see docs/DEVELOPMENT.md for install notes).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS="${ROBLOX_DEFS:-/root/tools/defs/globalTypes.d.luau}"

echo "== sourcemap"
rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json

echo "== stylua"
stylua --check src

echo "== selene"
selene src

echo "== luau-lsp (Roblox types)"
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions "@roblox=$DEFS" \
	--flag:LuauSolverV2=false --no-strict-dm-types src

echo "== rojo build"
mkdir -p build
rojo build default.project.json -o build/VoidFactory.rbxl

echo "== verify place file"
lune run tools/verify_place.luau build/VoidFactory.rbxl

echo "== tests"
lune run tests/run.luau "$@"
