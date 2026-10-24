#!/usr/bin/env python3
"""Finds background music for each world and weather in Roblox's licensed
partner catalogues (creators APMOfficial and DistrokidOfficial, which any
game may use) with the Creator Store search API, and writes the shortlist:

  python3 tools/audio/music_search.py

- docs/audio/music-shortlist.md: 6 candidates per slot (id, title, artist,
  length, the query that found it)
- tools/audio/music.json: the same, as data
- src/shared/MusicShortlist.luau: every candidate, for the Studio audition
  (TEST > REWARDS > Music audition)

The game plays Config.MUSIC: put the picks there (the top 3 per slot to
start with, printed at the end)."""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
URL = "https://apis.roblox.com/toolbox-service/v2/assets:search"
CREATORS = {"APMOfficial", "DistrokidOfficial"}
MIN_SECONDS = 90
PER_SLOT = 6
CONFIG_PICKS = 3
# not background music for this game: stings, songs with words, holidays, moody
# or sleepy pieces, drones, other games' names, and titles moderation hid ("###")
SKIP_WORDS = (
    "sting", "vocal", "lyric", "christmas", "xmas", "halloween", "sad", "horror", "drone",
    "minecraft", "fortnite", "roblox", "novel", "reading", "sleep", "meditation", "lofi", "ninja", "#",
)

WORLD_NAMES = {"Bay": "Barometer Bay", "Voltcliff": "Voltcliff Works", "Stormspire": "Stormspire Isles"}

# "<world id>_<Calm|Storm>" -> the queries searched for it (best first)
SLOTS = {
    "Bay_Calm": ["sunny playful", "playful adventure", "light adventure", "seaside", "happy ukulele"],
    "Bay_Storm": ["driving electronic", "energetic electronic", "synth action", "electro chase", "upbeat synth"],
    "Voltcliff_Calm": ["steampunk", "clockwork", "quirky mechanical", "groovy funk", "quirky"],
    "Voltcliff_Storm": ["industrial electronic", "intense electronic", "industrial action", "intense electronic rock", "dubstep action"],
    "Stormspire_Calm": ["airy uplifting", "soaring adventure", "dreamy flight", "floating islands", "whimsical"],
    "Stormspire_Storm": ["epic electronic", "epic action electronic", "sky battle", "heroic synth", "epic chase"],
}


def search(query, pages=2):
    found, token = [], None
    for _ in range(pages):
        body = {"searchCategoryType": "Audio", "query": query, "maxPageSize": 50}
        if token:
            body["pageToken"] = token
        out = subprocess.run(
            ["curl", "-sS", "-m", "60", "-X", "POST", URL, "-H", "Content-Type: application/json", "-d", json.dumps(body)],
            capture_output=True, text=True, check=True,
        ).stdout
        data = json.loads(out)
        found += data.get("creatorStoreAssets") or []
        token = data.get("nextPageToken")
        if not token:
            break
    return found


def keep(item):
    asset, creator = item.get("asset") or {}, (item.get("creator") or {}).get("name")
    title = (asset.get("title") or asset.get("name") or "").lower()
    return (
        creator in CREATORS
        and asset.get("audioType") == "Music"
        and (asset.get("durationSeconds") or 0) >= MIN_SECONDS
        and not any(word in title for word in SKIP_WORDS)
    )


def main():
    used = set()
    result = {}
    for slot, queries in SLOTS.items():
        scored = {}
        for qi, query in enumerate(queries):
            for rank, item in enumerate(search(query)):
                if not keep(item):
                    continue
                asset = item["asset"]
                entry = scored.setdefault(asset["id"], {
                    "id": asset["id"],
                    "title": asset.get("title") or asset.get("name"),
                    "artist": asset.get("artist") or "",
                    "creator": item["creator"]["name"],
                    "seconds": asset["durationSeconds"],
                    "genre": asset.get("genre") or "",
                    "query": query,
                    "score": 0.0,
                })
                # found by more queries, earlier, and by better queries: higher
                entry["score"] += 1.0 / (1 + rank * 0.15) / (1 + qi * 0.25)
        ranked = [e for e in sorted(scored.values(), key=lambda e: -e["score"]) if e["id"] not in used]
        result[slot] = ranked[:PER_SLOT]
        used.update(e["id"] for e in result[slot])
        print(f"{slot}: {len(scored)} found, kept {len(result[slot])}", file=sys.stderr)

    with open(os.path.join(HERE, "music.json"), "w") as f:
        json.dump(result, f, indent=1)
        f.write("\n")
    os.makedirs(os.path.join(ROOT, "docs", "audio"), exist_ok=True)
    with open(os.path.join(ROOT, "docs", "audio", "music-shortlist.md"), "w") as f:
        f.write("# Music shortlist\n\n")
        f.write("Licensed tracks from Roblox's partner catalogues (APMOfficial and\n"
                "DistrokidOfficial), found by `tools/audio/music_search.py`. The top 3 of\n"
                "each slot are in `Config.MUSIC`. Listen to them in Studio with TEST >\n"
                "REWARDS > **Music audition**, then say which to keep.\n")
        for slot, tracks in result.items():
            world, phase = slot.split("_")
            f.write(f"\n## {WORLD_NAMES[world]}, {phase.lower()}\n\n")
            f.write("| # | Id | Title | Artist | Length | Found by |\n| --- | --- | --- | --- | --- | --- |\n")
            for i, t in enumerate(tracks, 1):
                m, s = divmod(int(t["seconds"]), 60)
                pick = " (in Config)" if i <= CONFIG_PICKS else ""
                f.write(f"| {i}{pick} | {t['id']} | {t['title']} | {t['artist']} ({t['creator']}) | {m}:{s:02d} | \"{t['query']}\" |\n")
    lines = []
    for slot, tracks in result.items():
        for t in tracks:
            title = t["title"].replace("\\", "").replace('"', "'")
            lines.append(f'\t{{ slot = "{slot}", id = {t["id"]}, title = "{title}" }},')
    with open(os.path.join(ROOT, "src", "shared", "MusicShortlist.luau"), "w") as f:
        f.write(
            "--!strict\n"
            "-- Every music candidate tools/audio/music_search.py found (see\n"
            "-- docs/audio/music-shortlist.md), for the Studio Music audition. The game\n"
            "-- itself plays Config.MUSIC. Generated: don't edit by hand.\n\n"
            "export type Track = { slot: string, id: number, title: string }\n\n"
            "local MusicShortlist: { Track } = {\n" + "\n".join(lines) + "\n}\n\n"
            "return table.freeze(MusicShortlist)\n"
        )
    print("wrote docs/audio/music-shortlist.md, tools/audio/music.json, src/shared/MusicShortlist.luau", file=sys.stderr)
    print("\nConfig.MUSIC picks (the top 3 per slot):")
    for slot, tracks in result.items():
        print(f"  {slot}: " + ", ".join(f"{t['id']} ({t['title']})" for t in tracks[:CONFIG_PICKS]))


if __name__ == "__main__":
    main()
