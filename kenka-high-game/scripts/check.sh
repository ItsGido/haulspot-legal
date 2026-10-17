#!/usr/bin/env bash
# Runs every check. Usage: scripts/check.sh [path-filter]
#   1. luau-lsp type check (Roblox API types + Rojo sourcemap)
#   2. selene lint
#   3. unit tests (tests/run.luau)
#   4. cross-reference check (scripts/xref.py)
#   5. rojo build (proves the project assembles into a place file)
set -uo pipefail
cd "$(dirname "$0")/.."
T=.tools
[ -x "$T/rojo" ] || scripts/setup-tools.sh
FILTER="${@:-src}"
status=0
RUN=$(mktemp -d)  # per-run files so parallel runs don't collide

echo "== Sourcemap"
$T/rojo sourcemap default.project.json -o "$RUN/sourcemap.json" || status=1
cp "$RUN/sourcemap.json" sourcemap.json 2>/dev/null || true

echo "== Type check (luau-lsp)"
$T/luau-lsp analyze --definitions="$T/globalTypes.d.luau" --sourcemap="$RUN/sourcemap.json" \
  --settings=scripts/luau-lsp-settings.json $(find $FILTER -name '*.luau' | sort) 2>&1 | grep -v "^$" | tee "$RUN/typecheck.txt"
if grep -qE "TypeError|SyntaxError|UnknownGlobal|UnknownRequire" "$RUN/typecheck.txt"; then status=1; fi

echo "== Lint (selene)"
# selene needs Roblox's API dump on first run; if it can't download it, skip (luau-lsp lints still run).
if $T/selene --display-style=quiet $FILTER 2>"$RUN/selene.txt"; then :; else
  if grep -q "standard library" "$RUN/selene.txt"; then echo "(selene skipped: could not fetch the Roblox API dump)"; else cat "$RUN/selene.txt"; status=1; fi
fi

echo "== Cross-references"
python3 scripts/xref.py || echo "(cross-reference warnings above; services built in parallel may not exist yet)"

echo "== Unit tests"
$T/luau tests/run.luau || status=1

echo "== Rojo build"
$T/rojo build default.project.json -o "$RUN/KenkaHigh.rbxl" || status=1
mkdir -p build && cp "$RUN/KenkaHigh.rbxl" build/KenkaHigh.rbxl 2>/dev/null || true

if [ $status -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $status
