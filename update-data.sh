#!/bin/bash
# Update world-window data.json and push to GitHub Pages
# Called after generating new knowledge content

cd /Users/stevewang/.openclaw/workspace-atom/fortune/world-window

# Stage, commit, push
git add data.json
git commit -m "📚 update $(date +%Y-%m-%d)" 2>/dev/null
git push origin main 2>/dev/null

echo "✅ world-window updated and pushed"
