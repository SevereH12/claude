"""Loads store_items.json and adds the derived "giftPasses" group: a
"Gift: <pass>" Developer Product for every game pass, at the same price.
Shared by make_icons.py, create_store.py and upload_icons.py."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))

# Which Open Cloud kind each group is created as.
GROUP_KIND = {"passes": "pass", "products": "product", "giftPasses": "product", "boosts": "product"}


def load():
    items = json.load(open(os.path.join(HERE, "store_items.json")))
    items["giftPasses"] = [
        {
            "key": "Gift" + p["key"],
            "pass": p["key"],
            "name": "Gift: " + p["name"],
            "price": p["price"],
            "color": p["color"],
            "description": f"Gift {p['name']} to another player. " + p["description"],
        }
        for p in items["passes"]
    ]
    return items
