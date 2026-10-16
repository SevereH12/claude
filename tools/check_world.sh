#!/bin/sh
# Builds, tests, walk-checks and renders one world style.
#   tools/check_world.sh <Style> [outdir]
# Needs `lune` (or LUNE=/path/to/lune) and python3 with Pillow.
# Exits non-zero if any check fails. Images: <outdir>/<Style>_top.png,
# <Style>_side.png, <Style>_walk.png.
set -u
STYLE="${1:?usage: tools/check_world.sh <Style> [outdir]}"
OUT="${2:-.}"
LUNE="${LUNE:-lune}"
mkdir -p "$OUT"
status=0
echo "== build $STYLE"
"$LUNE" run tools/harness/buildmap.luau "$OUT/$STYLE.json" "$STYLE" || status=1
echo "== gameplay tests"
"$LUNE" run tools/harness/test_gameplay.luau "$STYLE" || status=1
if [ -f "$OUT/$STYLE.json" ]; then
	echo "== walkability"
	python3 tools/walkcheck.py "$OUT/$STYLE.json" "$OUT/$STYLE" || status=1
	echo "== render"
	python3 tools/render_map.py "$OUT/$STYLE.json" "$OUT/$STYLE" || status=1
fi
if [ "$status" -eq 0 ]; then echo "== ALL CHECKS PASSED ($STYLE)"; else echo "== CHECKS FAILED ($STYLE)"; fi
exit $status
