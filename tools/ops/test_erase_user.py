#!/usr/bin/env python3
"""Offline test for erase_user.py: runs the erase against a fake Open Cloud
(nothing goes over the network) and checks the right keys are deleted or
cleaned, that --dry-run changes nothing, and that --check passes.

   python3 tools/ops/test_erase_user.py"""
import copy
import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import erase_user as E  # noqa: E402

UID = 111
OTHER = 222

START = {
    ("ds", "StormBottler_PlayerData", f"player_{UID}"): {"volts": 5},
    ("ds", "StormBottler_PlayerData", f"player_{OTHER}"): {"volts": 9},
    ("ds", "StormBottler_Gifts", f"inbox_{UID}"): [{"id": "a", "fromId": OTHER, "fromName": "Bob"}],
    ("ds", "StormBottler_Gifts", f"inbox_{OTHER}"): [
        {"id": "b", "fromId": UID, "fromName": "Al"},
        {"id": "c", "fromId": 333, "fromName": "Cy"},
    ],
    ("ds", "StormBottler_Gifts", "receipt_X"): {"recipientId": UID, "recipientName": "Al"},
    ("ds", "StormBottler_Gifts", "receipt_Y"): {"recipientId": OTHER, "recipientName": "Bob"},
    ("ds", "StormBottler_Invites", f"inviter_{UID}"): {"day": 1, "ids": [OTHER]},
    ("ds", "StormBottler_Invites", f"inviter_{OTHER}"): {"day": 1, "ids": [UID, 333]},
    ("ds", "AdminLog", "day_2026-10-25"): [
        {"by": OTHER, "byName": "Bob", "target": UID, "targetName": "Al", "action": "kick"},
        {"by": OTHER, "byName": "Bob", "target": 333, "targetName": "Cy", "action": "kick"},
    ],
    ("ods", "StormBottler_LB_volts", str(UID)): 50,
    ("ods", "StormBottler_LB_volts", str(OTHER)): 70,
    ("sm", "StormBottler_Notifications", f"000000000000100|{UID}|daily"): {"userId": UID},
    ("sm", "StormBottler_Notifications", f"000000000000100|{OTHER}|daily"): {"userId": OTHER},
}


def fake_curl(data):
    def curl(method, url, body=None, headers=()):
        u = urllib.parse.urlparse(url)
        q = dict(urllib.parse.parse_qsl(u.query))
        path = urllib.parse.unquote(u.path)
        if "/standard-datastores/datastore/entries/entry" in path:
            key = ("ds", q["datastoreName"], q["entryKey"])
            if method == "GET":
                if key not in data:
                    raise E.NotFound(url)
                return copy.deepcopy(data[key])
            if method == "DELETE":
                data.pop(key, None)
                return None
            data[key] = json.loads(body)
            return {}
        if "/standard-datastores/datastore/entries" in path:
            keys = [k[2] for k in data if k[0] == "ds" and k[1] == q["datastoreName"] and k[2].startswith(q["prefix"])]
            return {"keys": [{"key": k} for k in sorted(keys)], "nextPageCursor": ""}
        if "/orderedDataStores/" in path:
            parts = path.split("/")
            key = ("ods", parts[parts.index("orderedDataStores") + 1], parts[-1])
            if key not in data:
                raise E.NotFound(url)
            if method == "DELETE":
                del data[key]
            return {}
        if "/sorted-maps/" in path:
            parts = path.split("/")
            name = parts[parts.index("sorted-maps") + 1]
            if method == "GET":
                return {"items": [{"id": k[2]} for k in data if k[0] == "sm" and k[1] == name]}
            data.pop(("sm", name, parts[-1]), None)
            return None
        raise AssertionError(f"unexpected call {method} {url}")
    return curl


def run(dry):
    data = copy.deepcopy(START)
    E.curl = fake_curl(data)
    cloud = E.Cloud(1, dry)
    E.erase(cloud, UID)
    return data, cloud.changes


def main():
    failures = []

    def expect(ok, what):
        if not ok:
            failures.append(what)

    expect(E.check() == [], f"--check finds problems: {E.check()}")

    data, changes = run(True)
    expect(data == START, "a dry run changed data")
    expect(changes == 9, f"dry run should list 9 changes, listed {changes}")

    data, changes = run(False)
    expect(("ds", "StormBottler_PlayerData", f"player_{UID}") not in data, "profile not deleted")
    expect(("ds", "StormBottler_PlayerData", f"player_{OTHER}") in data, "another profile was deleted")
    expect(("ds", "StormBottler_Gifts", f"inbox_{UID}") not in data, "inbox not deleted")
    inbox = data[("ds", "StormBottler_Gifts", f"inbox_{OTHER}")]
    expect(inbox[0]["fromId"] == 0 and inbox[0]["fromName"] == E.ERASED, "sender not blanked")
    expect(inbox[1]["fromName"] == "Cy", "someone else's gift was blanked")
    expect(("ds", "StormBottler_Gifts", "receipt_X") not in data, "receipt not deleted")
    expect(("ds", "StormBottler_Gifts", "receipt_Y") in data, "another receipt was deleted")
    expect(("ds", "StormBottler_Invites", f"inviter_{UID}") not in data, "invite count not deleted")
    expect(data[("ds", "StormBottler_Invites", f"inviter_{OTHER}")]["ids"] == [333], "invite id not removed")
    log = data[("ds", "AdminLog", "day_2026-10-25")]
    expect(log[0]["target"] == 0 and log[0]["targetName"] == E.ERASED, "admin log target not blanked")
    expect(log[0]["byName"] == "Bob" and log[1]["targetName"] == "Cy", "other admin log entries changed")
    expect(("ods", "StormBottler_LB_volts", str(UID)) not in data, "leaderboard score not deleted")
    expect(("ods", "StormBottler_LB_volts", str(OTHER)) in data, "another score was deleted")
    expect(("sm", "StormBottler_Notifications", f"000000000000100|{UID}|daily") not in data, "reminder not deleted")
    expect(("sm", "StormBottler_Notifications", f"000000000000100|{OTHER}|daily") in data, "other reminder deleted")

    if failures:
        print("FAIL erase_user:")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print("PASS erase_user (dry run changes nothing, real run erases only that user)")


main()
