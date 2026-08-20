#!/usr/bin/env bash
# blurpy installer. Install:  curl -sL <raw-url>/install.sh | bash
# Uninstall:                  curl -sL <raw-url>/install.sh | bash -s uninstall
set -euo pipefail

DEST="$HOME/.blurpy"
BIN="$DEST/blurpy"
URL="https://github.com/nicknisi/blurpy/releases/latest/download/blurpy-macos-arm64"

if [[ "${1:-}" == "uninstall" ]]; then
  pkill -f "$BIN" 2>/dev/null && echo "blurpy stopped." || true
  rm -rf "$DEST" "$HOME/.config/blurpy"
  echo "blurpy is gone. process, files, logs, and overrides removed."
  exit 0
fi

mkdir -p "$DEST"
echo "summoning blurpy..."
curl -sL --fail -o "$BIN" "$URL" || { echo "summon failed — is the release up?"; exit 1; }
chmod +x "$BIN"

# keep a local uninstall around for when the network is far away
cat > "$DEST/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
pkill -f "$HOME/.blurpy/blurpy" 2>/dev/null && echo "blurpy stopped." || true
rm -rf "$HOME/.blurpy" "$HOME/.config/blurpy"
echo "blurpy is gone. process, files, logs, and overrides removed."
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
