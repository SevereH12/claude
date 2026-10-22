"""Replaces the icon of every pass and Volts pack in store_ids.json with the
matching <key>.png from make_icons.py. Only the image changes; prices and
sale status stay as they are.
   python3 tools/store/upload_icons.py <iconDir>
The API key is sent as the x-api-key header from $ROBLOX_API_KEY, or added
by the network proxy when that variable isn't set."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://apis.roblox.com"
from items import GROUP_KIND

PATHS = {
    "pass": "game-passes/v1/universes/{u}/game-passes/{id}",
    "product": "developer-products/v2/universes/{u}/developer-products/{id}",
}


def main():
    icons = sys.argv[1]
    ids = json.load(open(os.path.join(HERE, "store_ids.json")))
    key = os.environ.get("ROBLOX_API_KEY")
    header = ["-H", f"x-api-key: {key}"] if key else []
    failed = 0
    for group, kind in GROUP_KIND.items():
        path = PATHS[kind]
        for name, item_id in ids.get(group, {}).items():
            url = f"{API}/" + path.format(u=ids["universeId"], id=item_id)
            icon = os.path.join(icons, f"{name}.png")
            out = subprocess.run(
                ["curl", "-sS", "-m", "60", "-o", "/dev/null", "-w", "%{http_code}", *header,
                 "-X", "PATCH", url, "-F", f"imageFile=@{icon};type=image/png"],
                capture_output=True, text=True)
            ok = out.stdout.startswith("2")
            failed += 0 if ok else 1
            print(f"{'updated' if ok else 'FAILED '} {name}: HTTP {out.stdout} {out.stderr.strip()}")
    sys.exit(1 if failed else 0)


main()
