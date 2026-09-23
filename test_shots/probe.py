"""DSH server probe: auth, list sessions, dump one session's journal.

Usage:
  python probe.py sessions                 # list sessions (id, title, running)
  python probe.py page <sessionId> [limit] # dump journal records
  python probe.py find <titleSubstring>    # find session id by title
"""
import io
import json
import os
import re
import sys
import urllib.request
import urllib.error

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

HOST = "192.168.10.171:3080"
TOKEN = "cQ-ARblge1OrWRemiVM5lREqL96RKwcGTWNijkAhD34"
UUID = "11111111-2222-3333-4444-555555555555"


class NoRedir(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


COOKIE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cookie")


def auth_cookie():
    """Prefer the app's live cookie (30d) saved by the tester; else use the
    launch token to exchange for a fresh one."""
    if os.path.exists(COOKIE_FILE):
        saved = open(COOKIE_FILE, encoding="ascii").read().strip()
        if saved:
            return saved
    url = f"http://{HOST}/?token={TOKEN}"
    op = urllib.request.build_opener(NoRedir)
    try:
        op.open(url)
    except urllib.error.HTTPError as e:
        cookie = e.headers.get("Set-Cookie")
        if cookie:
            return cookie.split(";")[0]
        raise
    raise RuntimeError("no Set-Cookie on auth redirect")


def rpc(method, args, cookie):
    body = json.dumps({
        "type": "client-request",
        "rpcId": UUID,
        "method": method,
        "payload": {"args": args},
    }).encode()
    req = urllib.request.Request(
        f"http://{HOST}/api/{method}",
        data=body,
        headers={"Content-Type": "application/json", "Cookie": cookie},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode())
    result = data.get("result", {})
    if not result.get("ok"):
        raise RuntimeError(f"{method} failed: {result.get('error')}")
    return result.get("value") or {}


def main():
    cookie = auth_cookie()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sessions"

    if cmd == "sessions":
        items = rpc("session/list", {"_request": {}}, cookie).get("items", [])
        for s in items:
            title = (s.get("title") or "")[:44]
            print(f"{s.get('sessionId')} run={str(s.get('running')):5} "
                  f"{title!r}")
        print(f"-- {len(items)} sessions")

    elif cmd == "find":
        needle = sys.argv[2]
        items = rpc("session/list", {"_request": {}}, cookie).get("items", [])
        for s in items:
            if needle in (s.get("title") or ""):
                print(s.get("sessionId"), repr(s.get("title")))

    elif cmd == "page":
        sid = sys.argv[2]
        limit = int(sys.argv[3]) if len(sys.argv) > 3 else 40
        req = {"address": {"kind": "session", "sessionId": sid},
               "throughSeq": 999999, "maxMessages": limit}
        try:
            val = rpc("session/page", {"request": req}, cookie)
        except RuntimeError as e:
            m = re.search(r"past cursor (\d+)", str(e))
            if not m:
                print("ERR", e)
                return
            req["throughSeq"] = int(m.group(1))
            val = rpc("session/page", {"request": req}, cookie)
        records = val.get("records", [])
        for r in records:
            seq = r.get("seq")
            kind = r.get("kind") or r.get("type")
            payload = r.get("payload") or r
            text = ""
            if isinstance(payload, dict):
                msg = payload.get("message") or payload
                content = msg.get("content") if isinstance(msg, dict) else None
                if isinstance(content, list):
                    text = " ".join(p.get("text", "") for p in content
                                    if isinstance(p, dict))
                elif isinstance(content, str):
                    text = content
                if not text:
                    text = json.dumps(payload, ensure_ascii=False)
            print(f"[{seq}] {kind}: {text[:150]!r}")
        print(f"-- {len(records)} records")

    else:
        print(__doc__)


if __name__ == "__main__":
    main()
