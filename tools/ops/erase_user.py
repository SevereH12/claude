#!/usr/bin/env python3
"""Erases one Roblox user's data from every store the game uses (a
"right to erasure" request), through Open Cloud.

   python3 tools/ops/erase_user.py <userId> [--dry-run] [--universe ID]
   python3 tools/ops/erase_user.py --check

--dry-run only reads: it prints every key it would delete or clean, and
changes nothing. ALWAYS run it with --dry-run first and read the list.
--check only checks that this script knows every store the game's code
opens (it fails if src/ uses a DataStore, OrderedDataStore or MemoryStore
that isn't in STORES below). It also runs before every erase.

What gets erased for user <id> (see STORES):
  StormBottler_PlayerData  player_<id>       the save: deleted
  StormBottler_Gifts       inbox_<id>        their gift inbox: deleted
                           receipt_*         gift receipts naming them as the
                                             receiver: deleted
                           inbox_* (others)  gifts they sent: their name and
                                             id are blanked (the gift stays)
  StormBottler_Invites     inviter_<id>      their invite count: deleted
                           inviter_* (others) their id is taken out of others'
                                             invite lists
  AdminLog                 day_*             log entries by or about them:
                                             name and id blanked
  StormBottler_LB_<board>  <id>              their leaderboard scores: deleted
  StormBottler_Notifications (MemoryStore sorted map) items "<due>|<id>|<kind>":
                                             deleted
Bans (Players:BanAsync) are kept by Roblox, not by this game.

The API key: sent as x-api-key from $ROBLOX_API_KEY, or added by the network
proxy when that variable isn't set (like tools/store/create_store.py). It
needs the DataStores (read, list, write, delete), Ordered DataStores and
MemoryStore sorted map scopes for the universe."""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
API = "https://apis.roblox.com"
UNIVERSE = 10772352394
ERASED = "[erased]"

# Every store the game opens. "kind": DataStore, OrderedDataStore or
# SortedMap (MemoryStore). A name ending in "*" is a prefix: one store per
# leaderboard board (Config.LEADERBOARDS.boards).
STORES = {
    "StormBottler_PlayerData": "DataStore",
    "StormBottler_Gifts": "DataStore",
    "StormBottler_Invites": "DataStore",
    "AdminLog": "DataStore",
    "StormBottler_LB_*": "OrderedDataStore",
    "StormBottler_Notifications": "SortedMap",
}
BOARDS = ("volts", "bolts", "ascension", "streak")


# Keeping the list complete ---------------------------------------------------------

CALL = re.compile(r":(GetDataStore|GetOrderedDataStore|GetGlobalDataStore|GetSortedMap|GetQueue|GetHashMap)\(([^)]*)\)")
KIND = {"GetDataStore": "DataStore", "GetOrderedDataStore": "OrderedDataStore", "GetSortedMap": "SortedMap"}


def config_string(config, field):
    found = re.findall(rf"\b{field}\s*=\s*\"([^\"]*)\"", config)
    if len(set(found)) != 1:
        raise ValueError(f"Config.{field} isn't one plain string")
    return found[0]


def resolve(arg, source, config):
    """The store name a Get*Store(...) argument means, or raises."""
    arg = arg.strip()
    m = re.fullmatch(r"\"([^\"]*)\"", arg)
    if m:
        return m.group(1)
    m = re.fullmatch(r"([A-Z_][A-Z0-9_]*)", arg)
    if m:
        local = re.findall(rf"local {m.group(1)}\s*=\s*\"([^\"]*)\"", source)
        if len(local) == 1:
            return local[0]
    m = re.fullmatch(r"SETTINGS\.(\w+)(\s*\.\.\s*\w+)?", arg)
    if m:
        return config_string(config, m.group(1)) + ("*" if m.group(2) else "")
    raise ValueError(f"can't tell which store `{arg}` is")


