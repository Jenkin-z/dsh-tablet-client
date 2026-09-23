# -*- coding: utf-8 -*-
"""Download the Android 34 google_apis x86_64 system image zip with resume + SHA1 verify."""
import hashlib
import os
import re
import sys
import time
import urllib.request

META = "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml"
PKG = "system-images;android-34;google_apis;x86_64"
DEST_DIR = os.environ.get(
    "SYSIMG_DEST", os.path.join(os.environ.get("TEMP", "."), "sysimg_dl")
)


def fetch(url: str, dest: str | None = None) -> bytes:
    last = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = r.read()
            if dest:
                with open(dest, "wb") as f:
                    f.write(data)
            return data
        except Exception as e:  # noqa: BLE001
            last = e
            print(f"fetch attempt {attempt + 1} failed: {e}", flush=True)
            time.sleep(2)
    raise RuntimeError(f"fetch failed: {last}")


def main() -> int:
    print("fetching metadata...", flush=True)
    xml = fetch(META).decode("utf-8", "replace")
    m = re.search(
        r'<remotePackage path="' + re.escape(PKG) + r'"[\s\S]*?</remotePackage>', xml
    )
    if not m:
        print("package block not found in metadata", flush=True)
        return 1
    block = m.group(0)
    url_m = re.search(r"<url>([^<]+)</url>", block)
    size_m = re.search(r"<size>(\d+)</size>", block)
    ck_m = re.search(r'<checksum type="([^"]+)">([^<]+)</checksum>', block)
    if not (url_m and size_m and ck_m):
        print("metadata fields missing", flush=True)
        return 1
    rel_url, expect_size = url_m.group(1), int(size_m.group(1))
    ck_type, expect_ck = ck_m.group(1), ck_m.group(2)
    url = "https://dl.google.com/android/repository/sys-img/google_apis/" + rel_url
    print(f"url={url}\nsize={expect_size}\nck={ck_type}:{expect_ck}", flush=True)

    os.makedirs(DEST_DIR, exist_ok=True)
    dest = os.path.join(DEST_DIR, os.path.basename(rel_url))

    # Resume until size matches, then hash.
    for round_no in range(1, 12):
        have = os.path.getsize(dest) if os.path.exists(dest) else 0
        if have >= expect_size:
            break
        print(f"round {round_no}: have {have}/{expect_size}, resuming...", flush=True)
        req = urllib.request.Request(url, headers={"Range": f"bytes={have}-"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                status = r.status
                mode = "ab" if status == 206 else "wb"
                if status != 206:
                    have = 0
                    print("server ignored Range, restarting file", flush=True)
                with open(dest, mode) as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
        except Exception as e:  # noqa: BLE001
            print(f"resume attempt failed: {e}", flush=True)
            time.sleep(3)

    size = os.path.getsize(dest)
    print(f"final size={size} expect={expect_size}", flush=True)
    if size != expect_size:
        print("SIZE MISMATCH", flush=True)
        return 2

    print("hashing...", flush=True)
    h = hashlib.sha1() if ck_type == "sha1" else hashlib.sha256()
    with open(dest, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    got = h.hexdigest()
    print(f"got={got}", flush=True)
    if got.lower() != expect_ck.lower():
        print("CHECKSUM MISMATCH - delete file and rerun for full redownload", flush=True)
        return 3
    print("OK: image zip downloaded and verified", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
