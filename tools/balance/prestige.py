#!/usr/bin/env python3
"""Works out the researcher promotion numbers (Config.RESEARCH_PRESTIGE)
from the game's own zones, bottles, boots and strike settings, and checks
Config against them (within 10%). Run it whenever zones, bottles or strike
settings change:

  python3 tools/balance/prestige.py

The aim: your whole team is ready to follow you about halfway through each
new zone.

* Time in a zone: the Volts for the bottles up to the next zone's bottle,
  divided by a realistic grinding rate there (Util/Afk's grinding formula
  times EFFICIENCY, for selling trips and missed rings), with the bottle
  that opens the zone and BOOTS_BY_RANK boots. The last zone is END_GAME
  minutes.
* Data for level 5 at the rank below (-> dataScale): what a researcher
  earns from halfway through the previous zone (you're there: every strike
  landing gives 1, and each one you catch 2 more) to halfway through the
  new one (you've moved on, they can't follow yet: 1 per strike). Divided
  by today's level-5 data (RESEARCH_LEVELS[5]).
* Glints per promotion (-> glintCost): the bolts you catch in the new
  zone's first half, split across TEAM researchers.
"""

import json
import math
import os
import subprocess
import sys

EFFICIENCY = 0.6  # of Util/Afk's grinding rate: selling trips, missed rings
BOOTS_BY_RANK = [0, 3, 4, 6, 7, 9, 10]  # speed bonus at each zone tier's stage
END_GAME = 20  # minutes in the last zone
TEAM = 5  # researchers sharing the Glints
TOLERANCE = 0.10  # Config must be within this of the suggestion

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")


def load_config():
    out = subprocess.run(
        ["lune", "run", "tools/balance/config_dump.luau"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(out[out.index("{") :])


def main():
    cfg = load_config()
    zones = [z for z in cfg["zones"] if not z["premium"]]
    tiers = sorted({z["requiresBottle"] for z in zones})
    bottles, boots = cfg["bottles"], cfg["boots"]
    share = cfg["STORM_DURATION"] / (cfg["STORM_DURATION"] + cfg["CALM_DURATION"])
    inset = 2 * (cfg["STRIKE_RADIUS"] + 2)

    def speed_for(bonus):
        # the boots with this speed bonus (or the closest below)
        best = 0
        for b in boots:
            if b["speedBonus"] <= bonus:
                best = b["speedBonus"]
        return cfg["WALK_SPEED_IN_ZONE"] + best

    stages = []
    for rank, bottle_tier in enumerate(tiers):
        # the best zone this bottle opens (what you'd grind)
        zone = max(
            (z for z in zones if z["requiresBottle"] <= bottle_tier),
            key=lambda z: z["chargeValue"],
        )
        capacity = bottles[bottle_tier - 1]["capacity"]
        strikes = math.ceil(capacity / zone["chargeSize"])
        bag = capacity / zone["chargeSize"] * zone["chargeValue"]
        bonus = BOOTS_BY_RANK[min(rank, len(BOOTS_BY_RANK) - 1)]
        reach = cfg["STRIKE_RADIUS"] + speed_for(bonus) * cfg["WARNING_TIME"]
        area = max(zone["width"] - inset, 1) * max(zone["depth"] - inset, 1)
        chance = min(1.0, math.pi * reach * reach / area)
        fill = strikes * zone["strikeInterval"] / chance / share
        rate = bag / fill * EFFICIENCY  # Volts per second
        landing = share / zone["strikeInterval"]  # strikes per second there
        catching = rate / zone["chargeValue"]  # bolts you catch per second
        if rank + 1 < len(tiers):
            cost = sum(b["price"] for b in bottles[bottle_tier : tiers[rank + 1]])
            seconds = cost / rate
        else:
            seconds = END_GAME * 60
        stages.append(
            dict(rank=rank, zone=zone["name"], seconds=seconds, landing=landing, catching=catching)
        )

    level5 = cfg["RESEARCH_LEVELS"][-1]
    prestige = cfg["RESEARCH_PRESTIGE"]
    ok = True
    print(f"{'rank':>4}  {'unlocks':<18} {'time':>7}  {'data':>7} {'scale':>6} {'config':>6}  {'glints':>6} {'config':>6}")
    for rank in range(1, len(stages)):
        before, new = stages[rank - 1], stages[rank]
        data = (before["landing"] + 2 * before["catching"]) * before["seconds"] / 2 + before[
            "landing"
        ] * new["seconds"] / 2
        scale = data / level5
        glints = new["catching"] * new["seconds"] / 2 / TEAM
        have_scale = prestige["dataScale"][rank - 1]
        have_cost = prestige["glintCost"][rank - 1] if rank - 1 < len(prestige["glintCost"]) else None
        suggest_scale = round(scale * 20) / 20
        suggest_cost = int(round(glints / 5) * 5)
        bad_scale = abs(have_scale - scale) > TOLERANCE * scale
        bad_cost = have_cost is None or abs(have_cost - glints) > TOLERANCE * glints
        ok = ok and not bad_scale and not bad_cost
        print(
            f"{rank:>4}  {new['zone']:<18} {new['seconds'] / 60:>5.0f} m  {data:>7.0f} {scale:>6.2f} {have_scale:>6}"
            f"{' !' if bad_scale else '  '}{glints:>6.0f} {str(have_cost):>6}{' !' if bad_cost else ''}"
            f"   suggest {suggest_scale}x, {suggest_cost} Glints"
        )
    top = len(stages) - 1
    if len(prestige["dataScale"]) < top + 1:
        print(f"dataScale needs {top + 1} entries (one per rank, the last repeats at the top)")
        ok = False
    if len(prestige["glintCost"]) != top:
        print(f"glintCost needs {top} entries (one per promotion)")
        ok = False
    if not ok:
        print(f"FAIL: Config.RESEARCH_PRESTIGE is more than {TOLERANCE:.0%} off (marked !)")
        sys.exit(1)
    print(f"ok: Config.RESEARCH_PRESTIGE is within {TOLERANCE:.0%} of the targets")


if __name__ == "__main__":
    main()
