# Prompt 17: tutorial, friends, leaderboards and notifications

Follow the rules in `docs/prompts/README.md`. **Run it twice**; each run
does the first unticked part, then ticks it.

- [x] Part A: the new-player tutorial, the friends boost and invites
- [x] Part B: leaderboards and phone notifications

**Needs prompt 16 part A**: `src/shared/Util/Stats.luau` must exist. If it
doesn't, stop and tell the user.

## Part A: tutorial, friends boost, invites (run 1)

### Read only

- in `src/server/Systems/Analytics.luau`: `ONBOARDING` and `onboard`.
  The tutorial steps match those funnel steps.
- `src/client/Lib/Layout.luau` and, in `src/client/Lib/UI.luau`, grep
  `toast`
- `src/shared/Util/ResearchSites.luau` and `Util/Zones.luau`
- `src/shared/Util/Passes.luau` (`sellMultiplier`)
- in `src/server/Systems/Gifts.luau`: the inbox write (to credit offline
  inviters)
- in `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE` and
  `MIGRATIONS`

### Build

1. **Tutorial**, for first-time players only (`tutorialStep` saved in the
   profile, so it resumes after a rejoin):
   1. Walk to Shoreline. A glowing Beam path leads from the player to the
      gate.
   2. Catch 3 bolts. If it's calm, explain the storm timer.
   3. When the bottle is full, a path leads to the sell pad.
   4. Open the menu, go to the Shop and buy the Vial (pointing at each
      button in turn).
   5. Finish with "You're a Storm Bottler!" and a 50-charge reward.

   - **Step cards**: one short line each, placed with the device layout
     rules.
   - **Skipping**: a SKIP button, which asks "Skip the tutorial?" first.
   - **Old players**: anyone who already owns a Vial or better is never
     shown it.
2. **Friends boost**: +5% Volts for each Roblox friend in your server, up
   to 3 (+15%).
   - **Checking**: on the server, with `Player:IsFriendsWith`, cached and
     re-checked as players join and leave.
   - **Applying it**: through `Passes.sellMultiplier`. Add a friend count to
     the effects set; don't add a fake pass flag.
   - **HUD**: a small chip, "👥 +10% friends".
3. **Invites**: an INVITE button in the REWARDS panel.
   - **The prompt**: `SocialService:PromptGameInvite`, after checking
     `CanSendGameInviteAsync`.
   - **Rewarding the inviter**: when a **new** player (no saved profile yet)
     joins with `Player:GetJoinData().ReferredByPlayerId`, the inviter gets
     a reward. The new player gets a welcome gift (100 charges).
     - **If the inviter is offline**, the reward goes to their gift inbox,
       so they get it later.
     - **Abuse limits**: 5 rewarded invites per inviter per day, and only
       for Roblox accounts at least 3 days old (`Player.AccountAge`).
4. **Tests**: `tools/harness/test_social.luau` covers:
   - tutorial step changes and skipping
   - the friend count and its cap
   - the invite rules (new players only, the daily cap, account age)

## Part B: leaderboards and notifications (run 2)

### Read only

- `src/shared/Util/Stats.luau`, and grep `ascension` and `dailyStreak` in
  `src/shared/Types.luau`
- `src/client/Controllers/RewardsUI.luau`
- in `src/server/World/Kit.luau`: grep `sign`
- in `src/server/World/Styles/WeatherLab/Hub.luau`: grep `fingerpost`
  (spawn-side placement)
- `src/server/Systems/Rewards.luau` (daily and streak timing)

### Build

1. **Leaderboards**: OrderedDataStores for:
   - all-time Volts
   - bolts caught
   - Ascension level
   - longest login streak

   - **Writing**: each player's values every 5 min and on leave, throttled,
     with `pcall` and backoff.
   - **Reading**: each server reads the top 50 every 2 min and caches it.
   - **Showing them**: a TOP tab in the REWARDS panel, with tabs for each
     board, avatars, and "You: #N" (or "not in the top 50" with their own
     value).
   - **A physical board** with SurfaceGui text beside world 1's spawn,
     placed like the fingerpost and clear of the boardwalk corridors. It
     shows the all-time Volts top 10. Check it with
     `tools/render_view.py --signs`.
2. **Notifications** (Roblox experience notifications):
   - **Opting in**: after a player's first daily claim, ask "Remind me when
     my daily reward is ready?" with
     `ExperienceNotificationService:PromptOptIn`. Ask once, never again
     after a no.
   - **Queueing**: on leave, queue "daily reward ready" (the next UTC day)
     and "streak ends soon" (3 h before it would break) in a MemoryStore
     sorted map, keyed by due time.
   - **Sending**: any running server sends due items each minute, claiming
     each item atomically so it's only sent once.
   - **The API**: send through the Open Cloud user notifications API.
     **Check the current docs first** for whether game servers may call it
     with `HttpService` and a key from `HttpService:GetSecret`.
   - **If the setup is missing** (game servers aren't allowed to call it,
     or the secret or message ids aren't set), skip sending, log once, and
     tell the user exactly what to set up: the secret name, and the
     notification templates under Engagement on the Creator Dashboard, with
     their ids in Config.
3. **Tests**: extend `test_social.luau` with the notification queue timing
   and the "only send once" claim.

## Done means (every part)

- stylua and selene are clean; the tests and existing harness tests pass.
- `tools/check_world.sh Game` passes (including the sign check for part
  B).
- In Studio (if the MCP is connected), a fresh profile sees the tutorial;
  the TOP tab shows test data. Studio can't do real invites or
  notifications; check the log lines.
- Tick the part, commit and push.