def check():
    """Problems (as text) if src/ opens a store this script doesn't know."""
    config = open(os.path.join(ROOT, "src", "shared", "Config.luau")).read()
    problems = []
    for folder, _, files in os.walk(os.path.join(ROOT, "src")):
        for name in files:
            if not name.endswith(".luau"):
                continue
            path = os.path.join(folder, name)
            source = open(path).read()
            for method, arg in CALL.findall(source):
                where = os.path.relpath(path, ROOT)
                if method not in KIND:
                    problems.append(f"{where}: {method} isn't handled by erase_user.py")
                    continue
                try:
                    store = resolve(arg, source, config)
                except ValueError as err:
                    problems.append(f"{where}: {err}")
                    continue
                if STORES.get(store) != KIND[method]:
                    problems.append(f"{where}: {KIND[method]} {store!r} isn't in erase_user.py STORES")
    block = config.split("LEADERBOARDS = table.freeze(", 1)[1].split("NOTIFICATIONS =", 1)[0]
    boards = tuple(re.findall(r"key = \"(\w+)\"", block))
    if boards != BOARDS:
        problems.append(f"Config.LEADERBOARDS.boards is {boards}, erase_user.py BOARDS is {BOARDS}")
    return problems


# Open Cloud -------------------------------------------------------------------------


class NotFound(Exception):
    pass


def curl(method, url, body=None, headers=()):
    key = os.environ.get("ROBLOX_API_KEY")
    args = ["curl", "-sS", "-m", "60", "-X", method, "-w", "\n%{http_code}"]
    if key:
        args += ["-H", f"x-api-key: {key}"]
    for h in headers:
        args += ["-H", h]
    if body is not None:
        args += ["--data-binary", "@-"]
    out = subprocess.run(args + [url], input=body, capture_output=True, text=True)
    text, _, code = out.stdout.rpartition("\n")
    if code == "404":
        raise NotFound(url)
    if not code.startswith("2"):
        raise SystemExit(f"{method} {url}\nHTTP {code}: {text or out.stderr}")
    return json.loads(text) if text.strip() else None


class Cloud:
    def __init__(self, universe, dry):
        self.u = universe
        self.dry = dry
        self.changes = 0

    def _ds(self, path, **query):
        q = urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
        return f"{API}/datastores/v1/universes/{self.u}/standard-datastores{path}?{q}"

    def keys(self, store, prefix):
        count = 0
        for key in self._keys(store, prefix):
            count += 1
            yield key
        print(f"  checked       {store} / {prefix}* ({count} key(s))")

    def _keys(self, store, prefix):
        cursor = None
        while True:
            try:
                page = curl("GET", self._ds("/datastore/entries", datastoreName=store, prefix=prefix, limit=100,
                                            cursor=cursor))
            except NotFound:  # the store hasn't been written yet
                return
            for k in page.get("keys") or []:
                yield k["key"]
            cursor = page.get("nextPageCursor")
            if not cursor:
                return

    def get(self, store, key):
        try:
            return curl("GET", self._ds("/datastore/entries/entry", datastoreName=store, entryKey=key))
        except NotFound:
            return None

    def delete(self, store, key, why):
        self.changes += 1
        print(f"  {'would delete' if self.dry else 'deleted'}  {store} / {key}  ({why})")
        if not self.dry:
            try:
                curl("DELETE", self._ds("/datastore/entries/entry", datastoreName=store, entryKey=key))
            except NotFound:
                pass

    def put(self, store, key, value, why):
        self.changes += 1
        print(f"  {'would clean' if self.dry else 'cleaned'}   {store} / {key}  ({why})")
        if not self.dry:
            body = json.dumps(value, separators=(",", ":"))
            md5 = base64.b64encode(hashlib.md5(body.encode()).digest()).decode()
            curl("POST", self._ds("/datastore/entries/entry", datastoreName=store, entryKey=key), body,
                 ["content-type: application/json", f"content-md5: {md5}"])

    def ordered_delete(self, store, key, why):
        url = f"{API}/ordered-data-stores/v1/universes/{self.u}/orderedDataStores/{urllib.parse.quote(store)}" \
              f"/scopes/global/entries/{urllib.parse.quote(key)}"
        try:
            curl("GET", url)
        except NotFound:
            print(f"  none          {store} / {key}")
            return
        self.changes += 1
        print(f"  {'would delete' if self.dry else 'deleted'}  {store} / {key}  ({why})")
        if not self.dry:
            curl("DELETE", url)

    def sorted_map_items(self, name):
        base = f"{API}/cloud/v2/universes/{self.u}/memory-store/sorted-maps/{urllib.parse.quote(name)}/items"
        token = None
        while True:
            q = urllib.parse.urlencode({"maxPageSize": 100, **({"pageToken": token} if token else {})})
            try:
                page = curl("GET", f"{base}?{q}") or {}
            except NotFound:
                return
            for item in page.get("items") or []:
                yield base, item
            token = page.get("nextPageToken")
            if not token:
                return

    def sorted_map_delete(self, base, item_id, why):
        self.changes += 1
        print(f"  {'would delete' if self.dry else 'deleted'}  sorted map item {item_id}  ({why})")
        if not self.dry:
            try:
                curl("DELETE", f"{base}/{urllib.parse.quote(item_id, safe='')}")
            except NotFound:
                pass


