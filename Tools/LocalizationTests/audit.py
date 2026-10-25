#!/usr/bin/env python3
"""Check bilingual resource completeness and interpolation safety."""
import collections
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
catalog = json.loads((root / "Sapphire/Resources/Localizable.xcstrings").read_text())
assert catalog["sourceLanguage"] == "en"
formats = re.compile(r"%(?:\d+\$)?(?:\d+)?(?:\.\d+)?(?:ll|l|h)?[@diufFeEgG%]")
for key, entry in catalog["strings"].items():
    locales = entry["localizations"]
    assert set(locales) == {"en", "zh-Hans"}, f"Unexpected or missing language: {key}"
    assert locales["en"]["stringUnit"]["value"] == key, f"English fallback changed: {key}"
    translation = locales["zh-Hans"]["stringUnit"]["value"]
    assert translation, f"Empty translation: {key}"
    assert collections.Counter(formats.findall(key)) == collections.Counter(formats.findall(translation)), f"Interpolation mismatch: {key}"

for key in ["Language", "Follow System", "General", "Screenshots", "Collect immediately",
            "Keep floating preview", "Keep until I remove", "Show Sports widget in the notch",
            "Finance", "Pin", "Unpin", "Quit Sapphire"]:
    assert catalog["strings"][key]["localizations"]["zh-Hans"]["stringUnit"]["value"] != key, key

print(f"PASS: {len(catalog['strings'])} complete English/Chinese entries; format arguments preserved")
