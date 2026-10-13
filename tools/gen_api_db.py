#!/usr/bin/env python3
"""Builds tests/mock/api.json.gz from Roblox's API-Dump.json (Roblox-Client-Tracker).

Usage: python3 tools/gen_api_db.py path/to/API-Dump.json
The compact database lets the Lune mock runtime reject members that do not exist in Roblox.
"""
import gzip, json, sys

def main(path):
    dump = json.load(open(path, encoding="utf-8"))
    classes = {}
    for cls in dump["Classes"]:
        props, events, funcs, callbacks = {}, [], [], []
        for m in cls.get("Members", []):
            name, kind = m["Name"], m["MemberType"]
            tags = m.get("Tags", []) or []
            if kind == "Property":
                vt = m.get("ValueType", {})
                readonly = "ReadOnly" in tags or (isinstance(m.get("Security"), dict) and m["Security"].get("Write") not in ("None", "PluginSecurity"))
                props[name] = [vt.get("Category", ""), vt.get("Name", ""), 1 if "ReadOnly" in tags else 0]
            elif kind == "Event":
                events.append(name)
            elif kind == "Function":
                funcs.append(name)
            elif kind == "Callback":
                callbacks.append(name)
        classes[cls["Name"]] = {
            "s": cls.get("Superclass", ""),
            "t": [t for t in (cls.get("Tags") or []) if isinstance(t, str)],
            "p": props, "e": events, "f": funcs, "c": callbacks,
        }
    enums = {}
    for enum in dump.get("Enums", []):
        enums[enum["Name"]] = [item["Name"] for item in enum.get("Items", [])]
    out = {"version": dump.get("Version"), "classes": classes, "enums": enums}
    data = json.dumps(out, separators=(",", ":")).encode()
    with gzip.open("tests/mock/api.json.gz", "wb", compresslevel=9) as f:
        f.write(data)
    print(f"classes={len(classes)} raw={len(data)} gz written")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/root/tools/defs/API-Dump.json")
