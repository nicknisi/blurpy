#!/usr/bin/env bash
# blurpy installer. Install:  curl -sL <raw-url>/install.sh | bash
# Uninstall:                  curl -sL <raw-url>/install.sh | bash -s uninstall
set -euo pipefail

REPO="workos/blurpy"
DEST="$HOME/.blurpy"
BIN="$DEST/blurpy"

if [[ "${1:-}" == "uninstall" ]]; then
  pkill -f "$BIN" 2>/dev/null && echo "blurpy stopped." || true
  rm -rf "$DEST"
  echo "blurpy is gone. he was never here."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "blurpy needs gh to download: brew install gh && gh auth login"
  exit 1
fi

mkdir -p "$DEST"
echo "summoning blurpy..."
gh release download --repo "$REPO" --pattern "blurpy-macos-*" --clobber --output "$BIN"
chmod +x "$BIN"

# keep a local uninstall around for when the network is far away
cat > "$DEST/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
pkill -f "$HOME/.blurpy/blurpy" 2>/dev/null && echo "blurpy stopped." || true
rm -rf "$HOME/.blurpy"
echo "blurpy is gone. he was never here."
EOF
chmod +x "$DEST/uninstall.sh"

pkill -f "$BIN" 2>/dev/null || true
nohup "$BIN" > "$DEST/blurpy.log" 2>&1 &
disown

echo ""
echo "blurpy is installed and watching your transcripts. he is always here."
echo "brain: ANTHROPIC_API_KEY if set, otherwise claude -p, otherwise nedry-only."
echo "log: $DEST/blurpy.log"
echo "uninstall: $DEST/uninstall.sh   (or re-run this script with 'uninstall')"
