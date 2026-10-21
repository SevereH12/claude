#!/bin/sh
# Builds, tests, walk-checks and renders the game, or one world style.
#   tools/check_world.sh [Game|<Style>] [outdir]
# "Game" (the default) builds every world in Config.WORLDS; a style name
# builds only the first world's zones in that style (to review a style).
# Needs `lune` (or LUNE=/path/to/lune) and python3 with Pillow.
# Exits non-zero if any check fails. Each world is checked on its own, with
# images <outdir>/<name>_top.png, <name>_side.png and <name>_walk.png, where
# <name> is <Style> for the first world and <Style>_<WorldId> for the others.
set -u
STYLE="${1:-Game}"
OUT="${2:-.}"
LUNE="${LUNE:-lune}"
mkdir -p "$OUT"
rm -f "$OUT/$STYLE.json" "$OUT/${STYLE}"_*.json
status=0
echo "== build $STYLE"
"$LUNE" run tools/harness/buildmap.luau "$OUT/$STYLE.json" "$STYLE" || status=1
echo "== gameplay tests"
"$LUNE" run tools/harness/test_gameplay.luau "$STYLE" || status=1
for json in "$OUT/$STYLE.json" "$OUT/${STYLE}"_*.json; do
	[ -f "$json" ] || continue
	name="${json%.json}"
	echo "== walkability ($(basename "$name"))"
	python3 tools/walkcheck.py "$json" "$name" || status=1
	echo "== flicker ($(basename "$name"))"
	python3 tools/flickercheck.py "$json" || status=1
	echo "== render ($(basename "$name"))"
	python3 tools/render_map.py "$json" "$name" || status=1
done
if [ "$status" -eq 0 ]; then echo "== ALL CHECKS PASSED ($STYLE)"; else echo "== CHECKS FAILED ($STYLE)"; fi
exit $status
