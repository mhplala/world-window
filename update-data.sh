#!/bin/bash
set -euo pipefail

REPO_DIR="/Users/stevewang/.openclaw/workspace-atom/fortune/world-window"
cd "$REPO_DIR"

echo "[world-window] repo: $REPO_DIR"
echo "[world-window] time: $(date '+%F %T %Z')"

if [ ! -f data.json ]; then
  echo "[world-window] ERROR: data.json not found" >&2
  exit 1
fi

python3 - <<'PY'
import json, pathlib, sys
from PIL import Image

p = pathlib.Path('data.json')
try:
    data = json.loads(p.read_text(encoding='utf-8'))
except Exception as e:
    print(f"[world-window] ERROR: invalid JSON: {e}", file=sys.stderr)
    raise

if not isinstance(data, list):
    print("[world-window] ERROR: data.json root is not a list", file=sys.stderr)
    sys.exit(1)
if not data:
    print("[world-window] ERROR: data.json is empty", file=sys.stderr)
    sys.exit(1)

latest = max(data, key=lambda x: x.get('date', ''))
print(f"[world-window] latest entry by date: {latest.get('date')} | {latest.get('title')}")

errors = []
checked = 0
for item in data:
    image = item.get('image')
    if not image:
        continue
    ip = pathlib.Path(image)
    if not ip.exists():
        errors.append(f"missing image for {item.get('date')}: {image}")
        continue
    suffix = ip.suffix.lower()
    if suffix == '.svg':
        checked += 1
        continue
    try:
        with Image.open(ip) as img:
            fmt = (img.format or '').lower()
            img.verify()
    except Exception as e:
        errors.append(f"unreadable image for {item.get('date')}: {image} ({e})")
        continue
    if fmt == 'jpeg' and suffix not in ('.jpg', '.jpeg'):
        errors.append(f"format mismatch for {item.get('date')}: {image} is jpeg")
    elif fmt == 'png' and suffix != '.png':
        errors.append(f"format mismatch for {item.get('date')}: {image} is png")
    checked += 1

if errors:
    print('[world-window] ERROR: image validation failed', file=sys.stderr)
    for err in errors:
        print(f"[world-window] ERROR: {err}", file=sys.stderr)
    sys.exit(1)

print(f"[world-window] image validation OK: checked {checked} images")
PY

git add data.json images index.html

pushed=0
if git diff --cached --quiet; then
  echo "[world-window] no changes to commit"
else
  commit_msg="📚 update $(date +%Y-%m-%d)"
  git commit -m "$commit_msg"
  git push origin main
  echo "[world-window] pushed: $commit_msg"
  pushed=1
fi

if [ "$pushed" -eq 1 ]; then
  echo "[world-window] waiting for GitHub Pages..."
  sleep 8
else
  echo "[world-window] no push this run, still verifying live site"
fi

python3 - <<'PY'
import json, sys, urllib.request
from urllib.parse import urljoin
from PIL import Image
from io import BytesIO

BASE = 'https://mhplala.github.io/world-window/'
DATA_URL = urljoin(BASE, 'data.json')
raw = urllib.request.urlopen(DATA_URL, timeout=60).read().decode('utf-8')
data = json.loads(raw)

seen = []
for item in data:
    src = item.get('image')
    if src and src not in seen:
        seen.append(src)

broken = []
for src in seen:
    url = urljoin(BASE, src)
    try:
        data = urllib.request.urlopen(url, timeout=60).read()
        if src.lower().endswith('.svg'):
            if b'<svg' not in data[:500].lower():
                broken.append({'src': src, 'reason': 'not svg content'})
            continue
        img = Image.open(BytesIO(data))
        img.verify()
    except Exception as e:
        broken.append({'src': src, 'reason': str(e)})

if broken:
    print('[world-window] ERROR: broken images on live site', file=sys.stderr)
    for item in broken:
        print('[world-window] ERROR:', json.dumps(item, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)

print(f'[world-window] browser-style verification OK: broken images = 0, checked {len(seen)} images')
PY
