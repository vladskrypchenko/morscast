#!/usr/bin/env python3
# MorsCast fork: shows "MorsCast" wherever the UI says "Tinycast", without touching Swift sources.
# Idempotent; after a rebase that conflicts in a catalog, take upstream's file and run this again.
import json
import re
import sys
from pathlib import Path

OLD, NEW = "Tinycast", "MorsCast"
ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "Tinycast/Resources/Localizable.xcstrings",
    ROOT / "Tinycast/Resources/InfoPlist.xcstrings",
]


def rebrand(node):
    if isinstance(node, str):
        return node.replace(OLD, NEW)
    if isinstance(node, dict):
        return {key: rebrand(value) for key, value in node.items()}
    if isinstance(node, list):
        return [rebrand(value) for value in node]
    return node


def rebrand_catalog(path):
    catalog = json.loads(path.read_text())
    source = catalog.get("sourceLanguage", "en")
    for key, entry in catalog["strings"].items():
        if OLD not in key and OLD not in json.dumps(entry.get("localizations", {})):
            continue
        localizations = entry.setdefault("localizations", {})
        # The key is the English text, so English needs its own entry to show the new name.
        if source not in localizations:
            localizations[source] = {"stringUnit": {"state": "translated", "value": key}}
        entry["localizations"] = rebrand(localizations)
    text = json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : "), sort_keys=True)
    text = re.sub(r'(\n( *)"[^"\n]*" : )\{\}', lambda m: m.group(1) + "{\n\n" + m.group(2) + "}", text)
    path.write_text(text + "\n")


for catalog in CATALOGS:
    rebrand_catalog(catalog)
print("Rebranded", ", ".join(c.name for c in CATALOGS), file=sys.stderr)
