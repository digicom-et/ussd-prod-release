#!/bin/bash
# Push ussdgw-prod-release to github.com/digicom-et/ussd-prod-release
set -e

REPO_DIR="/home/meodien/Desktop/ethiopia-working-dir/ussdgw-prod-release"
cd "$REPO_DIR"

echo "=== Current branch ==="
git branch --show-current

echo ""
echo "=== Working tree status ==="
git status --short
if [ -z "$(git status --short)" ]; then
    echo "✓ Working tree clean"
else
    echo "! Uncommitted changes detected. Commit them first:"
    echo "  git add -A && git commit -m 'your message'"
    exit 1
fi

echo ""
echo "=== Recent commits ==="
git log --oneline -5

echo ""
echo "=== Remote ==="
git remote -v

echo ""
echo "=== Pushing to origin/main ==="
GIT_TERMINAL_PROMPT=0 git push origin main

echo ""
echo "=== Done! ==="
