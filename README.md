# blurpy

an absolutely unhinged clippy-style menace that watches your Claude Code, Codex,
and pi transcripts and pops up to pitch WorkOS AI initiatives (arc, TARS, Alto,
Wallaby, Atlas) and internal skills instead of whatever you're hand-rolling.

kick off a devin session and he goes full Jurassic Park.

## install

```bash
curl -sL https://raw.githubusercontent.com/nicknisi/blurpy/main/install.sh | bash
```

no prerequisites. uses `ANTHROPIC_API_KEY` if set,
falls back to `claude -p`, falls further back to just the nedry gag.

## uninstall

```bash
~/.blurpy/uninstall.sh
```

Or remotely:

```bash
curl -fsSL https://raw.githubusercontent.com/nicknisi/blurpy/main/install.sh | bash -s -- uninstall
```

Both kill the process and remove `~/.blurpy` (binary + logs) and `~/.config/blurpy` (optional avatar override). No launch agent or other files are installed.

## develop

```bash
swift build
swift test
.build/debug/blurpy   # run in foreground, watch stdout
```

pitch sheet: `Sources/blurpy/Resources/pitches.json` — edit and rebuild.
override the nedry image: drop a PNG at `~/.config/blurpy/nedry.png`.
