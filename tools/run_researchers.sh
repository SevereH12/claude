#!/bin/sh
# Builds the Researchers feature by running each part in
# docs/prompts/researchers in order, one fresh Claude Code session per part
# (each part is sized to fit in one usage limit).
#   tools/run_researchers.sh
# Parts already ticked in the README are skipped, so after a usage limit or
# a failed part just run it again: it carries on where it stopped.
# Needs the Claude Code CLI (`claude`) and push access to the repo.
set -eu
cd "$(git rev-parse --show-toplevel)"

DIR=docs/prompts/researchers
README="$DIR/README.md"

# Every part must land on the branch the Studio updater pulls from.
UPDATE_BRANCH=$(sed -n 's/^local BRANCH = "\(.*\)"$/\1/p' plugin/StormBottlerUpdater.server.luau)
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "$UPDATE_BRANCH" ]; then
	echo "You're on '$BRANCH' but Update Game pulls '$UPDATE_BRANCH'. Switch to it first."
	exit 1
fi

done_part() {
	grep -q "^- \[x\] Part $1:" "$README"
}

for n in 1 2 3 4 5; do
	if done_part "$n"; then
		echo "== part $n: already done"
		continue
	fi
	file=$(ls "$DIR"/part-"$n"-*.md)
	echo "== part $n: $file"
	git pull --ff-only
	claude -p "Do $file. If the working tree has uncommitted changes from an earlier attempt at this part, continue from them instead of starting over." \
		--permission-mode acceptEdits \
		--allowedTools "Read" "Edit" "Write" "Glob" "Grep" \
		"Bash(git *)" "Bash(stylua *)" "Bash(selene *)" "Bash(lune *)" "Bash(rokit *)" \
		"Bash(python3 *)" "Bash(tools/check_world.sh *)" "Bash(sh tools/check_world.sh *)" \
		"Bash(mkdir *)" "Bash(ls *)" || true
	if ! done_part "$n"; then
		echo "== part $n didn't finish. Run tools/run_researchers.sh again to retry it."
		exit 1
	fi
done
echo "== all parts done. Open Studio and click Update Game."
