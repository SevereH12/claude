"""Creates the game passes and Volts packs from store_items.json through
Roblox Open Cloud, skipping any that already exist (matched by name), and
writes their ids to store_ids.json. Everything is created OFF SALE: turn
items on sale once the game code for them is live.
   python3 tools/store/create_store.py <universeId> <iconDir>
The API key is sent as the x-api-key header from $ROBLOX_API_KEY, or added
by the network proxy when that variable isn't set."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://apis.roblox.com"
KINDS = {
    "passes": ("game-passes/v1/universes/{u}/game-passes", "gamePasses", "gamePassId"),
    "products": ("developer-products/v2/universes/{u}/developer-products", "developerProducts", "productId"),
}


def curl(args):
    key = os.environ.get("ROBLOX_API_KEY")
    header = ["-H", f"x-api-key: {key}"] if key else []
    out = subprocess.run(["curl", "-sS", "-m", "60", "-w", "\n%{http_code}", *header, *args],
                         capture_output=True, text=True)
    body, _, code = out.stdout.rpartition("\n")
    if not code.startswith("2"):
        raise SystemExit(f"HTTP {code}: {body or out.stderr}")
    return json.loads(body) if body.strip() else {}


def existing(path, listKey, idKey):
    found, token = {}, ""
    while True:
        page = curl([f"{API}/{path}/creator?pageSize=50" + (f"&pageToken={token}" if token else "")])
        for item in page.get(listKey) or []:
            found[item["name"]] = item.get(idKey) or item.get("id")
        token = page.get("nextPageToken")
        if not token:
            return found


def main():
    universe, icons = sys.argv[1], sys.argv[2]
    items = json.load(open(os.path.join(HERE, "store_items.json")))
    ids = {"universeId": int(universe), "passes": {}, "products": {}}
    for group, (path, listKey, idKey) in KINDS.items():
        path = path.format(u=universe)
        have = existing(path, listKey, idKey)
        for item in items[group]:
            if item["name"] in have:
                ids[group][item["key"]] = have[item["name"]]
                print(f"exists   {item['name']}: {have[item['name']]}")
                continue
            form = ["-F", f"name={item['name']}", "-F", f"description={item['description']}",
                    "-F", f"price={item['price']}", "-F", "isForSale=false",
                    "-F", "isRegionalPricingEnabled=true"]
            icon = os.path.join(icons, f"{item['key']}.png")
            if os.path.exists(icon):
                form += ["-F", f"imageFile=@{icon};type=image/png"]
            made = curl(["-X", "POST", f"{API}/{path}", *form])
            ids[group][item["key"]] = made[idKey]
            print(f"created  {item['name']}: {made[idKey]}")
    with open(os.path.join(HERE, "store_ids.json"), "w") as f:
        json.dump(ids, f, indent=2)
        f.write("\n")
    print("ids written to tools/store/store_ids.json")


main()
