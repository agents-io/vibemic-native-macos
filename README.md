# VibeMic Native (macOS)

System-wide voice-to-text for macOS. Press PgDn to record, press again to transcribe with OpenAI Whisper and instantly paste into any app.

## How it works

1. Press `PgDn` — recording starts, menu bar icon turns red
2. Press `PgDn` again — audio is sent to OpenAI Whisper
3. Transcribed text is pasted into your currently focused window via clipboard

## Features

- **System-wide** — works in any app, not just VS Code
- **One-key toggle** — PgDn to start/stop recording
- **Instant paste** — clipboard + Cmd+V, no per-character delay
- **Transcript history** — all transcriptions saved, browse and copy from menu bar
- **Browser-based settings** — configure model, language, temperature, etc.
- **Menu bar icon** — idle, recording, transcribing states
- **Multi-language** — Cantonese, English, Mandarin, Japanese, and 97+ other languages
- **Multiple models** — whisper-1, gpt-4o-transcribe, gpt-4o-mini-transcribe

## Requirements

- macOS 11+
- Python 3.8+
- Homebrew
- OpenAI API key with Whisper access

## Quick Start

```bash
# 1. Clone
git clone https://github.com/ithiria894/vibemic-native-macos.git
cd vibemic-native-macos

# 2. Run setup (installs sox via brew + Python packages)
chmod +x setup.sh
./setup.sh

# 3. Open Settings from menu bar icon and set your API key
python3 vibemic.py
```

## Manual Setup

```bash
# System dependencies
brew install sox

# Python dependencies
pip3 install openai rumps pynput Pillow pyobjc-framework-Cocoa

# Run
python3 vibemic.py
```

## macOS Permissions

You **must** grant these permissions in **System Settings > Privacy & Security**:

1. **Accessibility** — for your terminal app (to detect PgDn hotkey and simulate Cmd+V)
2. **Microphone** — for your terminal app (to record audio)

Without these, VibeMic will silently fail with no error message.

## Configuration

Click the menu bar icon and select **Settings** to configure:

| Setting | Description |
|---------|-------------|
| OpenAI API Key | Your `sk-...` key |
| Model | `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` |
| Language | Auto-detect or specify (en, zh, ja, ko, etc.) |
| Prompt | Hint text for Whisper (e.g. expected languages) |
| Temperature | 0 (deterministic) to 1 (creative) |
| Response Format | json, text, srt, verbose_json, vtt |

Settings are saved to `config.json`.

## Menu Bar

- **History** — browse and copy past transcriptions
- **Settings** — open configuration in browser
- **Quit** — stop VibeMic

## How it pastes

Text is copied to clipboard via `pbcopy` and pasted with AppleScript `keystroke "v" using command down`. This is instant regardless of text length and natively supports CJK characters and emoji.

## Related

- [VibeMic VS Code Extension](https://github.com/ithiria894/VibeMic) — voice-to-text inside VS Code
- [VibeMic Native Ubuntu](https://github.com/ithiria894/vibemic-native-ubuntu) — Ubuntu/Linux version

## License

MIT
