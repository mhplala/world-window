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

node - <<'JS'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  try {
    await page.goto('https://mhplala.github.io/world-window/', { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(3000);
    const broken = await page.evaluate(() => Array.from(document.images)
      .map((img, i) => ({ i, src: img.getAttribute('src'), currentSrc: img.currentSrc, naturalWidth: img.naturalWidth, complete: img.complete }))
      .filter(x => x.complete && x.naturalWidth === 0));
    if (broken.length) {
      console.error('[world-window] ERROR: broken images on live site');
      for (const item of broken) console.error('[world-window] ERROR:', JSON.stringify(item));
      process.exit(1);
    }
    console.log('[world-window] browser verification OK: broken images = 0');
  } finally {
    await browser.close();
  }
})().catch(err => {
  console.error('[world-window] ERROR: browser verification failed:', err.message || err);
  process.exit(1);
});
JS
