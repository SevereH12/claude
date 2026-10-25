# Brief for agents running the feature prompts

Read this before running a prompt part. It holds the standing rules and the
user's decisions, so a fresh session can carry on where the last stopped.

## The job

- Run **one part**: the first unticked part (`- [ ]`) of the prompt you
  were given in `docs/prompts/`. Follow that prompt and
  `docs/prompts/README.md` exactly. When the part is done, tick it
  (`- [x]`), commit and push.
- Repo `/home/user/claude`, branch `claude/sweet-planck-ea1ob4` (the user's
  Update Game plugin pulls from it). Never push anywhere else, never force
  push, never open a PR.
- Read `CLAUDE.md` first (layout, conventions, the map rules, the tools).
- Commit messages end with exactly:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01JJg6X9h56YUZ9j4g2tvwoa
  ```

  No model names anywhere else (code, comments, docs).
- Commit and push as you go if a part is big (it survives a stopped
  session), but tick the part only when its "Done means" holds.

## Checks (run all before the final push)

```
export PATH=/root/.local/bin:$PATH
stylua src
selene --config tools/lint/selene-offline.toml src   # the repo's selene.toml needs a download that's blocked here
for t in tools/harness/test_*.luau; do ...; done     # test_layout takes an output path, test_gameplay takes Game
tools/check_world.sh Game <outdir>                   # after any map, zone or world change
```

The harness can't load modules that touch `Players.PlayerRemoving` at load
time (`Lib/RateLimit`) or client UI controllers: that's known. Keep game
logic in pure `Util/` modules so it can be tested.

There is no Roblox Studio connection in these sessions: skip the "In
Studio" checks and list them in your report instead.

## Standing rules

- Balance numbers live in `src/shared/Config.luau`.
- A profile shape change: bump `CURRENT_VERSION`, add a migration, update
  `DEFAULT_PROFILE` (and a test for the migration).
- Every client->server remote is rate-limited and validated
  (`Systems/Shop.luau` is the pattern). Server owns all state.
- Don't put game passes or products on sale, and don't change prices:
  everything stays off sale until the user says otherwise.
- Settings go through `Util/Settings` and `Lib/SettingsStore`; sounds
  through `Lib/Sfx` (no new sound uploads); UI through `Lib/UI` and
  `Lib/Layout` (the layout test must pass).
- Write for a beginner: comments and README sections in plain words.

## The user's decisions

- **Admins** (prompt 18): the group owner, Studio, and Super Studio group
  (7889739) ranks **200 and up** (`Config.ADMIN_RANK = 200`).
- **Private servers** (prompt 18): turn them on at **100 Robux a month**.
- **Store art** (prompt 18): make the icon and thumbnails, then **upload
  them automatically** if the API key allows it (no need to wait); show
  them in the report.
- **Double Volts Weekend** (prompt 15): **on**, every Saturday 00:00 to
  Sunday 23:59 UTC.
- Music must be **instrumental only** (no lyrics):
  `tools/audio/music_search.py` enforces it.

## Your report

End with: what you built, the commit hashes, the checks you ran and their
results, anything you couldn't do and why, and the "what to check in
Studio" steps for the user (numbered, plain words).
