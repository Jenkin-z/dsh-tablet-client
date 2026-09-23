"""Cancel regression probe.

Drives the app UI: starts a long turn, waits for the 停止 button, taps it,
then polls the server for that turn's end reason.

Usage:
  python cancel_test.py "<prompt text>"
"""
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ADB = r"E:\Android\Sdk\platform-tools\adb.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
UI_XML = os.path.join(HERE, "_ui.xml")
HOST = "192.168.10.171:3080"
COOKIE = open(os.path.join(HERE, ".cookie"), encoding="ascii").read().strip()
SESSION = "session-ea5af874-cdb7-418c-8c2c-c018ba7d2039"

COMPOSER = (916, 903)   # standard layout, no IME
SEND = (1852, 915)


def sh(*args, timeout=60):
    try:
        return subprocess.run([ADB] + list(args), capture_output=True,
                              text=True, encoding="utf-8", errors="replace",
                              timeout=timeout).stdout or ""
    except subprocess.TimeoutExpired:
        return ""


def composer_text(tree=None):
    tree = tree or dump()
    for n in tree.iter("node"):
        a = n.attrib
        if a.get("class", "").endswith("EditText"):
            return a.get("text") or ""
    return None


def clear_composer():
    """Delete composer contents in small batches.

    A single 80-keyevent burst wedges the emulator's input dispatcher (ANR),
    so delete in chunks and give the system room to breathe.
    """
    for _ in range(10):
        if not composer_text():
            return
        sh("shell", "input", "keyevent", "123")
        time.sleep(0.3)
        for _ in range(8):
            sh("shell", "input", "keyevent", "67")
        time.sleep(0.4)


def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    sh("pull", "/sdcard/ui.xml", UI_XML)
    return ET.parse(UI_XML)


def find(tree, desc=None, text=None):
    for n in tree.iter("node"):
        a = n.attrib
        if desc is not None and a.get("content-desc") == desc:
            return a
        if text is not None and a.get("text") == text:
            return a
    return None


def center(bounds):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not m:
        return None
    x1, y1, x2, y2 = (int(g) for g in m.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def rpc(method, args):
    body = json.dumps({"type": "client-request",
                       "rpcId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                       "method": method, "payload": {"args": args}}).encode()
    req = urllib.request.Request(
        f"http://{HOST}/api/{method}", data=body,
        headers={"Content-Type": "application/json", "Cookie": COOKIE})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def records():
    """Fetch the session journal, retrying with the real cursor if needed."""
    req = {"address": {"kind": "session", "sessionId": SESSION},
           "throughSeq": 999999, "maxMessages": 200}
    val = rpc("session/page", {"request": req})
    result = val.get("result", {})
    if not result.get("ok"):
        err = json.dumps(result.get("error", {}), ensure_ascii=False)
        m = re.search(r"past cursor (\d+)", err)
        if not m:
            print("page error:", err[:160])
            return []
        req["throughSeq"] = int(m.group(1))
        val = rpc("session/page", {"request": req})
        result = val.get("result", {})
    return (result.get("value") or {}).get("records", [])


def turns():
    """Return [(turn, reasonKind|null)] from the session journal."""
    out = []
    for r in records():
        blob = json.dumps(r, ensure_ascii=False)
        m = re.search(r'"turn/start".*?"turn": (\d+)', blob)
        if m:
            out.append([int(m.group(1)), None])
        m = re.search(r'"turn/end".*?"turn": (\d+).*?"kind": "(\w+)"', blob)
        if m:
            t = int(m.group(1))
            for row in reversed(out):
                if row[0] == t:
                    row[1] = m.group(2)
                    break
    return out


def ime_shown():
    out = sh("shell", "dumpsys", "input_method")
    return "mInputShown=true" in out


def close_ime():
    """Close the soft keyboard without risking BACK-exits-activity.

    BACK only dismisses the IME when it is actually shown; otherwise it pops
    the Activity to the launcher, so check first.
    """
    if ime_shown():
        sh("shell", "input", "keyevent", "4")
        time.sleep(2)
    if ime_shown():
        # still up: tap the message area (above the composer) to blur
        sh("shell", "input", "tap", "960", "300")
        time.sleep(2)


def send_prompt(text):
    sh("shell", "input", "tap", str(COMPOSER[0]), str(COMPOSER[1]))
    time.sleep(2)
    clear_composer()
    sh("shell", "input", "text", text.replace(" ", "%s"))
    time.sleep(2)
    close_ime()
    tree = dump()
    node = find(tree, text=text)
    if not node:
        print(f"WARN: composer does not hold {text!r}; aborting send")
        for n in tree.iter("node"):
            if n.attrib.get("class", "").endswith("EditText"):
                print("  composer =", repr(n.attrib.get("text")))
        return False
    sh("shell", "input", "tap", str(SEND[0]), str(SEND[1]))
    return True


def main():
    prompt = sys.argv[1] if len(sys.argv) > 1 else "count slowly 1 to 600"
    before = turns()
    print(f"turns before: {before[-3:]}")

    if not send_prompt(prompt):
        return
    time.sleep(6)

    # Wait for the stop button to appear, then tap it.
    stop_xy = None
    for i in range(20):
        tree = dump()
        node = find(tree, desc="停止")
        if node:
            stop_xy = center(node.get("bounds"))
            print(f"+{i*2}s stop button at {stop_xy}")
            break
        time.sleep(2)
    if not stop_xy:
        print("FAIL: stop button never appeared")
        return

    t0 = time.time()
    sh("shell", "input", "tap", str(stop_xy[0]), str(stop_xy[1]))
    print(f"tapped stop at t=0")

    for i in range(15):
        time.sleep(2)
        tree = dump()
        still = find(tree, desc="停止") is not None
        mid = find(tree, desc="正在停止") is not None
        print(f"  +{time.time()-t0:.0f}s button={'stop' if still else 'gone'}"
              f"{' (canceling)' if mid else ''}")
        if not still:
            break

    time.sleep(4)
    after = turns()
    new = [t for t in after if t not in before]
    print(f"turns after:  {after[-3:]}")
    print(f"new turns:    {new}")


if __name__ == "__main__":
    main()