# The erase -----------------------------------------------------------------------------


def erase(cloud, uid):
    sid = str(uid)

    print("StormBottler_PlayerData")
    if cloud.get("StormBottler_PlayerData", f"player_{uid}") is not None:
        cloud.delete("StormBottler_PlayerData", f"player_{uid}", "their saved profile")
    else:
        print(f"  none          StormBottler_PlayerData / player_{uid}")

    print("StormBottler_Gifts")
    for key in cloud.keys("StormBottler_Gifts", "inbox_"):
        if key == f"inbox_{uid}":
            cloud.delete("StormBottler_Gifts", key, "their gift inbox")
            continue
        entries = cloud.get("StormBottler_Gifts", key)
        if isinstance(entries, list) and any(isinstance(e, dict) and e.get("fromId") == uid for e in entries):
            for e in entries:
                if isinstance(e, dict) and e.get("fromId") == uid:
                    e["fromId"], e["fromName"] = 0, ERASED
            cloud.put("StormBottler_Gifts", key, entries, "gifts they sent: sender blanked")
    for key in cloud.keys("StormBottler_Gifts", "receipt_"):
        marker = cloud.get("StormBottler_Gifts", key)
        if isinstance(marker, dict) and marker.get("recipientId") == uid:
            cloud.delete("StormBottler_Gifts", key, "a gift receipt naming them")

    print("StormBottler_Invites")
    for key in cloud.keys("StormBottler_Invites", "inviter_"):
        if key == f"inviter_{uid}":
            cloud.delete("StormBottler_Invites", key, "their invite count")
            continue
        record = cloud.get("StormBottler_Invites", key)
        if isinstance(record, dict) and uid in (record.get("ids") or []):
            record["ids"] = [i for i in record["ids"] if i != uid]
            cloud.put("StormBottler_Invites", key, record, "they were someone's invite")

    print("AdminLog")
    for key in cloud.keys("AdminLog", "day_"):
        log = cloud.get("AdminLog", key)
        if not isinstance(log, list):
            continue
        hit = False
        for e in log:
            if not isinstance(e, dict):
                continue
            if e.get("by") == uid:
                e["by"], e["byName"], hit = 0, ERASED, True
            if e.get("target") == uid:
                e["target"], e["targetName"], hit = 0, ERASED, True
        if hit:
            cloud.put("AdminLog", key, log, "admin log entries by or about them: blanked")

    for board in BOARDS:
        store = f"StormBottler_LB_{board}"
        print(store)
        cloud.ordered_delete(store, sid, f"their {board} score")

    print("StormBottler_Notifications (MemoryStore)")
    seen = 0
    for base, item in cloud.sorted_map_items("StormBottler_Notifications"):
        seen += 1
        item_id = item.get("id") or item.get("path", "").rsplit("/", 1)[-1]
        item_id = urllib.parse.unquote(item_id)
        if f"|{uid}|" in item_id:
            cloud.sorted_map_delete(base, item_id, "a phone reminder for them")
    print(f"  checked       sorted map StormBottler_Notifications, items *|{uid}|* ({seen} item(s))")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("user_id", nargs="?", type=int)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--universe", type=int, default=UNIVERSE)
    args = parser.parse_args()
    problems = check()
    if problems:
        print("erase_user.py doesn't know every store the game uses:")
        for p in problems:
            print("  " + p)
        print("Add the new store to STORES (and to erase()) before erasing anything.")
        sys.exit(1)
    if args.check:
        print(f"erase_user.py knows every store in src/ ({len(STORES)} stores, {len(BOARDS)} boards)")
        return
    if not args.user_id or args.user_id <= 0:
        parser.error("give the Roblox user id to erase")
    cloud = Cloud(args.universe, args.dry_run)
    mode = "DRY RUN: nothing will change" if args.dry_run else "ERASING"
    print(f"{mode}. User {args.user_id}, universe {args.universe}\n")
    erase(cloud, args.user_id)
    verb = "would change" if args.dry_run else "changed"
    print(f"\nDone: {verb} {cloud.changes} key(s) for user {args.user_id}.")


if __name__ == "__main__":
    main()
