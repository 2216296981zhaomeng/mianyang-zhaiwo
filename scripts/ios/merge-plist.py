#!/usr/bin/env python3
"""Deep-merge a UTS plugin Info.plist into the host Info.plist."""
import plistlib
import sys


def merge(dst, src, bundle_id):
    for key, value in src.items():
        if key == "CFBundleURLTypes" and isinstance(value, list):
            existing = dst.setdefault(key, [])
            for item in value:
                item = dict(item)
                if item.get("CFBundleURLName") == "com.tcwang.agent":
                    item["CFBundleURLName"] = bundle_id
                if item not in existing:
                    existing.append(item)
        elif isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], value, bundle_id)
        elif isinstance(value, list) and isinstance(dst.get(key), list):
            for item in value:
                if item not in dst[key]:
                    dst[key].append(item)
        else:
            dst[key] = value


def main():
    host, plugin, bundle_id = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(host, "rb") as f:
        dst = plistlib.load(f)
    with open(plugin, "rb") as f:
        src = plistlib.load(f)
    merge(dst, src, bundle_id)
    with open(host, "wb") as f:
        plistlib.dump(dst, f)
    print(f"merged {plugin} -> {host}")


if __name__ == "__main__":
    main()
