"""UI dump helper: dump the emulator screen and print a compact element table.

Usage:
  python ui.py            # dump + print all elements with text/desc
  python ui.py --raw      # also print nodes without text/desc (ids only)
"""
import io
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ADB = r"E:\Android\Sdk\platform-tools\adb.exe"
TMP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_ui.xml")


def sh(*args):
    return subprocess.run([ADB] + list(args), capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout or ""


def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    sh("pull", "/sdcard/ui.xml", TMP)


def center(bounds):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not m:
        return None
    x1, y1, x2, y2 = (int(g) for g in m.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def main():
    dump()
    raw = "--raw" in sys.argv
    tree = ET.parse(TMP)
    rows = []
    for node in tree.iter("node"):
        a = node.attrib
        text = (a.get("text") or "").strip()
        desc = (a.get("content-desc") or "").strip()
        rid = (a.get("resource-id") or "").split("/")[-1]
        if not (text or desc) and not raw:
            continue
        c = center(a.get("bounds"))
        rows.append((
            c[0] if c else -1, c[1] if c else -1,
            a.get("class", "").split(".")[-1],
            text, desc, rid,
            a.get("selected"), a.get("enabled") == "true",
            a.get("clickable") == "true", a.get("bounds"),
        ))
    rows.sort(key=lambda r: (r[1], r[0]))
    print(f"{'x':>5} {'y':>5} {'class':<22} {'en':<2} {'clk':<4} text / desc")
    for x, y, cls, text, desc, rid, sel, en, clk, b in rows:
        label = text or desc
        if desc and text and desc != text:
            label = f"{text} | {desc}"
        print(f"{x:>5} {y:>5} {cls:<22} {'Y' if en else 'n':<2} "
              f"{'Y' if clk else '-':<4} {label}")
    print(f"-- {len(rows)} nodes")


if __name__ == "__main__":
    main()
