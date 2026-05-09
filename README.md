# Claudy

A macOS notch companion that reacts to Claude Code activity in real-time.

Personal fork of [sk-ruban/notchi](https://github.com/sk-ruban/notchi) — rebranded as Claudy with extra activity surfaces and Sparkle auto-update disabled so the upstream feed cannot replace this build.

## What it does

- Reacts to Claude Code events in real-time (thinking, working, errors, completions)
- Collapsed activity strip under the notch showing `verb · tool · arg · elapsed` while a session is working, compacting, or waiting
- Bottom activity panel pinned to the bottom of the screen for a wider view of session activity
- Analyzes conversation sentiment to show emotions (happy, sad, neutral, sob)
- Click to expand and see session time and usage quota
- Supports multiple concurrent Claude Code sessions with individual sprites
- Sound effects for events (optional, auto-muted when terminal is focused)

## Requirements

- macOS 15.0+ (Sequoia)
- MacBook with notch
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Xcode (for building from source — no prebuilt releases)

## Build & install

The repo lives in `~/Documents/Dev/Claudy`. `~/Documents` is iCloud-synced, which stamps `com.apple.FinderInfo` on build artifacts and breaks codesign. Build to `/tmp` instead:

```sh
cd ~/Documents/Dev/Claudy/notchi
xcodebuild -project notchi.xcodeproj -scheme notchi -configuration Release -derivedDataPath /tmp/claudy-build
cp -R /tmp/claudy-build/Build/Products/Release/Claudy.app /Applications/Claudy.app
```

Re-sign Sparkle ad-hoc to match the app's identity (otherwise dyld rejects with "different Team IDs"):

```sh
codesign --force --deep --sign - /Applications/Claudy.app/Contents/Frameworks/Sparkle.framework
codesign --force --deep --sign - /Applications/Claudy.app
```

Then launch:

```sh
open /Applications/Claudy.app
```

On first launch a macOS keychain popup will ask to access Claude Code's cached OAuth token (used for API usage stats). Click **Always Allow**.

*(Optional)* Click the notch → Settings → paste an Anthropic API key to enable prompt-sentiment analysis.

## How it works

```
Claude Code --> Hooks (shell scripts) --> Unix Socket --> Event Parser --> State Machine --> Animated Sprites
```

Claudy registers shell script hooks with Claude Code on launch. When Claude Code emits events (tool use, thinking, prompts, session start/end), the hook script sends JSON payloads to a Unix socket. The app parses these events, runs them through a state machine that maps to sprite animations (idle, working, sleeping, compacting, waiting), and uses the Anthropic API to analyze user prompt sentiment for emotional reactions.

Each Claude Code session gets its own sprite on the grass island. Clicking expands the notch panel to show a live activity feed, session info, and API usage stats. The collapsed strip and bottom panel surface the same activity outside of the expanded view.

## Project layout

- Bundle id: `com.hinevics.claudy`
- Internal Xcode target/scheme is still `notchi`; source folder is still `notchi/` (only display name, bundle id, and `PRODUCT_NAME` were renamed to Claudy).
- Code signing is ad-hoc (`CODE_SIGN_IDENTITY = "-"`) — no Apple Developer account needed.

## Credits

- [notchi](https://github.com/sk-ruban/notchi) by [@sk-ruban](https://github.com/sk-ruban) — upstream this is forked from
- [Claude Island](https://github.com/farouqaldori/claude-island) — design inspiration
- [Readout](https://readout.org) — design inspiration
- [Aseprite](https://www.aseprite.org/) — sprite design

## License

GPL-3.0-only. See [LICENSE](LICENSE).
